import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../models/habit.dart';
import '../../models/habit_log.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/habit_streak_utils.dart';
import '../../widgets/section_header.dart';

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
  bool _loading = false;
  bool _logging = false;

  DateTime get _today => AppDateUtils.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
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
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updated.isArchived ? 'Đã lưu trữ' : 'Đã bỏ lưu trữ'),
        ),
      );
      if (updated.isArchived) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa thói quen?'),
        content: const Text('Tất cả log sẽ không truy cập được nữa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể log ngày tương lai')),
      );
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Đánh dấu hoàn thành'),
              onTap: () => Navigator.of(ctx).pop('done'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Đánh dấu chưa làm'),
              onTap: () => Navigator.of(ctx).pop('undone'),
            ),
            ListTile(
              leading: const Icon(Icons.note_outlined),
              title: const Text('Thêm/sửa ghi chú'),
              onTap: () => Navigator.of(ctx).pop('note'),
            ),
            if (log != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.danger,
                ),
                title: const Text(
                  'Xóa log',
                  style: TextStyle(color: AppColors.danger),
                ),
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
        title: Text('Ghi chú · ${AppDateUtils.formatDate(date)}'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _habit == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_habit == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Không tìm thấy habit')),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
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

    return Scaffold(
      appBar: AppBar(
        title: Text(habit.title),
        backgroundColor: habit.color.withValues(alpha: 0.12),
        actions: [
          PopupMenuButton<String>(
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
                child: Text(habit.isArchived ? 'Bỏ lưu trữ' : 'Lưu trữ'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Xóa', style: TextStyle(color: AppColors.danger)),
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
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '${habit.currentStreak}',
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -2,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.local_fire_department,
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
                    decoration: BoxDecoration(
                      color: AppColors.streakGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Kỷ lục: ${habit.longestStreak} ngày',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.streakGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Today CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      todayLog == null
                          ? 'Đã hoàn thành hôm nay chưa?'
                          : todayLog.completed
                          ? 'Bạn đã hoàn thành hôm nay'
                          : 'Bạn đã đánh dấu bỏ lỡ hôm nay',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _TodayLogButton(
                            label: 'Hoàn thành',
                            icon: Icons.check_rounded,
                            color: AppColors.success,
                            selected: todayLog?.completed == true,
                            onPressed: _logging
                                ? null
                                : () => _setTodayLog(true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TodayLogButton(
                            label: 'Bỏ lỡ',
                            icon: Icons.close_rounded,
                            color: AppColors.danger,
                            selected: todayLog?.completed == false,
                            onPressed: _logging
                                ? null
                                : () => _setTodayLog(false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SectionHeader(label: '28 ngày gần đây (long-press để sửa)'),
            _CalendarGrid(
              habit: habit,
              logsByDate: logsByDate,
              today: _today,
              onLongPress: _onLongPressCell,
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
              ...notesLogs.map(
                (l) => ListTile(
                  leading: Icon(Icons.note_outlined, color: textSecondary),
                  title: Text(l.note ?? ''),
                  subtitle: Text(AppDateUtils.formatDate(l.logDate)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color secondary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: secondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _TodayLogButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onPressed;

  const _TodayLogButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : color;
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          elevation: selected ? 1 : 0,
          backgroundColor: selected ? color : color.withValues(alpha: 0.12),
          foregroundColor: foreground,
          disabledBackgroundColor: color.withValues(alpha: 0.08),
          disabledForegroundColor: color.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.55)),
          ),
        ),
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final Habit habit;
  final Map<DateTime, HabitLog> logsByDate;
  final DateTime today;
  final void Function(DateTime, HabitLog?) onLongPress;

  const _CalendarGrid({
    required this.habit,
    required this.logsByDate,
    required this.today,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark
        ? AppColors.dividerDark.withValues(alpha: 0.95)
        : AppColors.divider;
    final headerColor = isDark
        ? AppColors.backgroundDark.withValues(alpha: 0.65)
        : AppColors.background;
    final todayOnly = AppDateUtils.dateOnly(today);
    final habitStart = AppDateUtils.dateOnly(habit.startDate);
    final todayWeekStart = todayOnly.subtract(
      Duration(days: todayOnly.weekday - DateTime.monday),
    );
    final defaultGridStart = todayWeekStart.subtract(const Duration(days: 14));
    final gridStart = habitStart.isAfter(defaultGridStart)
        ? habitStart
        : defaultGridStart;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Column(
            children: [
              Row(
                children: List.generate(7, (index) {
                  final weekday = ((gridStart.weekday - 1 + index) % 7) + 1;
                  return Expanded(
                    child: Container(
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: headerColor,
                        border: Border.all(
                          color: borderColor.withValues(alpha: 0.75),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        AppDateUtils.weekdayShort(weekday),
                        style: TextStyle(
                          fontSize: 11,
                          color: secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              GridView.builder(
                itemCount: 28,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 0,
                  crossAxisSpacing: 0,
                  childAspectRatio: 0.72,
                ),
                itemBuilder: (context, index) {
                  final date = gridStart.add(Duration(days: index));
                  final log = logsByDate[date];
                  final isToday = AppDateUtils.isSameDay(date, today);
                  return _CalendarCell(
                    date: date,
                    log: log,
                    surface: surface,
                    secondary: secondary,
                    borderColor: borderColor,
                    accent: habit.color,
                    isToday: isToday,
                    onLongPress: () => onLongPress(date, log),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  final DateTime date;
  final HabitLog? log;
  final Color surface;
  final Color secondary;
  final Color borderColor;
  final Color accent;
  final bool isToday;
  final VoidCallback onLongPress;

  const _CalendarCell({
    required this.date,
    required this.log,
    required this.surface,
    required this.secondary,
    required this.borderColor,
    required this.accent,
    required this.isToday,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = isToday ? accent : secondary;
    return GestureDetector(
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        decoration: BoxDecoration(
          color: isToday
              ? Color.alphaBlend(accent.withValues(alpha: 0.14), surface)
              : surface,
          border: Border.all(
            color: isToday ? accent : borderColor.withValues(alpha: 0.75),
            width: isToday ? 1.4 : 0.6,
          ),
          boxShadow: isToday
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 30,
              child: Center(
                child: log?.completed == true
                    ? _FlameIcon(completed: true, size: isToday ? 28 : 24)
                    : log == null
                    ? const SizedBox.shrink()
                    : _FlameIcon(completed: false, size: isToday ? 28 : 24),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}/${date.month}',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 10,
                height: 1,
                color: labelColor,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlameIcon extends StatelessWidget {
  final bool completed;
  final double size;

  const _FlameIcon({required this.completed, required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FlamePainter(completed: completed),
    );
  }
}

class _FlamePainter extends CustomPainter {
  final bool completed;

  const _FlamePainter({required this.completed});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outerPath = Path()
      ..moveTo(w * 0.58, h * 0.02)
      ..cubicTo(w * 0.34, h * 0.19, w * 0.43, h * 0.37, w * 0.36, h * 0.49)
      ..cubicTo(w * 0.28, h * 0.39, w * 0.28, h * 0.29, w * 0.18, h * 0.22)
      ..cubicTo(w * 0.21, h * 0.41, w * 0.08, h * 0.50, w * 0.08, h * 0.68)
      ..cubicTo(w * 0.08, h * 0.88, w * 0.27, h * 0.99, w * 0.46, h * 0.98)
      ..cubicTo(w * 0.34, h * 0.89, w * 0.39, h * 0.74, w * 0.49, h * 0.64)
      ..cubicTo(w * 0.54, h * 0.76, w * 0.67, h * 0.83, w * 0.58, h * 0.98)
      ..cubicTo(w * 0.78, h * 0.94, w * 0.93, h * 0.79, w * 0.90, h * 0.59)
      ..cubicTo(w * 0.88, h * 0.42, w * 0.76, h * 0.32, w * 0.78, h * 0.18)
      ..cubicTo(w * 0.66, h * 0.25, w * 0.65, h * 0.38, w * 0.58, h * 0.02)
      ..close();

    final outerColors = completed
        ? const [Color(0xFFFF2D14), Color(0xFFFF7A18), Color(0xFFFFE45C)]
        : const [Color(0xFF0B6DFF), Color(0xFF1688FF), Color(0xFF74D2FF)];
    final outerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: outerColors,
      ).createShader(Offset.zero & size);
    canvas.drawPath(outerPath, outerPaint);

    final innerPath = Path()
      ..moveTo(w * 0.50, h * 0.96)
      ..cubicTo(w * 0.33, h * 0.86, w * 0.39, h * 0.70, w * 0.50, h * 0.59)
      ..cubicTo(w * 0.57, h * 0.71, w * 0.72, h * 0.79, w * 0.62, h * 0.96)
      ..cubicTo(w * 0.58, h * 0.99, w * 0.53, h * 0.99, w * 0.50, h * 0.96)
      ..close();
    final innerColors = completed
        ? const [Color(0xFFFFFFFF), Color(0xFFFFF46A), Color(0xFFFFB23F)]
        : const [Color(0xFFE8F7FF), Color(0xFF7DDCFF), Color(0xFF1E9BFF)];
    final innerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: innerColors,
      ).createShader(Offset.zero & size);
    canvas.drawPath(innerPath, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _FlamePainter oldDelegate) {
    return oldDelegate.completed != completed;
  }
}
