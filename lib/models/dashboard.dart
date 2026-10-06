import '../utils/json_utils.dart';
import '../utils/todo_time_utils.dart';
import 'tag.dart';

const List<String> dashboardQuadrantKeys = ['q1', 'q2', 'q3', 'q4'];

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<dynamic> _asList(dynamic value) => value is List ? value : const [];

String _stringValue(dynamic value, {String fallback = ''}) {
  if (value is String && value.isNotEmpty) return value;
  return fallback;
}

int _intValue(dynamic value) => value is num ? value.toInt() : 0;

int? _intNullable(dynamic value) => value is num ? value.toInt() : null;

String? _nullableString(dynamic value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

DateTime? _dateTimeNullable(dynamic value) {
  final dateString = value is String ? value : null;
  if (dateString == null || dateString.isEmpty) return null;
  try {
    return jsonDate(dateString);
  } catch (_) {
    return null;
  }
}

DateTime _dateOnlyOrToday(dynamic value) {
  final dateString = value is String ? value : null;
  if (dateString != null && dateString.isNotEmpty) {
    try {
      return jsonDateOnly(dateString);
    } catch (_) {
      // Fall through to local today for malformed dashboard payloads.
    }
  }
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime? _dateOnlyNullable(dynamic value) {
  final dateString = value is String ? value : null;
  if (dateString == null || dateString.isEmpty) return null;
  try {
    return jsonDateOnly(dateString);
  } catch (_) {
    return null;
  }
}

String? _quadrantKey(dynamic value) {
  final key = value is String ? value.toLowerCase() : null;
  return dashboardQuadrantKeys.contains(key) ? key : null;
}

String _quadrantFromFlags({required bool important, required bool urgent}) {
  if (important && urgent) return 'q1';
  if (important && !urgent) return 'q2';
  if (!important && urgent) return 'q3';
  return 'q4';
}

Map<String, int> _parseCounts(dynamic value) {
  final source = _asMap(value);
  return {
    for (final key in dashboardQuadrantKeys) key: _intValue(source?[key]),
  };
}

/// Tóm tắt todo đại diện cho Frog trên Dashboard.
class FrogTodo {
  final String id;
  final String title;
  final String status;

  const FrogTodo({required this.id, required this.title, required this.status});

  factory FrogTodo.fromJson(Map<String, dynamic> json) {
    return FrogTodo(
      id: _stringValue(json['id']),
      title: _stringValue(json['title'], fallback: 'Không có tiêu đề'),
      status: _stringValue(json['status'], fallback: 'open'),
    );
  }

  bool get isDone => status == 'done';
}

/// Response F-D1 GET /dashboard/today.
class DashboardSnapshot {
  final DateTime date;
  final int score; // điểm backend, có thể vượt 100
  final int todosTotal;
  final int todosDone;
  final Map<String, int> eisenhowerCounts; // q1, q2, q3, q4
  final int habitsTotal;
  final int habitsCompleted;
  final FrogTodo? frog;

  const DashboardSnapshot({
    required this.date,
    required this.score,
    required this.todosTotal,
    required this.todosDone,
    required this.eisenhowerCounts,
    required this.habitsTotal,
    required this.habitsCompleted,
    required this.frog,
  });

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    final todosMap = _asMap(json['todos']);
    final habitsMap = _asMap(json['habits_today']);
    final frogJson = _asMap(json['frog']);
    return DashboardSnapshot(
      date: _dateOnlyOrToday(json['date']),
      score: _intValue(json['score']),
      todosTotal: _intValue(todosMap?['total']),
      todosDone: _intValue(todosMap?['done']),
      eisenhowerCounts: _parseCounts(json['eisenhower_counts']),
      habitsTotal: _intValue(habitsMap?['total']),
      habitsCompleted: _intValue(habitsMap?['completed']),
      frog: frogJson == null ? null : FrogTodo.fromJson(frogJson),
    );
  }
}

class DashboardEisenhowerTodo {
  final String id;
  final String source;
  final bool isDailyLog;
  final String? logId;
  final String todoId;
  final bool? lockedCompleted;
  final String title;
  final String status;
  final DateTime? scheduledDate;
  final String? time;
  final bool isImportant;
  final bool isUrgent;
  final bool isFrog;
  final DateTime? frogDate;
  final String quadrant;
  final String? habitId;
  final List<Tag> tags;
  final List<String> tagIds;

  const DashboardEisenhowerTodo({
    required this.id,
    this.source = 'live',
    this.isDailyLog = false,
    this.logId,
    String? todoId,
    this.lockedCompleted,
    required this.title,
    required this.status,
    required this.scheduledDate,
    this.time,
    required this.isImportant,
    required this.isUrgent,
    required this.isFrog,
    required this.frogDate,
    required this.quadrant,
    this.habitId,
    this.tags = const [],
    this.tagIds = const [],
  }) : todoId = todoId ?? id;

  factory DashboardEisenhowerTodo.fromJson(
    Map<String, dynamic> json, {
    required String fallbackQuadrant,
  }) {
    final important = jsonBool(json['is_important']);
    final urgent = jsonBool(json['is_urgent']);
    final sourceValue = _stringValue(json['source'], fallback: 'live');
    final isDailyLog =
        jsonBool(json['is_daily_log']) || sourceValue == 'daily_log';
    final quadrant =
        _quadrantKey(json['quadrant']) ??
        _quadrantKey(fallbackQuadrant) ??
        _quadrantFromFlags(important: important, urgent: urgent);
    final tags = _asList(json['tags'])
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList(growable: false);
    final tagIds = _parseStringList(json['tag_ids']);
    return DashboardEisenhowerTodo(
      id: _stringValue(json['id']),
      source: isDailyLog ? 'daily_log' : sourceValue,
      isDailyLog: isDailyLog,
      logId: _nullableString(json['log_id']),
      todoId: _stringValue(json['todo_id'], fallback: _stringValue(json['id'])),
      lockedCompleted: json['locked_completed'] == null
          ? null
          : jsonBool(json['locked_completed']),
      title: _stringValue(json['title'], fallback: 'Không có tiêu đề'),
      status: _stringValue(json['status'], fallback: 'open'),
      scheduledDate: _dateOnlyNullable(json['scheduled_date']),
      time: json['time'] as String?,
      isImportant: important,
      isUrgent: urgent,
      isFrog: jsonBool(json['is_frog']),
      frogDate: _dateOnlyNullable(json['frog_date']),
      quadrant: quadrant,
      habitId: json['habit_id'] as String?,
      tags: tags,
      tagIds: tagIds.isNotEmpty ? tagIds : tags.map((tag) => tag.id).toList(),
    );
  }

  DashboardEisenhowerTodo copyWith({String? habitId}) {
    return DashboardEisenhowerTodo(
      id: id,
      source: source,
      isDailyLog: isDailyLog,
      logId: logId,
      todoId: todoId,
      lockedCompleted: lockedCompleted,
      title: title,
      status: status,
      scheduledDate: scheduledDate,
      time: time,
      isImportant: isImportant,
      isUrgent: isUrgent,
      isFrog: isFrog,
      frogDate: frogDate,
      quadrant: quadrant,
      habitId: habitId ?? this.habitId,
      tags: tags,
      tagIds: tagIds,
    );
  }

  bool get effectiveDone =>
      isDailyLog ? lockedCompleted == true : status == 'done';

  bool get isDoneOrArchived => isDailyLog
      ? lockedCompleted == true
      : status == 'done' || status == 'archived';
}

/// Response F-D2 GET /dashboard/eisenhower.
class EisenhowerDetail {
  final DateTime date;
  final Map<String, int> counts;
  final Map<String, List<DashboardEisenhowerTodo>> byQuadrant;

  const EisenhowerDetail({
    required this.date,
    required this.counts,
    required this.byQuadrant,
  });

  factory EisenhowerDetail.fromJson(Map<String, dynamic> json) {
    final byQuadMap = _asMap(json['by_quadrant']);
    return EisenhowerDetail(
      date: _dateOnlyOrToday(json['date']),
      counts: _parseCounts(json['counts']),
      byQuadrant: {
        for (final key in dashboardQuadrantKeys)
          key: _parseDashboardTodos(byQuadMap?[key], fallbackQuadrant: key),
      },
    );
  }
}

List<DashboardEisenhowerTodo> _parseDashboardTodos(
  dynamic value, {
  required String fallbackQuadrant,
}) {
  final todos = _asList(value)
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map(
        (json) => DashboardEisenhowerTodo.fromJson(
          json,
          fallbackQuadrant: fallbackQuadrant,
        ),
      )
      .where((todo) => !todo.isDoneOrArchived)
      .toList();
  todos.sort((a, b) {
    final byTime = compareTodoTimes(a.time, b.time);
    if (byTime != 0) return byTime;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return List.unmodifiable(todos);
}

List<Tag> _parseTags(dynamic value) {
  return _asList(value)
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map((json) {
        try {
          return Tag.fromJson(json);
        } catch (_) {
          return null;
        }
      })
      .whereType<Tag>()
      .toList(growable: false);
}

List<String> _parseStringList(dynamic value) {
  return _asList(value)
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

/// Một ngày trong calendar overview (F-D3).
class CalendarDay {
  final int totalTodos;
  final int doneTodos;
  final int? score; // null nếu future; điểm có thể vượt 100
  final int habitsTotal;
  final int habitsCompleted;

  const CalendarDay({
    required this.totalTodos,
    required this.doneTodos,
    this.score,
    required this.habitsTotal,
    required this.habitsCompleted,
  });

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    final totalTodos = (json['total_todos'] as num?)?.toInt() ?? 0;
    final doneTodos = (json['done_todos'] as num?)?.toInt() ?? 0;
    final rawScore = (json['score'] as num?)?.toInt();
    return CalendarDay(
      totalTodos: totalTodos,
      doneTodos: doneTodos,
      score: rawScore == null || _isScoreEligible(totalTodos, doneTodos)
          ? rawScore
          : 0,
      habitsTotal: (json['habits_total'] as num?)?.toInt() ?? 0,
      habitsCompleted: (json['habits_completed'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isFuture => score == null;

  static bool _isScoreEligible(int totalTodos, int doneTodos) {
    return totalTodos >= 3 && doneTodos >= 3;
  }
}

/// Một ngày trong week strip của calendar day detail.
class CalendarWeekDay {
  final DateTime date;
  final int isoWeekday;
  final String weekdayLabel;
  final int dayOfMonth;
  final int month;
  final bool isSelected;
  final bool isToday;
  final int totalTodos;
  final int timedTodos;
  final int doneTodos;

  const CalendarWeekDay({
    required this.date,
    required this.isoWeekday,
    required this.weekdayLabel,
    required this.dayOfMonth,
    required this.month,
    required this.isSelected,
    required this.isToday,
    required this.totalTodos,
    required this.timedTodos,
    required this.doneTodos,
  });

  factory CalendarWeekDay.fromJson(
    Map<String, dynamic> json, {
    DateTime? selectedDate,
  }) {
    final date =
        _dateOnlyNullable(json['date']) ??
        selectedDate ??
        _dateOnlyOrToday(null);
    return CalendarWeekDay(
      date: date,
      isoWeekday: _intValue(json['iso_weekday']) == 0
          ? date.weekday
          : _intValue(json['iso_weekday']),
      weekdayLabel: _stringValue(
        json['weekday_label'],
        fallback: _weekdayShort(date.weekday),
      ),
      dayOfMonth: _intValue(json['day_of_month']) == 0
          ? date.day
          : _intValue(json['day_of_month']),
      month: _intValue(json['month']) == 0
          ? date.month
          : _intValue(json['month']),
      isSelected:
          jsonBool(json['is_selected']) ||
          (selectedDate != null && _isSameDay(date, selectedDate)),
      isToday: jsonBool(json['is_today']) || _isSameDay(date, DateTime.now()),
      totalTodos: _intValue(json['total_todos']),
      timedTodos: _intValue(json['timed_todos']),
      doneTodos: _intValue(json['done_todos']),
    );
  }

  CalendarWeekDay copyWith({
    bool? isSelected,
    int? totalTodos,
    int? timedTodos,
    int? doneTodos,
  }) {
    return CalendarWeekDay(
      date: date,
      isoWeekday: isoWeekday,
      weekdayLabel: weekdayLabel,
      dayOfMonth: dayOfMonth,
      month: month,
      isSelected: isSelected ?? this.isSelected,
      isToday: isToday,
      totalTodos: totalTodos ?? this.totalTodos,
      timedTodos: timedTodos ?? this.timedTodos,
      doneTodos: doneTodos ?? this.doneTodos,
    );
  }
}

class CalendarWeek {
  final String startsOn;
  final DateTime from;
  final DateTime to;
  final List<CalendarWeekDay> days;

  const CalendarWeek({
    required this.startsOn,
    required this.from,
    required this.to,
    required this.days,
  });

  factory CalendarWeek.fromJson(
    Map<String, dynamic>? json, {
    required DateTime selectedDate,
  }) {
    final from =
        _dateOnlyNullable(json?['from']) ?? _startOfIsoWeek(selectedDate);
    final to =
        _dateOnlyNullable(json?['to']) ?? from.add(const Duration(days: 6));
    final parsedDays = _asList(json?['days'])
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map((day) => CalendarWeekDay.fromJson(day, selectedDate: selectedDate))
        .toList(growable: false);
    final days = parsedDays.isEmpty
        ? _buildWeekDays(selectedDate)
        : parsedDays
              .map(
                (day) => day.copyWith(
                  isSelected: _isSameDay(day.date, selectedDate),
                ),
              )
              .toList(growable: false);
    return CalendarWeek(
      startsOn: _stringValue(json?['starts_on'], fallback: 'monday'),
      from: from,
      to: to,
      days: days,
    );
  }
}

class CalendarHourMark {
  final int minute;
  final String label;

  const CalendarHourMark({required this.minute, required this.label});

  factory CalendarHourMark.fromJson(Map<String, dynamic> json) {
    return CalendarHourMark(
      minute: _intValue(json['minute']),
      label: _stringValue(
        json['label'],
        fallback: _formatMinuteLabel(_intValue(json['minute'])),
      ),
    );
  }
}

class CalendarTimeline {
  final int startMinute;
  final int endMinute;
  final int slotMinutes;
  final List<CalendarHourMark> hourMarks;

  const CalendarTimeline({
    required this.startMinute,
    required this.endMinute,
    required this.slotMinutes,
    required this.hourMarks,
  });

  factory CalendarTimeline.fromJson(Map<String, dynamic>? json) {
    final start = _intValue(json?['start_minute']);
    final end = _intValue(json?['end_minute']) == 0
        ? 1440
        : _intValue(json?['end_minute']);
    final slot = _intValue(json?['slot_minutes']) == 0
        ? 60
        : _intValue(json?['slot_minutes']);
    final marks = _asList(json?['hour_marks'])
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(CalendarHourMark.fromJson)
        .toList(growable: false);
    return CalendarTimeline(
      startMinute: start,
      endMinute: end,
      slotMinutes: slot,
      hourMarks: marks.isEmpty ? _defaultHourMarks(start, end, slot) : marks,
    );
  }
}

class CalendarCurrentTimeIndicator {
  final bool visible;
  final DateTime? serverTime;
  final DateTime? currentDate;
  final String? currentTime;
  final int? minutesSinceMidnight;
  final int? lineMinutesSinceMidnight;
  final int? hiddenHourMarkMinute;
  final String? hiddenHourLabel;

  const CalendarCurrentTimeIndicator({
    required this.visible,
    this.serverTime,
    this.currentDate,
    this.currentTime,
    this.minutesSinceMidnight,
    this.lineMinutesSinceMidnight,
    this.hiddenHourMarkMinute,
    this.hiddenHourLabel,
  });

  factory CalendarCurrentTimeIndicator.fromJson(Map<String, dynamic>? json) {
    return CalendarCurrentTimeIndicator(
      visible: jsonBool(json?['visible']),
      serverTime: _dateTimeNullable(json?['server_time']),
      currentDate: _dateOnlyNullable(json?['current_date']),
      currentTime: _nullableString(json?['current_time']),
      minutesSinceMidnight: _intNullable(json?['minutes_since_midnight']),
      lineMinutesSinceMidnight: _intNullable(
        json?['line_minutes_since_midnight'],
      ),
      hiddenHourMarkMinute: _intNullable(json?['hidden_hour_mark_minute']),
      hiddenHourLabel: _nullableString(json?['hidden_hour_label']),
    );
  }

  static const hidden = CalendarCurrentTimeIndicator(visible: false);
}

class CalendarDayTodo {
  final String id;
  final String source;
  final bool isDailyLog;
  final String? logId;
  final String todoId;
  final bool? lockedCompleted;
  final String? userId;
  final String? parentId;
  final String title;
  final String? description;
  final String status;
  final int position;
  final DateTime? scheduledDate;
  final String? time;
  final int? minutesSinceMidnight;
  final int? estimatedMinutes;
  final int? actualMinutes;
  final DateTime? startAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final bool isFrog;
  final DateTime? frogDate;
  final bool isImportant;
  final bool isUrgent;
  final String? triggerAfterTodoId;
  final String? habitId;
  final String? recurrenceType;
  final int? recurrenceInterval;
  final String? recurrenceDaysOfWeek;
  final String? recurrenceEndDate;
  final String? recurrenceTemplateId;
  final bool hasSubtasks;
  final List<Tag> tags;
  final List<String> tagIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CalendarDayTodo({
    required this.id,
    this.source = 'live',
    this.isDailyLog = false,
    this.logId,
    String? todoId,
    this.lockedCompleted,
    this.userId,
    this.parentId,
    required this.title,
    this.description,
    required this.status,
    required this.position,
    this.scheduledDate,
    this.time,
    this.minutesSinceMidnight,
    this.estimatedMinutes,
    this.actualMinutes,
    this.startAt,
    this.dueAt,
    this.completedAt,
    required this.isFrog,
    this.frogDate,
    required this.isImportant,
    required this.isUrgent,
    this.triggerAfterTodoId,
    this.habitId,
    this.recurrenceType,
    this.recurrenceInterval,
    this.recurrenceDaysOfWeek,
    this.recurrenceEndDate,
    this.recurrenceTemplateId,
    required this.hasSubtasks,
    this.tags = const [],
    this.tagIds = const [],
    this.createdAt,
    this.updatedAt,
  }) : todoId = todoId ?? id;

  factory CalendarDayTodo.fromJson(Map<String, dynamic> json) {
    final parentId = json['parent_id'] as String?;
    final time = parentId == null ? _nullableString(json['time']) : null;
    final tags = _parseTags(json['tags']);
    final tagIds = _parseStringList(json['tag_ids']);
    final sourceValue = _stringValue(json['source'], fallback: 'live');
    final isDailyLog =
        jsonBool(json['is_daily_log']) || sourceValue == 'daily_log';
    return CalendarDayTodo(
      id: _stringValue(json['id']),
      source: isDailyLog ? 'daily_log' : sourceValue,
      isDailyLog: isDailyLog,
      logId: _nullableString(json['log_id']),
      todoId: _stringValue(json['todo_id'], fallback: _stringValue(json['id'])),
      lockedCompleted: json['locked_completed'] == null
          ? null
          : jsonBool(json['locked_completed']),
      userId: json['user_id'] as String?,
      parentId: parentId,
      title: _stringValue(json['title'], fallback: 'Không có tiêu đề'),
      description: json['description'] as String?,
      status: _stringValue(json['status'], fallback: 'open'),
      position: _intValue(json['position']),
      scheduledDate: _dateOnlyNullable(json['scheduled_date']),
      time: time,
      minutesSinceMidnight:
          _intNullable(json['minutes_since_midnight']) ?? todoTimeMinutes(time),
      estimatedMinutes: _intNullable(json['estimated_minutes']),
      actualMinutes: _intNullable(json['actual_minutes']),
      startAt: _dateTimeNullable(json['start_at']),
      dueAt: _dateTimeNullable(json['due_at']),
      completedAt: _dateTimeNullable(json['completed_at']),
      isFrog: jsonBool(json['is_frog']),
      frogDate: _dateOnlyNullable(json['frog_date']),
      isImportant: jsonBool(json['is_important']),
      isUrgent: jsonBool(json['is_urgent']),
      triggerAfterTodoId: json['trigger_after_todo_id'] as String?,
      habitId: json['habit_id'] as String?,
      recurrenceType: json['recurrence_type'] as String?,
      recurrenceInterval: _intNullable(json['recurrence_interval']),
      recurrenceDaysOfWeek: json['recurrence_days_of_week'] as String?,
      recurrenceEndDate: json['recurrence_end_date'] as String?,
      recurrenceTemplateId: json['recurrence_template_id'] as String?,
      hasSubtasks: jsonBool(json['has_subtasks']),
      tags: tags,
      tagIds: tagIds.isNotEmpty ? tagIds : tags.map((tag) => tag.id).toList(),
      createdAt: _dateTimeNullable(json['created_at']),
      updatedAt: _dateTimeNullable(json['updated_at']),
    );
  }

  bool get isDone => isDailyLog ? lockedCompleted == true : status == 'done';
}

class CalendarDayTotals {
  final int totalTodos;
  final int timedTodos;
  final int untimedTodos;
  final int doneTodos;

  const CalendarDayTotals({
    required this.totalTodos,
    required this.timedTodos,
    required this.untimedTodos,
    required this.doneTodos,
  });

  factory CalendarDayTotals.fromJson(Map<String, dynamic>? json) {
    return CalendarDayTotals(
      totalTodos: _intValue(json?['total_todos']),
      timedTodos: _intValue(json?['timed_todos']),
      untimedTodos: _intValue(json?['untimed_todos']),
      doneTodos: _intValue(json?['done_todos']),
    );
  }
}

/// Response GET /dashboard/calendar/day.
class CalendarDayDetail {
  final DateTime date;
  final String timezone;
  final CalendarWeek week;
  final CalendarTimeline timeline;
  final CalendarCurrentTimeIndicator currentTimeIndicator;
  final List<CalendarDayTodo> timedTodos;
  final List<CalendarDayTodo> untimedTodos;
  final CalendarDayTotals totals;

  const CalendarDayDetail({
    required this.date,
    required this.timezone,
    required this.week,
    required this.timeline,
    required this.currentTimeIndicator,
    required this.timedTodos,
    required this.untimedTodos,
    required this.totals,
  });

  factory CalendarDayDetail.fromJson(Map<String, dynamic> json) {
    final date = _dateOnlyOrToday(json['date']);
    final timed = _parseCalendarTodos(json['timed_todos'], timed: true);
    final untimed = _parseCalendarTodos(json['untimed_todos'], timed: false);
    final totalsJson = _asMap(json['totals']);
    return CalendarDayDetail(
      date: date,
      timezone: _stringValue(json['timezone'], fallback: 'local'),
      week: CalendarWeek.fromJson(_asMap(json['week']), selectedDate: date),
      timeline: CalendarTimeline.fromJson(_asMap(json['timeline'])),
      currentTimeIndicator: CalendarCurrentTimeIndicator.fromJson(
        _asMap(json['current_time_indicator']),
      ),
      timedTodos: timed,
      untimedTodos: untimed,
      totals: totalsJson == null
          ? CalendarDayTotals(
              totalTodos: timed.length + untimed.length,
              timedTodos: timed.length,
              untimedTodos: untimed.length,
              doneTodos: [
                ...timed,
                ...untimed,
              ].where((todo) => todo.isDone).length,
            )
          : CalendarDayTotals.fromJson(totalsJson),
    );
  }
}

List<CalendarDayTodo> _parseCalendarTodos(
  dynamic value, {
  required bool timed,
}) {
  final todos = _asList(value)
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map(CalendarDayTodo.fromJson)
      .where((todo) => todo.parentId == null)
      .where((todo) => timed ? todo.time != null : todo.time == null)
      .toList();
  todos.sort((a, b) {
    if (timed) {
      final byTime = (a.minutesSinceMidnight ?? 1048576).compareTo(
        b.minutesSinceMidnight ?? 1048576,
      );
      if (byTime != 0) return byTime;
    }
    final byPosition = a.position.compareTo(b.position);
    if (byPosition != 0) return byPosition;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return List.unmodifiable(todos);
}

List<CalendarHourMark> _defaultHourMarks(int start, int end, int slot) {
  final result = <CalendarHourMark>[];
  final safeSlot = slot <= 0 ? 60 : slot;
  for (var minute = start; minute <= end; minute += safeSlot) {
    result.add(
      CalendarHourMark(minute: minute, label: _formatMinuteLabel(minute)),
    );
  }
  return result;
}

List<CalendarWeekDay> _buildWeekDays(DateTime selectedDate) {
  final from = _startOfIsoWeek(selectedDate);
  return List.generate(7, (index) {
    final date = from.add(Duration(days: index));
    return CalendarWeekDay(
      date: date,
      isoWeekday: date.weekday,
      weekdayLabel: _weekdayShort(date.weekday),
      dayOfMonth: date.day,
      month: date.month,
      isSelected: _isSameDay(date, selectedDate),
      isToday: _isSameDay(date, DateTime.now()),
      totalTodos: 0,
      timedTodos: 0,
      doneTodos: 0,
    );
  });
}

DateTime _startOfIsoWeek(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  return local.subtract(Duration(days: local.weekday - 1));
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _weekdayShort(int weekday) {
  const labels = ['', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  return labels[weekday.clamp(1, 7).toInt()];
}

String _formatMinuteLabel(int minute) {
  final normalized = minute >= 1440 ? 0 : minute.clamp(0, 1439).toInt();
  final hour = normalized ~/ 60;
  final min = normalized % 60;
  return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}
