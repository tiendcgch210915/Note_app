import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../data/todos_repository.dart';
import '../../models/habit.dart';
import '../../models/habit_log.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_snack.dart';
import '../../utils/date_utils.dart';
import '../../utils/habit_streak_utils.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/habit_calendar_grid.dart';
import '../../widgets/habit_today_log_panel.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/todo_tile.dart';
import 'habit_edit_screen.dart';
import '../todos/todo_detail_screen.dart';

/// HabitDetailScreen — fetch detail + log today + 28-day grid.
/// EXP 5: Archive/Unarchive via PopupMenu.
/// EXP 6: Long-press calendar cell → edit/delete log.
class HabitDetailScreen extends StatefulWidget {
  final String habitId;
  const HabitDetailScreen({super.key, required this.habitId});

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  Habit? _habit;
  List<HabitLog> _recentLogs = [];
  List<HabitLog> _calendarLogs = [];
  List<Todo> _relatedTodos = [];
  bool _loading = false;
  bool _logging = false;
  String? _loadError;

  DateTime get _today => AppDateUtils.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final detailFut = HabitsRepository.instance.getDetail(widget.habitId);
      final logsFut = HabitsRepository.instance.getLogs(
        widget.habitId,
        from: _today.subtract(const Duration(days: 29)),
        to: _today,
      );
      final results = await Future.wait([detailFut, logsFut]);
      if (!mounted) return;
      final detail = results[0] as ({Habit habit, List<HabitLog> recentLogs});
      final calendarLogs = results[1] as List<HabitLog>;
      final streak = deriveHabitStreakFromLogs(
        logs: calendarLogs,
        today: _today,
        startDate: detail.habit.startDate,
        fallbackCurrent: detail.habit.currentStreak,
        fallbackLongest: detail.habit.longestStreak,
      );
      setState(() {
        _habit = _habitWithStreak(detail.habit, streak.current, streak.longest);
        _recentLogs = detail.recentLogs;
        _calendarLogs = calendarLogs;
      });
      await _loadRelatedTodos();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_habit == null) {
        setState(() => _loadError = e.vnMessage);
      } else {
        _showError(e.vnMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRelatedTodos() async {
    final local = await TodosRepository.instance.listByHabitLocal(
      widget.habitId,
    );
    if (mounted) setState(() => _relatedTodos = local);
    try {
      final remote = await TodosRepository.instance.list(
        habitId: widget.habitId,
        limit: 100,
      );
      if (mounted) setState(() => _relatedTodos = remote.items);
    } on ApiException catch (e) {
      if (e.code != 'no_connection' && mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _openTodo(Todo todo) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: todo.id)),
    );
    if (mounted) _loadRelatedTodos();
  }

  Future<void> _openEdit() async {
    final habit = _habit;
    if (habit == null) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => HabitEditScreen(habit: habit)));
    if (mounted) _load();
  }

  Future<void> _setTodayLog(bool completed) async {
    final previous = _logForDate(_today);
    if (previous?.completed == completed) return;
    final optimistic = HabitLog(
      id: previous?.id ?? 'optimistic-${_today.millisecondsSinceEpoch}',
      habitId: widget.habitId,
      logDate: _today,
      completed: completed,
      note: previous?.note,
    );
    setState(() {
      _logging = true;
      _replaceLocalLog(optimistic);
    });
    try {
      final res = await HabitsRepository.instance.logHabit(
        widget.habitId,
        logDate: _today,
        completed: completed,
      );
      if (!mounted) return;
      setState(() {
        _replaceLocalLog(res.log);
        _habit = _copyHabitWithStreak(res.currentStreak, res.longestStreak);
      });
      if (res.log.completed) {
        AppHaptics.medium();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('+1 streak! 🔥 (${res.currentStreak} ngày)'),
              duration: const Duration(seconds: 1),
            ),
          );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          if (previous == null) {
            _removeLocalLog(_today);
          } else {
            _replaceLocalLog(previous);
          }
        });
        _showError(e.vnMessage);
      }
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  // EXP 5
  Future<void> _toggleArchive() async {
    if (_habit == null) return;
    try {
      final updated = _habit!.isArchived
          ? await HabitsRepository.instance.unarchive(widget.habitId)
          : await HabitsRepository.instance.archive(widget.habitId);
      if (!mounted) return;
      setState(() => _habit = updated);
      showAppSnack(
        context,
        updated.isArchived ? 'Đã lưu trữ' : 'Đã bỏ lưu trữ',
      );
      if (updated.isArchived) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: 'Xóa thói quen?',
      message: 'Tất cả log sẽ không truy cập được nữa.',
      confirmLabel: 'Xóa',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    try {
      await HabitsRepository.instance.delete(widget.habitId);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  // EXP 6
  Future<void> _onLongPressCell(DateTime date, HabitLog? log) async {
    if (date.isAfter(_today)) {
      showAppSnack(context, 'Không thể log ngày tương lai');
      return;
    }
    AppHaptics.medium();
    final action = await showAppSheet<String>(
      context: context,
      builder: (ctx) => AppSheetScaffold(
        title: AppDateUtils.formatDate(date),
        child: AppListSection(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          dividerIndent: AppListSection.iconIndent,
          children: [
            AppListTile(
              icon: Icons.check_circle_rounded,
              iconColor: AppColors.success,
              title: 'Đánh dấu hoàn thành',
              showChevron: false,
              onTap: () => Navigator.of(ctx).pop('done'),
            ),
            AppListTile(
              icon: Icons.cancel_rounded,
              iconColor: AppColors.tagSlate,
              title: 'Đánh dấu chưa làm',
              showChevron: false,
              onTap: () => Navigator.of(ctx).pop('undone'),
            ),
            AppListTile(
              icon: Icons.sticky_note_2_rounded,
              iconColor: AppColors.tagAmber,
              title: 'Thêm/sửa ghi chú',
              showChevron: false,
              onTap: () => Navigator.of(ctx).pop('note'),
            ),
            if (log != null)
              AppListTile(
                icon: Icons.delete_rounded,
                title: 'Xóa log',
                destructive: true,
                showChevron: false,
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'done' || action == 'undone') {
      final completed = action == 'done';
      final previous = log;
      final optimistic = HabitLog(
        id: previous?.id ?? 'optimistic-${date.millisecondsSinceEpoch}',
        habitId: widget.habitId,
        logDate: date,
        completed: completed,
        note: previous?.note,
      );
      try {
        setState(() => _replaceLocalLog(optimistic));
        late final ({HabitLog log, int currentStreak, int longestStreak}) res;
        if (log == null) {
          res = await HabitsRepository.instance.logHabit(
            widget.habitId,
            logDate: date,
            completed: completed,
          );
        } else {
          res = await HabitsRepository.instance.patchLog(
            widget.habitId,
            date,
            completed: completed,
          );
        }
        if (!mounted) return;
        setState(() {
          _replaceLocalLog(res.log);
          _habit = _copyHabitWithStreak(res.currentStreak, res.longestStreak);
        });
      } on ApiException catch (e) {
        if (mounted) {
          setState(() {
            if (previous == null) {
              _removeLocalLog(date);
            } else {
              _replaceLocalLog(previous);
            }
          });
          _showError(e.vnMessage);
        }
      }
    } else if (action == 'note') {
      _editNote(date, log);
    } else if (action == 'delete') {
      final previous = log;
      try {
        setState(() => _removeLocalLog(date));
        final res = await HabitsRepository.instance.deleteLog(
          widget.habitId,
          date,
        );
        if (!mounted) return;
        setState(() {
          _habit = _copyHabitWithStreak(res.currentStreak, res.longestStreak);
        });
      } on ApiException catch (e) {
        if (mounted) {
          if (previous != null) setState(() => _replaceLocalLog(previous));
          _showError(e.vnMessage);
        }
      }
    }
  }

  Future<void> _editNote(DateTime date, HabitLog? log) async {
    final ctrl = TextEditingController(text: log?.note ?? '');
    final newNote = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('Ghi chú · ${AppDateUtils.formatDate(date)}'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText: 'Ghi chú (tối đa 1000 ký tự)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (newNote == null) return;
    final note = newNote.isEmpty ? null : newNote;
    final previous = log;
    final optimistic = HabitLog(
      id: previous?.id ?? 'optimistic-${date.millisecondsSinceEpoch}',
      habitId: widget.habitId,
      logDate: date,
      completed: previous?.completed ?? false,
      note: note,
    );
    try {
      setState(() => _replaceLocalLog(optimistic));
      late final ({HabitLog log, int currentStreak, int longestStreak}) res;
      if (log == null) {
        res = await HabitsRepository.instance.logHabit(
          widget.habitId,
          logDate: date,
          completed: false,
          note: note,
        );
      } else {
        res = await HabitsRepository.instance.patchLog(
          widget.habitId,
          date,
          note: note,
          updateNote: true,
        );
      }
      if (!mounted) return;
      setState(() {
        _replaceLocalLog(res.log);
        _habit = _copyHabitWithStreak(res.currentStreak, res.longestStreak);
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          if (previous == null) {
            _removeLocalLog(date);
          } else {
            _replaceLocalLog(previous);
          }
        });
        _showError(e.vnMessage);
      }
    }
  }

  HabitLog? _logForDate(DateTime date) {
    for (final log in _calendarLogs) {
      if (AppDateUtils.isSameDay(log.logDate, date)) return log;
    }
    return null;
  }

  void _replaceLocalLog(HabitLog log) {
    final date = AppDateUtils.dateOnly(log.logDate);
    _calendarLogs = [
      for (final existing in _calendarLogs)
        if (!AppDateUtils.isSameDay(existing.logDate, date)) existing,
      log,
    ];
    _calendarLogs.sort((a, b) => a.logDate.compareTo(b.logDate));
    _recentLogs = [
      for (final existing in _recentLogs)
        if (!AppDateUtils.isSameDay(existing.logDate, date)) existing,
      if (log.note != null && log.note!.isNotEmpty) log,
    ];
    _recentLogs.sort((a, b) => b.logDate.compareTo(a.logDate));
  }

  void _removeLocalLog(DateTime date) {
    _calendarLogs = [
      for (final log in _calendarLogs)
        if (!AppDateUtils.isSameDay(log.logDate, date)) log,
    ];
    _recentLogs = [
      for (final log in _recentLogs)
        if (!AppDateUtils.isSameDay(log.logDate, date)) log,
    ];
  }

  Habit? _copyHabitWithStreak(int currentStreak, int longestStreak) {
    final habit = _habit;
    if (habit == null) return null;
    return _habitWithStreak(habit, currentStreak, longestStreak);
  }

  Habit _habitWithStreak(Habit habit, int currentStreak, int longestStreak) {
    return Habit(
      id: habit.id,
      title: habit.title,
      description: habit.description,
      iconName: habit.iconName,
      icon: habit.icon,
      color: habit.color,
      frequencyType: habit.frequencyType,
      targetPerPeriod: habit.targetPerPeriod,
      activeWeekdays: habit.activeWeekdays,
      startDate: habit.startDate,
      endDate: habit.endDate,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      isArchived: habit.isArchived,
    );
  }

  void _showError(String msg) {
    showAppSnack(context, msg, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _habit == null) {
      return Scaffold(appBar: AppBar(), body: const AppSpinner());
    }
    if (_habit == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _loadError != null
            ? AppErrorState(message: _loadError!, onRetry: _load)
            : const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Không tìm thấy thói quen',
              ),
      );
    }
    final textSecondary = context.appTextSecondary;
    final habit = _habit!;
    final logsByDate = <DateTime, HabitLog>{
      for (final l in _calendarLogs) AppDateUtils.dateOnly(l.logDate): l,
    };
    final sevenDayStart = _today.subtract(const Duration(days: 6));
    final thirtyDayStart = _today.subtract(const Duration(days: 29));
    final sevenDayCount = _calendarLogs
        .where(
          (l) =>
              !l.logDate.isBefore(sevenDayStart) &&
              !l.logDate.isAfter(_today) &&
              l.completed,
        )
        .length;
    final thirtyDayCount = _calendarLogs
        .where(
          (l) =>
              !l.logDate.isBefore(thirtyDayStart) &&
              !l.logDate.isAfter(_today) &&
              l.completed,
        )
        .length;
    final todayLog = _logForDate(_today);
    final notesLogs = _recentLogs.where((l) => l.note != null).take(5).toList();
    // Chữ huy hiệu "kỷ lục": vàng đậm hơn ở light mode để đủ tương phản.
    final recordText = context.isDark
        ? AppColors.streakGold
        : const Color(0xFFB45309);

    return Scaffold(
      appBar: AppBar(
        title: Text(habit.title),
        backgroundColor: habit.color.withValues(alpha: 0.12),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Chỉnh sửa',
            onPressed: _openEdit,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) {
              if (v == 'archive') {
                _toggleArchive();
              } else if (v == 'delete') {
                _confirmDelete();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(
                      habit.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(habit.isArchived ? 'Bỏ lưu trữ' : 'Lưu trữ'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: AppColors.danger,
                    ),
                    SizedBox(width: 12),
                    Text('Xóa', style: TextStyle(color: AppColors.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // Hero header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    habit.color.withValues(alpha: 0.18),
                    habit.color.withValues(alpha: 0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: AppMotion.normal,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Text(
                      '${habit.currentStreak}',
                      key: ValueKey(habit.currentStreak),
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -2,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: AppColors.streakGold,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ngày liên tiếp',
                        style: TextStyle(fontSize: 16, color: textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: ShapeDecoration(
                      color: AppColors.streakGold.withValues(alpha: 0.18),
                      shape: AppShape.pill,
                    ),
                    child: Text(
                      'Kỷ lục: ${habit.longestStreak} ngày',
                      style: TextStyle(
                        fontSize: 12,
                        color: recordText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Today CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: AppSurface(
                padding: const EdgeInsets.all(16),
                child: HabitTodayLogPanel(
                  completed: todayLog?.completed,
                  busy: _logging,
                  onLog: _setTodayLog,
                ),
              ),
            ),

            const SectionHeader(label: '28 ngày gần đây (nhấn giữ để sửa)'),
            HabitCalendarGrid(
              habit: habit,
              completedByDate: {
                for (final entry in logsByDate.entries)
                  entry.key: entry.value.completed,
              },
              today: _today,
              onLongPress: (date) => _onLongPressCell(date, logsByDate[date]),
            ),
            const SizedBox(height: 16),

            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _statCard(
                      '7 ngày gần đây',
                      '$sevenDayCount/7',
                      textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      '30 ngày gần đây',
                      '$thirtyDayCount/30',
                      textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (notesLogs.isNotEmpty) ...[
              const SectionHeader(label: 'Ghi chú gần đây'),
              AppListSection(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                dividerIndent: AppListSection.iconIndent,
                children: [
                  for (final l in notesLogs)
                    AppListTile(
                      icon: Icons.sticky_note_2_rounded,
                      iconColor: AppColors.tagAmber,
                      title: l.note ?? '',
                      subtitle: AppDateUtils.formatDate(l.logDate),
                    ),
                ],
              ),
            ],
            const SectionHeader(label: 'Todos liên quan'),
            if (_relatedTodos.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                child: Text(
                  'Chưa có todo liên kết',
                  style: TextStyle(color: textSecondary),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppSurface(
                  clipBehavior: Clip.antiAlias,
                  showShadow: false,
                  child: Column(
                    children: [
                      for (final todo in _relatedTodos)
                        TodoTile(
                          todo: todo,
                          compact: true,
                          onTap: () => _openTodo(todo),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color secondary) {
    return AppSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: secondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
