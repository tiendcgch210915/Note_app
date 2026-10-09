import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/dashboard.dart';
import '../models/habit.dart';
import '../models/tag.dart';
import '../models/todo.dart';
import '../utils/daily_score_calculator.dart';
import '../utils/date_utils.dart';
import '../utils/json_utils.dart';
import '../utils/todo_time_utils.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_storage.dart';
import 'habits_repository.dart';
import 'local/database.dart';
import 'todos_repository.dart';

/// Repository cho Group D — Dashboard. 3 endpoint F-D1/F-D2/F-D3.
class DashboardRepository {
  DashboardRepository._({AppDatabase? database})
    : _db = database ?? AppDatabase.instance;
  static final DashboardRepository instance = DashboardRepository._();

  /// Chỉ để test các đường đọc Drift (`localCalendarDayDetail`...): không dựng
  /// kết nối SQLite thật của app. Các hàm dùng `TodosRepository.instance` hay
  /// `HabitsRepository.instance` (ví dụ `localTodayData`) vẫn chạm singleton
  /// nên chưa test được qua đây.
  @visibleForTesting
  factory DashboardRepository.forTesting(AppDatabase database) =>
      DashboardRepository._(database: database);

  final ApiClient _client = ApiClient.instance;
  final AppDatabase _db;

  String get _userId =>
      AuthStorage.instance.currentUserJson?['id'] as String? ?? '';

  bool _belongsToCurrentUser(String rowUserId) {
    final userId = _userId;
    return userId.isEmpty || rowUserId == userId;
  }

  /// F-D1 Today summary.
  Future<DashboardSnapshot> today({DateTime? date}) async {
    final localDate = AppDateUtils.dateOnly(date ?? DateTime.now());
    final resp = await _client.get(
      '/dashboard/today',
      query: {'date': formatDateOnly(localDate)},
    );
    return DashboardSnapshot.fromJson(resp as Map<String, dynamic>);
  }

  Future<bool> hasPendingLocalWrites() async {
    return (await _db.syncDao.getPendingCount()) > 0;
  }

  Future<
    ({
      DashboardSnapshot snapshot,
      EisenhowerDetail eisenhower,
      List<Habit> habits,
      Map<DateTime, Map<String, bool>> todayCal,
      bool hasData,
    })
  >
  localTodayData({DateTime? date}) async {
    final localDate = AppDateUtils.dateOnly(date ?? DateTime.now());
    final todos = await TodosRepository.instance.listLocal(includeDone: true);
    final habits = await HabitsRepository.instance.listLocal();
    final todayCal = await HabitsRepository.instance.getCalendarLocal(
      from: localDate.subtract(const Duration(days: 29)),
      to: localDate,
    );
    final dayTodos = todos
        .where((todo) => _isTodoOnDate(todo, localDate))
        .where((todo) => todo.status != TodoStatus.archived)
        .toList();
    final openTodos = dayTodos.where((todo) => !todo.isDone).toList();
    final completedByHabitId = todayCal[localDate] ?? const <String, bool>{};
    final habitsCompleted = habits
        .where((habit) => completedByHabitId[habit.id] == true)
        .length;
    final eisenhower = _localEisenhower(localDate, openTodos);
    final scoreResult = DailyScoreCalculator.calculate(
      todos: dayTodos,
      date: localDate,
      habitsTotal: habits.length,
      habitsCompleted: habitsCompleted,
    );
    final snapshot = DashboardSnapshot(
      date: localDate,
      score: scoreResult.score,
      todosTotal: dayTodos.length,
      todosDone: scoreResult.validCompletedTodos,
      eisenhowerCounts: eisenhower.counts,
      habitsTotal: habits.length,
      habitsCompleted: habitsCompleted,
      frog: _localFrog(dayTodos, localDate),
    );

    return (
      snapshot: snapshot,
      eisenhower: eisenhower,
      habits: habits,
      todayCal: todayCal,
      hasData: todos.isNotEmpty || habits.isNotEmpty || todayCal.isNotEmpty,
    );
  }

