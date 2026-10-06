import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api_exception.dart';
import '../../data/dashboard_repository.dart';
import '../../data/todos_repository.dart';
import '../../models/dashboard.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/habit_stacking_dialog.dart';
import '../../utils/todo_local_events.dart';
import '../../utils/todo_time_utils.dart';
import '../../widgets/calendar_day_timeline.dart';
import '../todos/todo_create_screen.dart';
import '../todos/todo_detail_screen.dart';
import '../todos/todo_edit_screen.dart';

typedef CalendarDayDetailLoader =
    Future<CalendarDayDetail> Function(DateTime date);

class CalendarDayDetailScreen extends StatefulWidget {
  final DateTime initialDate;
  final CalendarDayDetailLoader? loader;

  const CalendarDayDetailScreen({
    super.key,
    required this.initialDate,
    this.loader,
  });

  @override
  State<CalendarDayDetailScreen> createState() =>
      _CalendarDayDetailScreenState();
}

class _CalendarDayDetailScreenState extends State<CalendarDayDetailScreen> {
  late DateTime _selectedDate;
  CalendarDayDetail? _detail;
  bool _loading = false;
  String? _error;
  DateTime _clock = DateTime.now();
  Timer? _clockTimer;
  final Set<String> _savingTodoIds = {};

  CalendarDayDetailLoader get _loader =>
      widget.loader ??
      ((date) => DashboardRepository.instance.calendarDayDetail(date: date));

  @override
  void initState() {
    super.initState();
    _selectedDate = AppDateUtils.dateOnly(widget.initialDate);
    TodoLocalEvents.instance.revision.addListener(_onLocalTodoChanged);
    _load();
    _scheduleClock();
  }

  @override
  void dispose() {
    TodoLocalEvents.instance.revision.removeListener(_onLocalTodoChanged);
    _clockTimer?.cancel();
    super.dispose();
  }

  void _onLocalTodoChanged() {
    if (_isPastDate(_selectedDate)) {
      unawaited(_load());
    } else {
      unawaited(_loadLocalDetail());
    }
  }

  Future<void> _loadLocalDetail() async {
    if (_isPastDate(_selectedDate)) return;
    final local = await DashboardRepository.instance.localCalendarDayDetail(
      date: _selectedDate,
    );
    if (!mounted) return;
    setState(() {
      _detail = local;
      _selectedDate = local.date;
      _error = null;
    });
  }

