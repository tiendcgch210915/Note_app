import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../models/habit.dart';
import '../../models/habit_log.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../widgets/primary_button.dart';
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
        from: _today.subtract(const Duration(days: 27)),
        to: _today,
      );
      final results = await Future.wait([detailFut, logsFut]);
      if (!mounted) return;
      final detail = results[0] as ({Habit habit, List<HabitLog> recentLogs});
      setState(() {
        _habit = detail.habit;
        _recentLogs = detail.recentLogs;
        _calendarLogs = results[1] as List<HabitLog>;
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _doneToday {
    return _calendarLogs.any((l) =>
        AppDateUtils.isSameDay(l.logDate, _today) && l.completed);
  }

  Future<void> _toggleTodayLog() async {
    setState(() => _logging = true);
    try {
      final res = await HabitsRepository.instance.logHabit(
        widget.habitId,
        logDate: _today,
        completed: !_doneToday,
      );
      if (!mounted) return;
      setState(() {
        _habit = _habit == null
            ? null
            : Habit(
                id: _habit!.id,
                title: _habit!.title,
                description: _habit!.description,
                iconName: _habit!.iconName,
                icon: _habit!.icon,
                color: _habit!.color,
                frequencyType: _habit!.frequencyType,
                targetPerPeriod: _habit!.targetPerPeriod,
                activeWeekdays: _habit!.activeWeekdays,
                startDate: _habit!.startDate,
                endDate: _habit!.endDate,
                currentStreak: res.currentStreak,
                longestStreak: res.longestStreak,
                isArchived: _habit!.isArchived,
              );
      });
      if (res.log.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('+1 streak! 🔥 (${res.currentStreak} ngày)'), duration: const Duration(seconds: 1)),
        );
      }
      _load(); // re-fetch logs
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
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
        SnackBar(content: Text(updated.isArchived ? 'Đã lưu trữ' : 'Đã bỏ lưu trữ')),
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
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
                leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                title: const Text('Xóa log', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'done' || action == 'undone') {
      final completed = action == 'done';
      try {
        if (log == null) {
          await HabitsRepository.instance.logHabit(widget.habitId, logDate: date, completed: completed);
        } else {
          await HabitsRepository.instance.patchLog(widget.habitId, date, completed: completed);
        }
        _load();
      } on ApiException catch (e) {
        if (mounted) _showError(e.vnMessage);
      }
    } else if (action == 'note') {
      _editNote(date, log);
    } else if (action == 'delete') {
      try {
        await HabitsRepository.instance.deleteLog(widget.habitId, date);
        _load();
      } on ApiException catch (e) {
        if (mounted) _showError(e.vnMessage);
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
          decoration: const InputDecoration(hintText: 'Ghi chú (tối đa 1000 ký tự)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (newNote == null) return;
    try {
      if (log == null) {
        await HabitsRepository.instance.logHabit(
          widget.habitId,
          logDate: date,
          completed: false,
          note: newNote.isEmpty ? null : newNote,
        );
      } else {
        await HabitsRepository.instance.patchLog(
          widget.habitId,
          date,
          note: newNote,
        );
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
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
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final habit = _habit!;
    final logsByDate = <DateTime, HabitLog>{
      for (final l in _calendarLogs) AppDateUtils.dateOnly(l.logDate): l,
    };
    final weekCount = _calendarLogs
        .where((l) => l.logDate.isAfter(_today.subtract(const Duration(days: 7))) && l.completed)
        .length;
    final monthCount = _calendarLogs.where((l) => l.completed).length;
    final ratio = _calendarLogs.isEmpty
        ? 0
        : (_calendarLogs.where((l) => l.completed).length * 100 / _calendarLogs.length).round();
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
                  colors: [habit.color.withValues(alpha: 0.18), Colors.transparent],
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
                      const Icon(Icons.local_fire_department, color: AppColors.streakGold),
                      const SizedBox(width: 6),
                      Text('ngày liên tiếp', style: TextStyle(fontSize: 16, color: textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                      _doneToday ? 'Bạn đã hoàn thành hôm nay' : 'Đã hoàn thành hôm nay chưa?',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: _doneToday ? 'Đã hoàn thành ✓ (bỏ chọn)' : 'Đánh dấu hoàn thành',
                      icon: Icons.check,
                      loading: _logging,
                      onPressed: _toggleTodayLog,
                    ),
                  ],
                ),
              ),
            ),

            const SectionHeader(label: '28 ngày qua (long-press để sửa)'),
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
                  Expanded(child: _statCard('Tuần này', '$weekCount/7', textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(child: _statCard('Tháng này', '$monthCount/30', textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(child: _statCard('Tỉ lệ', '$ratio%', textSecondary)),
                ],
              ),
            ),
            if (notesLogs.isNotEmpty) ...[
              const SectionHeader(label: 'Ghi chú gần đây'),
              ...notesLogs.map((l) => ListTile(
                    leading: Icon(Icons.note_outlined, color: textSecondary),
                    title: Text(l.note ?? ''),
                    subtitle: Text(AppDateUtils.formatDate(l.logDate)),
                  )),
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
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
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
    final secondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;

    final cells = <Widget>[];
    for (var i = 27; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final log = logsByDate[date];
      Color bg;
      Color fg;
      if (log == null) {
        bg = surface;
        fg = secondary;
      } else if (log.completed) {
        bg = habit.color;
        fg = Colors.white;
      } else {
        bg = AppColors.q1.withValues(alpha: 0.15);
        fg = AppColors.q1;
      }
      cells.add(GestureDetector(
        onLongPress: () => onLongPress(date, log),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text('${date.day}',
              style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: cells,
      ),
    );
  }
}