  /// F-D2 Eisenhower detail (chứa by_quadrant preview todos).
  Future<EisenhowerDetail> eisenhower({DateTime? date}) async {
    final localDate = AppDateUtils.dateOnly(date ?? DateTime.now());
    final resp = await _client.get(
      '/dashboard/eisenhower',
      query: {'date': formatDateOnly(localDate)},
    );
    final detail = EisenhowerDetail.fromJson(resp as Map<String, dynamic>);
    return _mergeLocalHabitLinks(detail);
  }

  /// F-D3 Calendar overview.
  Future<Map<DateTime, CalendarDay>> calendar({
    required DateTime from,
    required DateTime to,
  }) async {
    final resp = await _client.get(
      '/dashboard/calendar',
      query: {'from': formatDateOnly(from), 'to': formatDateOnly(to)},
    );
    final daysMap =
        (resp as Map<String, dynamic>)['days'] as Map<String, dynamic>? ?? {};
    final result = <DateTime, CalendarDay>{};
    daysMap.forEach((dateStr, value) {
      result[jsonDateOnly(dateStr)] = CalendarDay.fromJson(
        value as Map<String, dynamic>,
      );
    });
    return result;
  }

  /// Calendar day detail for the iPhone Calendar-style timeline.
  Future<CalendarDayDetail> calendarDayDetail({required DateTime date}) async {
    final localDate = AppDateUtils.dateOnly(date);
    final isPast = localDate.isBefore(AppDateUtils.dateOnly(DateTime.now()));
    try {
      final resp = await _client.get(
        '/dashboard/calendar/day',
        query: {'date': formatDateOnly(localDate)},
      );
      return CalendarDayDetail.fromJson(resp as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.isAuthError) rethrow;
      if (e.statusCode == 404 || e.code == 'not_found') {
        return _legacyCalendarDayDetailOrLocal(localDate);
      }
      if (!e.isRetryable) rethrow;
      if (isPast) rethrow;
      return localCalendarDayDetail(date: localDate);
    }
  }

  Future<CalendarDayDetail> _legacyCalendarDayDetailOrLocal(
    DateTime localDate,
  ) async {
    try {
      final legacyItems = await TodosRepository.instance.getDay(localDate);
      final shell = await localCalendarDayDetail(date: localDate);
      final timedTodos = <CalendarDayTodo>[];
      final untimedTodos = <CalendarDayTodo>[];
      for (final item in legacyItems) {
        final todo = _calendarTodoFromModel(
          item.todo,
          hasSubtasks: item.hasSubtasks,
        );
        if (todo.time == null) {
          untimedTodos.add(todo);
        } else {
          timedTodos.add(todo);
        }
      }
      timedTodos.sort(_compareCalendarTimedTodos);
      untimedTodos.sort(_compareCalendarUntimedTodos);
      return CalendarDayDetail(
        date: shell.date,
        timezone: shell.timezone,
        week: shell.week,
        timeline: shell.timeline,
        currentTimeIndicator: shell.currentTimeIndicator,
        timedTodos: List.unmodifiable(timedTodos),
        untimedTodos: List.unmodifiable(untimedTodos),
        totals: CalendarDayTotals(
          totalTodos: timedTodos.length + untimedTodos.length,
          timedTodos: timedTodos.length,
          untimedTodos: untimedTodos.length,
          doneTodos: [...timedTodos, ...untimedTodos]
              .where(
                (todo) => _calendarTodoCompletionCountsForDate(todo, localDate),
              )
              .length,
        ),
      );
    } on ApiException catch (legacyError) {
      if (legacyError.isAuthError) rethrow;
      return localCalendarDayDetail(date: localDate);
    }
  }