  Future<void> _load() async {
    if (_detail == null && !_isPastDate(_selectedDate)) {
      await _loadLocalDetail();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _loader(_selectedDate);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _selectedDate = detail.date;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Không tải được lịch ngày');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleClock() {
    _clockTimer?.cancel();
    final now = DateTime.now();
    _clock = now;
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    ).add(const Duration(milliseconds: 80));
    _clockTimer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _clock = DateTime.now());
      _scheduleClock();
    });
  }

  Future<void> _selectDate(DateTime date) async {
    final normalized = AppDateUtils.dateOnly(date);
    if (AppDateUtils.isSameDay(normalized, _selectedDate) && _detail != null) {
      return;
    }
    setState(() {
      _selectedDate = normalized;
      _detail = null;
      _error = null;
    });
    await _load();
  }

  void _shiftWeek(int delta) {
    unawaited(_selectDate(_selectedDate.add(Duration(days: delta * 7))));
  }

  Future<void> _openTodo(CalendarDayTodo todo) async {
    final targetId = todo.todoId.isNotEmpty ? todo.todoId : todo.id;
    if (targetId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: targetId)),
    );
    if (!mounted) return;
    if (todo.isDailyLog) {
      unawaited(_load());
      return;
    }
    await _loadLocalDetail();
    if (!mounted) return;
    final hasPending = await TodosRepository.instance.hasPendingLocalWrites();
    if (!hasPending) unawaited(_load());
  }

  Future<void> _completeTodo(CalendarDayTodo todo) async {
    if (todo.isDailyLog) {
      _showError('Ngày này đã chốt, không thể tick trực tiếp từ lịch sử');
      return;
    }
    if (todo.id.isEmpty || todo.isDone || _savingTodoIds.contains(todo.id)) {
      return;
    }
    final previous = _detail;
    final completedAt = DateTime.now().toUtc();
    setState(() {
      _savingTodoIds.add(todo.id);
      if (!_isPastDate(_selectedDate)) {
        _replaceTodoInDetail(_calendarTodoWithStatus(todo, completedAt));
      }
    });

    try {
      final source = await _sourceTodo(todo);
      final result = await TodosRepository.instance.completeLocalFirst(source);
      if (!mounted) return;
      if (_isPastDate(_selectedDate)) {
        unawaited(_load());
      } else {
        await _loadLocalDetail();
      }
      if (!mounted) return;
      setState(() => _savingTodoIds.remove(todo.id));
      if (result.triggeredTodos.isNotEmpty) {
        await showHabitStackingDialog(context, result.triggeredTodos, (next) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TodoDetailScreen(todoId: next.id),
            ),
          );
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _detail = previous;
        _savingTodoIds.remove(todo.id);
      });
      _showError(e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detail = previous;
        _savingTodoIds.remove(todo.id);
      });
      _showError('Không thể hoàn thành việc này');
    }
  }

  Future<void> _openTodoEdit(CalendarDayTodo todo) async {
    if (todo.isDailyLog) {
      _showError('Ngày này đã chốt, hãy mở todo thật để chỉnh sửa');
      return;
    }
    if (todo.id.isEmpty) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TodoEditScreen(todoId: todo.id)));
    if (!mounted) return;
    await _loadLocalDetail();
    if (!mounted) return;
    final hasPending = await TodosRepository.instance.hasPendingLocalWrites();
    if (!hasPending) unawaited(_load());
  }

  Future<void> _createTodoForSelectedDate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TodoCreateScreen(initialScheduledDate: _selectedDate),
      ),
    );
    if (!mounted || created != true) return;
    await _loadLocalDetail();
    if (!mounted) return;
    final hasPending = await TodosRepository.instance.hasPendingLocalWrites();
    if (!hasPending) unawaited(_load());
  }

  Future<void> _pickTodoTime(CalendarDayTodo todo) async {
    if (todo.isDailyLog) {
      _showError('Ngày này đã chốt, không thể đổi giờ từ lịch sử');
      return;
    }
    if (todo.id.isEmpty || _savingTodoIds.contains(todo.id)) return;
    final action = todo.time == null
        ? 'pick'
        : await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Chọn giờ'),
                    subtitle: Text('Hiện tại: ${todo.time}'),
                    onTap: () => Navigator.of(ctx).pop('pick'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.close_rounded),
                    title: const Text('Bỏ giờ'),
                    onTap: () => Navigator.of(ctx).pop('clear'),
                  ),
                ],
              ),
            ),
          );
    if (action == null || !mounted) return;
    if (action == 'clear') {
      await _changeTodoTimeLocalFirst(todo, null);
      return;
    }
    if (todo.scheduledDate == null) {
      _showError('Todo này chưa có ngày làm');
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDayFromString(todo.time),
    );
    if (picked == null || !mounted) return;
    await _changeTodoTimeLocalFirst(todo, _formatTimeOfDay(picked));
  }

  Future<void> _changeTodoTimeLocalFirst(
    CalendarDayTodo todo,
    String? time,
  ) async {
    final previous = _detail;
    final optimistic = _calendarTodoWithTime(todo, time);
    setState(() {
      _savingTodoIds.add(todo.id);
      _upsertTodoInDetail(optimistic);
    });
    try {
      final source = await _sourceTodo(todo);
      await TodosRepository.instance.updateLocalFirst(source, {'time': time});
      if (!mounted) return;
      if (_isPastDate(_selectedDate)) {
        unawaited(_load());
      } else {
        await _loadLocalDetail();
      }
      if (!mounted) return;
      setState(() => _savingTodoIds.remove(todo.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _detail = previous;
        _savingTodoIds.remove(todo.id);
      });
      _showError(e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detail = previous;
        _savingTodoIds.remove(todo.id);
      });
      _showError('Không thể đổi giờ');
    }
  }

  Future<Todo> _sourceTodo(CalendarDayTodo todo) async {
    final lookupId = todo.todoId.isNotEmpty ? todo.todoId : todo.id;
    final local = await TodosRepository.instance.getLocalDetail(lookupId);
    return local?.todo ?? _todoFromCalendar(todo);
  }

  Todo _todoFromCalendar(CalendarDayTodo todo) {
    final now = DateTime.now().toUtc();
    return Todo(
      id: todo.todoId.isNotEmpty ? todo.todoId : todo.id,
      parentId: todo.parentId,
      title: todo.title,
      description: todo.description,
      status: TodoStatus.parse(todo.status),
      position: todo.position,
      isFrog: todo.isFrog,
      frogDate: todo.frogDate,
      isImportant: todo.isImportant,
      isUrgent: todo.isUrgent,
      estimatedMinutes: todo.estimatedMinutes,
      actualMinutes: todo.actualMinutes,
      startAt: todo.startAt,
      dueAt: todo.dueAt,
      scheduledDate: todo.scheduledDate,
      time: todo.time,
      triggerAfterTodoId: todo.triggerAfterTodoId,
      habitId: todo.habitId,
      tags: todo.tags,
      tagIds: todo.tagIds,
      tagsLoaded: todo.tags.isNotEmpty || todo.tagIds.isNotEmpty,
      completedAt: todo.completedAt,
      createdAt: todo.createdAt ?? now,
      updatedAt: todo.updatedAt ?? now,
      recurrenceType: todo.recurrenceType,
      recurrenceInterval: todo.recurrenceInterval ?? 1,
      recurrenceDaysOfWeek: todo.recurrenceDaysOfWeek,
      recurrenceEndDate: todo.recurrenceEndDate,
      recurrenceTemplateId: todo.recurrenceTemplateId,
    );
  }

  CalendarDayTodo _calendarTodoWithStatus(
    CalendarDayTodo todo,
    DateTime completedAt,
  ) {
    return CalendarDayTodo(
      id: todo.id,
      source: todo.source,
      isDailyLog: todo.isDailyLog,
      logId: todo.logId,
      todoId: todo.todoId,
      lockedCompleted: todo.lockedCompleted,
      userId: todo.userId,
      parentId: todo.parentId,
      title: todo.title,
      description: todo.description,
      status: TodoStatus.done.backendValue,
      position: todo.position,
      scheduledDate: todo.scheduledDate,
      time: todo.time,
      minutesSinceMidnight:
          todo.minutesSinceMidnight ?? todoTimeMinutes(todo.time),
      estimatedMinutes: todo.estimatedMinutes,
      actualMinutes: todo.actualMinutes,
      startAt: todo.startAt,
      dueAt: todo.dueAt,
      completedAt: completedAt,
      isFrog: todo.isFrog,
      frogDate: todo.frogDate,
      isImportant: todo.isImportant,
      isUrgent: todo.isUrgent,
      triggerAfterTodoId: todo.triggerAfterTodoId,
      habitId: todo.habitId,
      recurrenceType: todo.recurrenceType,
      recurrenceInterval: todo.recurrenceInterval,
      recurrenceDaysOfWeek: todo.recurrenceDaysOfWeek,
      recurrenceEndDate: todo.recurrenceEndDate,
      recurrenceTemplateId: todo.recurrenceTemplateId,
      hasSubtasks: todo.hasSubtasks,
      tags: todo.tags,
      tagIds: todo.tagIds,
      createdAt: todo.createdAt,
      updatedAt: completedAt,
    );
  }

  CalendarDayTodo _calendarTodoWithTime(CalendarDayTodo todo, String? time) {
    final now = DateTime.now().toUtc();
    return CalendarDayTodo(
      id: todo.id,
      source: todo.source,
      isDailyLog: todo.isDailyLog,
      logId: todo.logId,
      todoId: todo.todoId,
      lockedCompleted: todo.lockedCompleted,
      userId: todo.userId,
      parentId: todo.parentId,
      title: todo.title,
      description: todo.description,
      status: todo.status,
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
      isImportant: todo.isImportant,
      isUrgent: todo.isUrgent,
      triggerAfterTodoId: todo.triggerAfterTodoId,
      habitId: todo.habitId,
      recurrenceType: todo.recurrenceType,
      recurrenceInterval: todo.recurrenceInterval,
      recurrenceDaysOfWeek: todo.recurrenceDaysOfWeek,
      recurrenceEndDate: todo.recurrenceEndDate,
      recurrenceTemplateId: todo.recurrenceTemplateId,
      hasSubtasks: todo.hasSubtasks,
      tags: todo.tags,
      tagIds: todo.tagIds,
      createdAt: todo.createdAt,
      updatedAt: now,
    );
  }

  void _replaceTodoInDetail(CalendarDayTodo updated) {
    final detail = _detail;
    if (detail == null) return;
    var wasDone = false;
    var replaced = false;
    List<CalendarDayTodo> replace(List<CalendarDayTodo> todos) {
      return [
        for (final todo in todos)
          if (todo.id == updated.id) ...[updated] else ...[todo],
      ];
    }

    for (final todo in [...detail.timedTodos, ...detail.untimedTodos]) {
      if (todo.id == updated.id) {
        wasDone = todo.isDone;
        replaced = true;
        break;
      }
    }
    if (!replaced) return;
    final doneDelta = !wasDone && updated.isDone ? 1 : 0;
    _detail = CalendarDayDetail(
      date: detail.date,
      timezone: detail.timezone,
      week: detail.week,
      timeline: detail.timeline,
      currentTimeIndicator: detail.currentTimeIndicator,
      timedTodos: replace(detail.timedTodos),
      untimedTodos: replace(detail.untimedTodos),
      totals: CalendarDayTotals(
        totalTodos: detail.totals.totalTodos,
        timedTodos: detail.totals.timedTodos,
        untimedTodos: detail.totals.untimedTodos,
        doneTodos: detail.totals.doneTodos + doneDelta,
      ),
    );
  }

  void _upsertTodoInDetail(CalendarDayTodo updated) {
    final detail = _detail;
    if (detail == null) return;
    final timed = [
      for (final todo in detail.timedTodos)
        if (todo.id != updated.id) todo,
      if (updated.time != null) updated,
    ]..sort(_compareCalendarTodos);
    final untimed = [
      for (final todo in detail.untimedTodos)
        if (todo.id != updated.id) todo,
      if (updated.time == null) updated,
    ]..sort(_compareCalendarTodos);

    _detail = CalendarDayDetail(
      date: detail.date,
      timezone: detail.timezone,
      week: detail.week,
      timeline: detail.timeline,
      currentTimeIndicator: detail.currentTimeIndicator,
      timedTodos: timed,
      untimedTodos: untimed,
      totals: CalendarDayTotals(
        totalTodos: detail.totals.totalTodos,
        timedTodos: timed.length,
        untimedTodos: untimed.length,
        doneTodos: detail.totals.doneTodos,
      ),
    );
  }

  int _compareCalendarTodos(CalendarDayTodo a, CalendarDayTodo b) {
    final byTime = (a.minutesSinceMidnight ?? 1048576).compareTo(
      b.minutesSinceMidnight ?? 1048576,
    );
    if (byTime != 0) return byTime;
    final byPosition = a.position.compareTo(b.position);
    if (byPosition != 0) return byPosition;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  TimeOfDay _timeOfDayFromString(String? value) {
    final minutes = todoTimeMinutes(value);
    if (minutes == null) return TimeOfDay.now();
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  String _formatTimeOfDay(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  bool _isPastDate(DateTime date) {
    return AppDateUtils.dateOnly(
      date,
    ).isBefore(AppDateUtils.dateOnly(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch ngày'),
        actions: [
          IconButton(
            tooltip: 'Hôm nay',
            onPressed: () => unawaited(_selectDate(DateTime.now())),
            icon: const Icon(Icons.today_outlined),
          ),
          IconButton(
            tooltip: 'Thêm việc',
            onPressed: () => unawaited(_createTodoForSelectedDate()),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: detail == null && _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _Header(
                    date: detail?.date ?? _selectedDate,
                    totals: detail?.totals,
                  ),
                  if (detail != null)
                    _WeekStrip(
                      week: detail.week,
                      onSelectDate: _selectDate,
                      onShiftWeek: _shiftWeek,
                    )
                  else
                    const SizedBox(height: 8),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (_error != null)
                    _ErrorBanner(
                      message: _error!,
                      onRetry: () => unawaited(_load()),
                    ),
                  if (detail != null)
                    CalendarDayTimeline(
                      detail: detail,
                      now: _clock,
                      onTodoTap: _openTodo,
                      onTodoComplete: _completeTodo,
                      onTodoPickTime: _pickTodoTime,
                      onTodoEdit: _openTodoEdit,
                    )
                  else if (_error != null)
                    const SizedBox(height: 320),
                ],
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  final DateTime date;
  final CalendarDayTotals? totals;

  const _Header({required this.date, this.totals});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final title = AppDateUtils.formatDashboardTitle(date);
    final totalLabel = totals == null
        ? ''
        : '${totals!.doneTodos}/${totals!.totalTodos} xong · ${totals!.timedTodos} có giờ · ${totals!.untimedTodos} không giờ';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (totalLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              totalLabel,
              style: TextStyle(color: secondary, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final CalendarWeek week;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<int> onShiftWeek;

  const _WeekStrip({
    required this.week,
    required this.onSelectDate,
    required this.onShiftWeek,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final border = isDark ? AppColors.dividerDark : AppColors.divider;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120) onShiftWeek(1);
          if (velocity > 120) onShiftWeek(-1);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Tuần trước',
                  onPressed: () => onShiftWeek(-1),
                  icon: const Icon(Icons.chevron_left),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Row(
                    children: [
                      for (final day in week.days)
                        Expanded(
                          child: _WeekDayButton(
                            day: day,
                            onTap: () => onSelectDate(day.date),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tuần sau',
                  onPressed: () => onShiftWeek(1),
                  icon: const Icon(Icons.chevron_right),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekDayButton extends StatelessWidget {
  final CalendarWeekDay day;
  final VoidCallback onTap;

  const _WeekDayButton({required this.day, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final selectedText = isDark ? AppColors.textPrimaryDark : Colors.white;
    final background = day.isSelected
        ? primary
        : day.isToday
        ? primary.withValues(alpha: 0.13)
        : Colors.transparent;
    final foreground = day.isSelected ? selectedText : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                day.weekdayLabel,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  color: foreground ?? secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${day.dayOfMonth}',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 18,
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 5),
              _MiniDotCount(day: day, color: foreground ?? secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniDotCount extends StatelessWidget {
  final CalendarWeekDay day;
  final Color color;

  const _MiniDotCount({required this.day, required this.color});

  @override
  Widget build(BuildContext context) {
    if (day.totalTodos <= 0) {
      return const SizedBox(height: 13);
    }
    return Text(
      '${day.doneTodos}/${day.totalTodos}',
      maxLines: 1,
      style: TextStyle(
        fontSize: 10,
        color: color,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Thử lại')),
            ],
          ),
        ),
      ),
    );
  }
}
