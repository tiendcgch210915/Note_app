import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../models/habit.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/habit_streak_utils.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/habit_card.dart';
import 'habit_detail_screen.dart';

class HabitsListScreen extends StatefulWidget {
  const HabitsListScreen({super.key});

  @override
  State<HabitsListScreen> createState() => _HabitsListScreenState();
}

class _HabitsListScreenState extends State<HabitsListScreen> {
  bool _showArchived = false;
  bool _loading = false;
  List<Habit> _habits = [];
  Map<DateTime, Map<String, bool>> _weekCal = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final today = AppDateUtils.dateOnly(DateTime.now());
      final habitsFut = HabitsRepository.instance.list(
        includeArchived: _showArchived,
      );
      final calFut = HabitsRepository.instance.getCalendar(
        from: today.subtract(const Duration(days: 29)),
        to: today,
      );
      final results = await Future.wait([habitsFut, calFut]);
      if (!mounted) return;
      setState(() {
        _habits = results[0] as List<Habit>;
        _weekCal = results[1] as Map<DateTime, Map<String, bool>>;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.vnMessage),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _completionsLastWeek(String habitId) {
    final today = AppDateUtils.dateOnly(DateTime.now());
    final start = today.subtract(const Duration(days: 6));
    var count = 0;
    _weekCal.forEach((date, map) {
      final day = AppDateUtils.dateOnly(date);
      if (!day.isBefore(start) && !day.isAfter(today) && map[habitId] == true) {
        count++;
      }
    });
    return count;
  }

  Habit _habitWithCalendarStreak(Habit habit) {
    final completedByDate = <DateTime, bool>{};
    for (final entry in _weekCal.entries) {
      if (entry.value.containsKey(habit.id)) {
        completedByDate[AppDateUtils.dateOnly(entry.key)] =
            entry.value[habit.id]!;
      }
    }
    final streak = deriveHabitStreakFromCompletionMap(
      completedByDate: completedByDate,
      today: AppDateUtils.dateOnly(DateTime.now()),
      startDate: habit.startDate,
      fallbackCurrent: habit.currentStreak,
      fallbackLongest: habit.longestStreak,
    );
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
      currentStreak: streak.current,
      longestStreak: streak.longest,
      isArchived: habit.isArchived,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _habits.isEmpty) {
      return Column(
        children: [
          _ArchiveToggle(
            showArchived: _showArchived,
            onChanged: _setShowArchived,
          ),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    return Column(
      children: [
        _ArchiveToggle(
          showArchived: _showArchived,
          onChanged: _setShowArchived,
        ),
        Expanded(child: _habits.isEmpty ? _emptyState() : _habitsGrid()),
      ],
    );
  }

  void _setShowArchived(bool value) {
    if (_showArchived == value) return;
    setState(() => _showArchived = value);
    _refresh();
  }

  Widget _emptyState() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 360,
            child: EmptyState(
              icon: Icons.local_fire_department_outlined,
              title: _showArchived
                  ? 'Không có habit lưu trữ'
                  : 'Chưa có thói quen nào',
              subtitle: _showArchived
                  ? 'Các thói quen đã lưu trữ sẽ xuất hiện tại đây.'
                  : 'Thêm thói quen đầu tiên để bắt đầu xây streak.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _habitsGrid() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.72,
        ),
        itemCount: _habits.length,
        itemBuilder: (ctx, i) {
          final h = _habits[i];
          return HabitCard(
            habit: _habitWithCalendarStreak(h),
            recentCompletions: _completionsLastWeek(h.id),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HabitDetailScreen(habitId: h.id),
                ),
              );
              if (mounted) _refresh();
            },
          );
        },
      ),
    );
  }
}

class _ArchiveToggle extends StatelessWidget {
  final bool showArchived;
  final ValueChanged<bool> onChanged;

  const _ArchiveToggle({required this.showArchived, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          const Text('Hiện archived'),
          Switch(value: showArchived, onChanged: onChanged),
        ],
      ),
    );
  }
}