  Future<CalendarDayDetail> localCalendarDayDetail({
    required DateTime date,
  }) async {
    final localDate = AppDateUtils.dateOnly(date);
    final dateString = formatDateOnly(localDate);
    final allRows = await _db.todosDao.getAllNonDeletedTodos();
    final currentUserRows = allRows
        .where((row) => _belongsToCurrentUser(row.userId))
        .where((row) => row.parentId == null)
        .where((row) => row.status != TodoStatus.archived.backendValue)
        .toList();
    final dayRows = currentUserRows
        .where((row) => row.scheduledDate == dateString)
        .toList();

    final timedTodos = <CalendarDayTodo>[];
    final untimedTodos = <CalendarDayTodo>[];
    for (final row in dayRows) {
      final todo = await _calendarTodoFromLocal(row);
      if (todo.time == null) {
        untimedTodos.add(todo);
      } else {
        timedTodos.add(todo);
      }
    }
    timedTodos.sort(_compareCalendarTimedTodos);
    untimedTodos.sort(_compareCalendarUntimedTodos);

    final start = _startOfWeek(localDate);
    final end = start.add(const Duration(days: 6));
    final weekDays = List.generate(7, (index) {
      final day = start.add(Duration(days: index));
      final dayString = formatDateOnly(day);
      final rows = currentUserRows
          .where((row) => row.scheduledDate == dayString)
          .toList();
      return CalendarWeekDay(
        date: day,
        isoWeekday: day.weekday,
        weekdayLabel: AppDateUtils.weekdayShort(day.weekday),
        dayOfMonth: day.day,
        month: day.month,
        isSelected: AppDateUtils.isSameDay(day, localDate),
        isToday: AppDateUtils.isToday(day),
        totalTodos: rows.length,
        timedTodos: rows
            .where((row) => todoTimeMinutes(row.time) != null)
            .length,
        doneTodos: rows
            .where((row) => _todoRowCompletionCountsForDate(row, day))
            .length,
      );
    });

    return CalendarDayDetail(
      date: localDate,
      timezone: DateTime.now().timeZoneName,
      week: CalendarWeek(
        startsOn: 'monday',
        from: start,
        to: end,
        days: weekDays,
      ),
      timeline: CalendarTimeline.fromJson(null),
      currentTimeIndicator: _localCurrentTimeIndicator(localDate),
      timedTodos: List.unmodifiable(timedTodos),
      untimedTodos: List.unmodifiable(untimedTodos),
      totals: CalendarDayTotals(
        totalTodos: dayRows.length,
        timedTodos: timedTodos.length,
        untimedTodos: untimedTodos.length,
        doneTodos: dayRows
            .where((row) => _todoRowCompletionCountsForDate(row, localDate))
            .length,
      ),
    );
  }

  Future<EisenhowerDetail> _mergeLocalHabitLinks(
    EisenhowerDetail detail,
  ) async {
    final byQuadrant = <String, List<DashboardEisenhowerTodo>>{};
    for (final entry in detail.byQuadrant.entries) {
      final todos = <DashboardEisenhowerTodo>[];
      for (final todo in entry.value) {
        if (todo.isDailyLog || todo.habitId != null || todo.todoId.isEmpty) {
          todos.add(todo);
          continue;
        }
        final local = await _db.todosDao.getTodoById(todo.todoId);
        todos.add(
          local?.habitId == null
              ? todo
              : todo.copyWith(habitId: local!.habitId),
        );
      }
      byQuadrant[entry.key] = _sortDashboardTodos(todos);
    }
    return EisenhowerDetail(
      date: detail.date,
      counts: detail.counts,
      byQuadrant: byQuadrant,
    );
  }

  bool _isTodoOnDate(Todo todo, DateTime date) {
    return DailyScoreCalculator.isTodoOnDate(todo, date);
  }

  Future<CalendarDayTodo> _calendarTodoFromLocal(TodoRow row) async {
    final tags = await _db.todosDao.getTagsForTodo(row.id);
    final hasSubtasks = await _db.todosDao.hasDirectActiveSubtasks(
      row.id,
      userId: row.userId,
    );
    final time = row.parentId == null && row.scheduledDate != null
        ? row.time
        : null;
    return CalendarDayTodo(
      id: row.id,
      userId: row.userId,
      parentId: row.parentId,
      title: row.title,
      description: row.description,
      status: row.status,
      position: row.position,
      scheduledDate: row.scheduledDate == null
          ? null
          : jsonDateOnlyNullable(row.scheduledDate),
      time: time,
      minutesSinceMidnight: todoTimeMinutes(time),
      estimatedMinutes: row.estimatedMinutes,
      actualMinutes: row.actualMinutes,
      startAt: row.startAt == null ? null : jsonDateNullable(row.startAt),
      dueAt: row.dueAt == null ? null : jsonDateNullable(row.dueAt),
      completedAt: row.completedAt == null
          ? null
          : jsonDateNullable(row.completedAt),
      isFrog: row.isFrog,
      frogDate: row.frogDate == null
          ? null
          : jsonDateOnlyNullable(row.frogDate),
      isImportant: row.isImportant == true,
      isUrgent: row.isUrgent == true,
      triggerAfterTodoId: row.triggerAfterTodoId,
      habitId: row.habitId,
      recurrenceType: row.recurrenceType,
      recurrenceInterval: row.recurrenceInterval,
      recurrenceDaysOfWeek: row.recurrenceWeekdays,
      recurrenceEndDate: row.recurrenceEndDate,
      recurrenceTemplateId: row.recurrenceTemplateId,
      hasSubtasks: hasSubtasks,
      tags: tags.map(_tagRowToModel).toList(growable: false),
      tagIds: tags.map((tag) => tag.id).toList(growable: false),
      createdAt: jsonDateNullable(row.createdAt),
      updatedAt: jsonDateNullable(row.updatedAt),
    );
  }

