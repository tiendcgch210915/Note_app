import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/dashboard_repository.dart';
import '../../data/habits_repository.dart';
import '../../models/dashboard.dart';
import '../../models/habit.dart';
import '../../theme/app_colors.dart';
import '../../utils/dashboard_habit_visibility.dart';
import '../../utils/dashboard_local_events.dart';
import '../../utils/date_utils.dart';
import '../../utils/habit_streak_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../widgets/dashboard_habit_card.dart';
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
  bool _celebratedExceptionalScore = false;
  OverlayEntry? _celebrationOverlay;
  int _refreshSeq = 0;

  @override
  void initState() {
    super.initState();
    DashboardLocalEvents.instance.revision.addListener(_onLocalDashboardChange);
    _refresh();
  }

  @override
  void dispose() {
    DashboardLocalEvents.instance.revision.removeListener(
      _onLocalDashboardChange,
    );
    _celebrationOverlay?.remove();
    _celebrationOverlay = null;
    super.dispose();
  }

  void _onLocalDashboardChange() {
    unawaited(_refresh(useLocalFallback: false));
  }

  Future<void> _refresh({bool useLocalFallback = true}) async {
    final seq = ++_refreshSeq;
    if (_snapshot == null) setState(() => _loading = true);
    if (useLocalFallback) {
      await _loadLocalDashboard(allowEmpty: _snapshot != null);
    }
    try {
      final today = AppDateUtils.dateOnly(DateTime.now());
      final results = await Future.wait([
        DashboardRepository.instance.today(date: today),
        DashboardRepository.instance.eisenhower(date: today),
        HabitsRepository.instance.list(),
        HabitsRepository.instance.getCalendar(
          from: today.subtract(const Duration(days: 29)),
          to: today,
        ),
      ]);
      final snapshot = results[0] as DashboardSnapshot;
      if (!mounted || seq != _refreshSeq) return;
      setState(() {
        _snapshot = snapshot;
        _eisenhower = results[1] as EisenhowerDetail;
        _habits = (results[2] as List<Habit>)
            .where((habit) => !habit.isArchived)
            .toList();
        _todayCal = results[3] as Map<DateTime, Map<String, bool>>;
      });
      _maybeCelebrateExceptionalScore(snapshot.score);
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
      if (mounted && seq == _refreshSeq) setState(() => _loading = false);
    }
  }

  Future<void> _loadLocalDashboard({required bool allowEmpty}) async {
    final today = AppDateUtils.dateOnly(DateTime.now());
    final local = await DashboardRepository.instance.localTodayData(
      date: today,
    );
    if (!mounted) return;
    if (!allowEmpty && !local.hasData) return;
    setState(() {
      _snapshot = local.snapshot;
      _eisenhower = local.eisenhower;
      _habits = local.habits;
      _todayCal = local.todayCal;
    });
    _maybeCelebrateExceptionalScore(local.snapshot.score);
  }

  void _maybeCelebrateExceptionalScore(int score) {
    if (score <= 100) {
      _celebratedExceptionalScore = false;
      return;
    }
    if (_celebratedExceptionalScore || !mounted) return;
    _celebratedExceptionalScore = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showExceptionalScoreCelebration();
    });
  }

  void _showExceptionalScoreCelebration() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trên cả tuyệt vời'),
        backgroundColor: AppColors.warning,
        duration: Duration(seconds: 2),
      ),
    );

    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.accessibleNavigation == true || media?.disableAnimations == true;
    if (reduceMotion) return;

    _celebrationOverlay?.remove();
    _celebrationOverlay = null;
    final overlay = Navigator.of(context).overlay;
    if (overlay == null) return;
    final entry = OverlayEntry(builder: (_) => const _ScoreConfettiOverlay());
    _celebrationOverlay = entry;
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (_celebrationOverlay != entry) return;
      entry.remove();
      _celebrationOverlay = null;
    });
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
      final result = await HabitsRepository.instance.logHabit(
        habit.id,
        logDate: today,
        completed: next,
      );
      if (!mounted) return;
      setState(() {
        _habits = [
          for (final item in _habits)
            item.id == habit.id
                ? _copyHabitWithStreak(
                    item,
                    currentStreak: result.currentStreak,
                    longestStreak: result.longestStreak,
                  )
                : item,
        ];
      });
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

  void _openQuadrant(Quadrant q) async {
    if (_eisenhower == null) return;
    final key = _dashboardQuadrantKey(q);
    final todos = _eisenhower!.byQuadrant[key] ?? const [];
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuadrantTodosScreen(
          quadrant: q,
          todos: todos,
          date: _eisenhower!.date,
        ),
      ),
    );
    if (mounted) _refresh();
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
    final today = AppDateUtils.dateOnly(DateTime.now());
    final remainingHabits = remainingDashboardHabitsForDate(
      habits: _habits,
      habitLogsByDate: _todayCal,
      date: today,
    ).map(_habitWithCalendarStreak).toList(growable: false);
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
            label:
                'Bạn còn ${remainingHabits.length} thói quen cho ngày hôm nay',
          ),
          if (remainingHabits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _HabitChipGrid(
                habits: remainingHabits,
                completedByHabitId: _todayCal[today] ?? const {},
                onToggle: _toggleHabit,
              ),
            ),
        ],
      ),
    );
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

  Habit _habitWithCalendarStreak(Habit habit) {
    final completedByDate = <DateTime, bool>{};
    for (final entry in _todayCal.entries) {
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
    return _copyHabitWithStreak(
      habit,
      currentStreak: streak.current,
      longestStreak: streak.longest,
    );
  }

  Habit _copyHabitWithStreak(
    Habit habit, {
    required int currentStreak,
    required int longestStreak,
  }) {
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
}

class _ScoreCard extends StatelessWidget {
  final DashboardSnapshot snapshot;
  const _ScoreCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final exceptional = snapshot.score > 100;
    final belowMinimumGate =
        snapshot.score == 0 &&
        (snapshot.todosTotal < 3 || snapshot.todosDone < 3);
    final bg = exceptional
        ? AppColors.warning.withValues(alpha: isDark ? 0.18 : 0.12)
        : isDark
        ? AppColors.primarySoftDark
        : AppColors.primarySoft;
    final borderColor = exceptional
        ? AppColors.warning.withValues(alpha: 0.75)
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: exceptional ? 1.4 : 0),
          boxShadow: exceptional
              ? [
                  BoxShadow(
                    color: AppColors.warning.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            ScoreRing(
              score: snapshot.score,
              size: 96,
              strokeWidth: 8,
              color: exceptional ? AppColors.warning : null,
            ),
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
                  if (exceptional) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+${snapshot.score - 100} vượt mốc',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
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
                  if (belowMinimumGate) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Cần ít nhất 3 việc hoàn thành để tính điểm',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(int score) {
    if (score > 100) return 'Trên cả tuyệt vời';
    if (score == 100) return 'Tròn 100 điểm';
    if (score >= 80) return 'Tuyệt vời!';
    if (score >= 60) return 'Khá tốt';
    if (score >= 40) return 'Tốt lắm!';
    if (score >= 20) return 'Cố gắng lên!';
    return 'Bắt đầu nào';
  }
}

class _ScoreConfettiOverlay extends StatefulWidget {
  const _ScoreConfettiOverlay();

  @override
  State<_ScoreConfettiOverlay> createState() => _ScoreConfettiOverlayState();
}

class _ScoreConfettiOverlayState extends State<_ScoreConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    final random = math.Random(115);
    const colors = [
      AppColors.warning,
      AppColors.danger,
      AppColors.success,
      AppColors.primary,
    ];
    _pieces = List.generate(72, (index) {
      return _ConfettiPiece(
        startX: random.nextDouble(),
        delay: random.nextDouble() * 0.18,
        drift: (random.nextDouble() - 0.5) * 180,
        fall: 0.55 + random.nextDouble() * 0.45,
        size: 4 + random.nextDouble() * 6,
        spin: random.nextDouble() * math.pi * 2,
        color: colors[index % colors.length],
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _ScoreConfettiPainter(
                progress: _controller.value,
                pieces: _pieces,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _ConfettiPiece {
  final double startX;
  final double delay;
  final double drift;
  final double fall;
  final double size;
  final double spin;
  final Color color;

  const _ConfettiPiece({
    required this.startX,
    required this.delay,
    required this.drift,
    required this.fall,
    required this.size,
    required this.spin,
    required this.color,
  });
}

class _ScoreConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiPiece> pieces;

  const _ScoreConfettiPainter({required this.progress, required this.pieces});

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final localT = ((progress - piece.delay) / (1 - piece.delay))
          .clamp(0.0, 1.0)
          .toDouble();
      if (localT <= 0 || localT >= 1) continue;
      final eased = Curves.easeOutCubic.transform(localT);
      final fade = (1 - Curves.easeIn.transform(localT))
          .clamp(0.0, 1.0)
          .toDouble();
      final x =
          piece.startX * size.width + piece.drift * math.sin(localT * math.pi);
      final y = -24 + size.height * piece.fall * eased;
      final paint = Paint()..color = piece.color.withValues(alpha: fade);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.spin + localT * math.pi * 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.size,
            height: piece.size * 1.8,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ScoreConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.pieces != pieces;
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

class _HabitChipGrid extends StatelessWidget {
  final List<Habit> habits;
  final Map<String, bool> completedByHabitId;
  final ValueChanged<Habit> onToggle;

  const _HabitChipGrid({
    required this.habits,
    required this.completedByHabitId,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 360 ? 2 : 3;
        const spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final habit in habits)
              SizedBox(
                width: itemWidth,
                child: DashboardHabitCard(
                  habit: habit,
                  completed: completedByHabitId[habit.id] ?? false,
                  onToggle: () => onToggle(habit),
                ),
              ),
          ],
        );
      },
    );
  }
}
