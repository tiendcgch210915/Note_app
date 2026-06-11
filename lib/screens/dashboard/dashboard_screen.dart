import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/dashboard_repository.dart';
import '../../data/habits_repository.dart';
import '../../models/dashboard.dart';
import '../../models/habit.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../widgets/eisenhower_grid.dart';
import '../../widgets/score_ring.dart';
import '../../widgets/section_header.dart';
import '../todos/todo_detail_screen.dart';
import 'quadrant_todos_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardSnapshot? _snapshot;
  EisenhowerDetail? _eisenhower;
  List<Habit> _habits = [];
  Map<DateTime, Map<String, bool>> _todayCal = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final today = AppDateUtils.dateOnly(DateTime.now());
      final results = await Future.wait([
        DashboardRepository.instance.today(date: today),
        DashboardRepository.instance.eisenhower(date: today),
        HabitsRepository.instance.list(),
        HabitsRepository.instance.getCalendar(from: today, to: today),
      ]);
      if (!mounted) return;
      setState(() {
        _snapshot = results[0] as DashboardSnapshot;
        _eisenhower = results[1] as EisenhowerDetail;
        _habits = results[2] as List<Habit>;
        _todayCal = results[3] as Map<DateTime, Map<String, bool>>;
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tải được dashboard'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleHabit(Habit habit) async {
    final today = AppDateUtils.dateOnly(DateTime.now());
    final current = _todayCal[today]?[habit.id] ?? false;
    final next = !current;
    setState(() {
      final dayMap = Map<String, bool>.from(_todayCal[today] ?? const {});
      dayMap[habit.id] = next;
      _todayCal = {..._todayCal, today: dayMap};
      _snapshot = _snapshotWithHabitCompletion(next ? 1 : -1);
    });
    try {
      await HabitsRepository.instance.logHabit(
        habit.id,
        logDate: today,
        completed: next,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          final dayMap = Map<String, bool>.from(_todayCal[today] ?? const {});
          dayMap[habit.id] = current;
          _todayCal = {..._todayCal, today: dayMap};
          _snapshot = _snapshotWithHabitCompletion(next ? -1 : 1);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.vnMessage)));
      }
    }
  }

  void _openQuadrant(Quadrant q) {
    if (_eisenhower == null) return;
    final key = _dashboardQuadrantKey(q);
    final todos = _eisenhower!.byQuadrant[key] ?? const [];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuadrantTodosScreen(quadrant: q, todos: todos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_snapshot == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Không tải được dashboard'),
            const SizedBox(height: 8),
            TextButton(onPressed: _refresh, child: const Text('Thử lại')),
          ],
        ),
      );
    }
    final snap = _snapshot!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              AppDateUtils.formatDashboardTitle(snap.date),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          _ScoreCard(snapshot: snap),
          if (snap.frog != null) ...[
            const SizedBox(height: 12),
            _FrogCard(frog: snap.frog!, onRefresh: _refresh),
          ],
          const SectionHeader(label: 'Ma trận Eisenhower'),
          EisenhowerGrid(
            counts: _eisenhower?.counts ?? snap.eisenhowerCounts,
            previews: _eisenhower?.byQuadrant,
            onTap: _openQuadrant,
          ),
          SectionHeader(
            label: 'Bạn có ${_habits.length} thói quen cần duy trì',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: _buildHabitChips()),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildHabitChips() {
    if (_habits.isEmpty) return [];
    final today = AppDateUtils.dateOnly(DateTime.now());
    final widgets = <Widget>[];
    final habitsToShow = _habits.take(3).toList();
    for (var i = 0; i < habitsToShow.length; i++) {
      final h = habitsToShow[i];
      final done = _todayCal[today]?[h.id] ?? false;
      widgets.add(
        Expanded(
          child: _HabitChipCard(
            habit: h,
            completed: done,
            onToggle: () => _toggleHabit(h),
          ),
        ),
      );
      if (i < habitsToShow.length - 1) widgets.add(const SizedBox(width: 8));
    }
    return widgets;
  }

  DashboardSnapshot? _snapshotWithHabitCompletion(int delta) {
    final snap = _snapshot;
    if (snap == null) return null;
    final completed = (snap.habitsCompleted + delta)
        .clamp(0, snap.habitsTotal)
        .toInt();
    return DashboardSnapshot(
      date: snap.date,
      score: snap.score,
      todosTotal: snap.todosTotal,
      todosDone: snap.todosDone,
      eisenhowerCounts: snap.eisenhowerCounts,
      habitsTotal: snap.habitsTotal,
      habitsCompleted: completed,
      frog: snap.frog,
    );
  }

  String _dashboardQuadrantKey(Quadrant q) {
    switch (q) {
      case Quadrant.q1:
        return 'q1';
      case Quadrant.q2:
        return 'q2';
      case Quadrant.q3:
        return 'q3';
      case Quadrant.q4:
      case Quadrant.unclassified:
        return 'q4';
    }
  }
}

class _ScoreCard extends StatelessWidget {
  final DashboardSnapshot snapshot;
  const _ScoreCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.primarySoftDark : AppColors.primarySoft;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            ScoreRing(score: snapshot.score, size: 96, strokeWidth: 8),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label(snapshot.score),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Việc: ${snapshot.todosDone}/${snapshot.todosTotal} · Thói quen: ${snapshot.habitsCompleted}/${snapshot.habitsTotal}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(int score) {
    if (score >= 80) return 'Tuyệt vời!';
    if (score >= 60) return 'Khá tốt';
    if (score >= 40) return 'Tốt lắm!';
    if (score >= 20) return 'Cố gắng lên!';
    return 'Bắt đầu nào';
  }
}

class _FrogCard extends StatelessWidget {
  final FrogTodo frog;
  final VoidCallback onRefresh;
  const _FrogCard({required this.frog, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TodoDetailScreen(todoId: frog.id),
            ),
          );
          onRefresh();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            border: const Border(
              left: BorderSide(color: AppColors.frog, width: 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.eco, color: AppColors.frog, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'ƯU TIÊN HÔM NAY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppColors.frog,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                frog.title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  decoration: frog.isDone ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.q1.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  frog.isDone ? 'Hoàn thành' : 'Mở',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.q1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HabitChipCard extends StatelessWidget {
  final Habit habit;
  final bool completed;
  final VoidCallback onToggle;
  const _HabitChipCard({
    required this.habit,
    required this.completed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(habit.icon ?? Icons.flag, size: 18, color: habit.color),
                const Spacer(),
                Icon(
                  completed ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: completed ? habit.color : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              habit.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