  CalendarDayTodo _calendarTodoFromModel(
    Todo todo, {
    required bool hasSubtasks,
  }) {
    final time = todo.parentId == null && todo.scheduledDate != null
        ? todo.time
        : null;
    return CalendarDayTodo(
      id: todo.id,
      parentId: todo.parentId,
      title: todo.title,
      description: todo.description,
      status: todo.status.backendValue,
      position: todo.position,
      scheduledDate: todo.scheduledDate,
      time: time,
      minutesSinceMidnight: todoTimeMinutes(time),
      estimatedMinutes: todo.estimatedMinutes,
      actualMinutes: todo.actualMinutes,
      startAt: todo.startAt,
      dueAt: todo.dueAt,
      completedAt: todo.completedAt,
      isFrog: todo.isFrog,
      frogDate: todo.frogDate,
      isImportant: todo.isImportant == true,
      isUrgent: todo.isUrgent == true,
      triggerAfterTodoId: todo.triggerAfterTodoId,
      habitId: todo.habitId,
      recurrenceType: todo.recurrenceType,
      recurrenceInterval: todo.recurrenceInterval,
      recurrenceDaysOfWeek: todo.recurrenceDaysOfWeek,
      recurrenceEndDate: todo.recurrenceEndDate,
      recurrenceTemplateId: todo.recurrenceTemplateId,
      hasSubtasks: hasSubtasks,
      tags: todo.tags,
      tagIds: todo.tagIds,
      createdAt: todo.createdAt,
      updatedAt: todo.updatedAt,
    );
  }

  CalendarCurrentTimeIndicator _localCurrentTimeIndicator(DateTime date) {
    final now = DateTime.now();
    if (!AppDateUtils.isSameDay(date, now)) {
      return CalendarCurrentTimeIndicator.hidden;
    }
    final minutes = now.hour * 60 + now.minute;
    final hidden = _nearestHourMarkMinute(minutes);
    return CalendarCurrentTimeIndicator(
      visible: true,
      serverTime: now.toUtc(),
      currentDate: AppDateUtils.dateOnly(now),
      currentTime: AppDateUtils.formatTime(now),
      minutesSinceMidnight: minutes,
      lineMinutesSinceMidnight: minutes,
      hiddenHourMarkMinute: hidden,
      hiddenHourLabel: _formatTimelineMinute(hidden),
    );
  }

  int _nearestHourMarkMinute(int minutes) {
    final rounded = ((minutes + 30) ~/ 60) * 60;
    return rounded.clamp(0, 1440);
  }

  String _formatTimelineMinute(int minute) {
    final normalized = minute >= 1440 ? 0 : minute.clamp(0, 1439).toInt();
    final hour = normalized ~/ 60;
    final min = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  DateTime _startOfWeek(DateTime date) {
    return AppDateUtils.dateOnly(
      date.subtract(Duration(days: date.weekday - 1)),
    );
  }

  int _compareCalendarTimedTodos(CalendarDayTodo a, CalendarDayTodo b) {
    final byTime = (a.minutesSinceMidnight ?? 1048576).compareTo(
      b.minutesSinceMidnight ?? 1048576,
    );
    if (byTime != 0) return byTime;
    return _compareCalendarUntimedTodos(a, b);
  }

  int _compareCalendarUntimedTodos(CalendarDayTodo a, CalendarDayTodo b) {
    final byPosition = a.position.compareTo(b.position);
    if (byPosition != 0) return byPosition;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  Tag _tagRowToModel(TagRow row) {
    return Tag(
      id: row.id,
      userId: row.userId,
      name: row.name,
      color: jsonColor(row.color),
      createdAt: row.createdAt.isEmpty
          ? null
          : DateTime.tryParse(row.createdAt),
      updatedAt: row.updatedAt.isEmpty
          ? null
          : DateTime.tryParse(row.updatedAt),
      deletedAt: row.deletedAt == null
          ? null
          : DateTime.tryParse(row.deletedAt!),
    );
  }

  EisenhowerDetail _localEisenhower(DateTime date, List<Todo> openTodos) {
    final byQuadrant = {
      for (final key in dashboardQuadrantKeys) key: <DashboardEisenhowerTodo>[],
    };
    for (final todo in openTodos) {
      final key = _quadrantKeyForTodo(todo);
      byQuadrant[key]!.add(_dashboardTodoFromLocal(todo, key));
    }
    for (final key in dashboardQuadrantKeys) {
      byQuadrant[key] = _sortDashboardTodos(byQuadrant[key]!);
    }
    return EisenhowerDetail(
      date: date,
      counts: {
        for (final key in dashboardQuadrantKeys) key: byQuadrant[key]!.length,
      },
      byQuadrant: byQuadrant,
    );
  }

  DashboardEisenhowerTodo _dashboardTodoFromLocal(Todo todo, String quadrant) {
    return DashboardEisenhowerTodo(
      id: todo.id,
      title: todo.title,
      status: todo.status.backendValue,
      scheduledDate: todo.scheduledDate,
      time: todo.time,
      isImportant: todo.isImportant == true,
      isUrgent: todo.isUrgent == true,
      isFrog: todo.isFrog,
      frogDate: todo.frogDate,
      quadrant: quadrant,
      habitId: todo.habitId,
      tags: todo.tags,
      tagIds: todo.tagIds,
    );
  }

  String _quadrantKeyForTodo(Todo todo) {
    final important = todo.isImportant == true;
    final urgent = todo.isUrgent == true;
    if (important && urgent) return 'q1';
    if (important && !urgent) return 'q2';
    if (!important && urgent) return 'q3';
    return 'q4';
  }

  List<DashboardEisenhowerTodo> _sortDashboardTodos(
    List<DashboardEisenhowerTodo> todos,
  ) {
    final sorted = [...todos];
    sorted.sort((a, b) {
      final byTime = compareTodoTimes(a.time, b.time);
      if (byTime != 0) return byTime;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return sorted;
  }

  bool _todoRowCompletionCountsForDate(TodoRow row, DateTime fallbackDate) {
    final completedAt = row.completedAt == null
        ? null
        : DateTime.tryParse(row.completedAt!);
    final workDate = row.scheduledDate == null
        ? fallbackDate
        : jsonDateOnlyNullable(row.scheduledDate!) ?? fallbackDate;
    return DailyScoreCalculator.isCompletionValidForScore(
      isDone: row.status == TodoStatus.done.backendValue,
      completedAt: completedAt,
      scoreDate: fallbackDate,
      scheduledDate: workDate,
    );
  }

  bool _calendarTodoCompletionCountsForDate(
    CalendarDayTodo todo,
    DateTime fallbackDate,
  ) {
    return DailyScoreCalculator.isCompletionValidForScore(
      isDone: todo.isDone,
      completedAt: todo.completedAt,
      scoreDate: fallbackDate,
      scheduledDate: todo.scheduledDate,
    );
  }

  bool _isFrogForDate(Todo todo, DateTime date) {
    return DailyScoreCalculator.isFrogForDate(todo, date);
  }

  FrogTodo? _localFrog(List<Todo> dayTodos, DateTime date) {
    final frogs = dayTodos.where((todo) => _isFrogForDate(todo, date)).toList();
    if (frogs.isEmpty) return null;
    frogs.sort((a, b) {
      final doneOrder = (a.isDone ? 1 : 0).compareTo(b.isDone ? 1 : 0);
      if (doneOrder != 0) return doneOrder;
      return a.createdAt.compareTo(b.createdAt);
    });
    final frog = frogs.first;
    return FrogTodo(
      id: frog.id,
      title: frog.title,
      status: frog.status.backendValue,
    );
  }
}
