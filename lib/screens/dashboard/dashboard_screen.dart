import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/dashboard_repository.dart';
import '../../data/habits_repository.dart';
import '../../models/dashboard.dart';
import '../../models/habit.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_snack.dart';
import '../../utils/dashboard_habit_visibility.dart';
import '../../utils/dashboard_local_events.dart';
import '../../utils/date_utils.dart';
import '../../utils/habit_streak_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/dashboard_habit_card.dart';
import '../../widgets/eisenhower_grid.dart';
import '../../widgets/habit_log_sheet.dart';
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
      if (mounted) showAppSnack(context, e.vnMessage, isError: true);
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Không tải được dashboard', isError: true);
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
        content: Text(
          'Trên cả tuyệt vời',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
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

  /// Chạm vào một thói quen: KHÔNG tick ngay mà mở bảng xác nhận (lịch 28 ngày +
  /// "Hoàn thành" / "Bỏ lỡ") để tránh bấm nhầm. Chỉ ghi log khi người dùng chọn.
  Future<void> _openHabitLog(Habit habit) async {
    final completedByDate = <DateTime, bool>{
      for (final entry in _todayCal.entries)
        if (entry.value.containsKey(habit.id))
          AppDateUtils.dateOnly(entry.key): entry.value[habit.id]!,
    };
    final completed = await showHabitLogSheet(
      context,
      habit: habit,
      completedByDate: completedByDate,
    );
    if (completed == null || !mounted) return;
    await _logHabit(habit, completed);
  }

  /// Đặt trạng thái hôm nay của [habitId] trong bản đồ lịch (null = xoá log).
  /// Phải gọi trong `setState`.
  void _putTodayLog(DateTime day, String habitId, bool? completed) {
    final dayMap = Map<String, bool>.from(_todayCal[day] ?? const {});
    if (completed == null) {
      dayMap.remove(habitId);
    } else {
      dayMap[habitId] = completed;
    }
    _todayCal = {..._todayCal, day: dayMap};
  }

  Future<void> _logHabit(Habit habit, bool completed) async {
    final today = AppDateUtils.dateOnly(DateTime.now());
    final previous = _todayCal[today]?[habit.id];
    // Số thói quen hoàn thành chỉ đổi khi trạng thái "hoàn thành" thay đổi.
    final delta = (completed ? 1 : 0) - (previous == true ? 1 : 0);
    setState(() {
      _putTodayLog(today, habit.id, completed);
      if (delta != 0) _snapshot = _snapshotWithHabitCompletion(delta);
    });
    try {
      final result = await HabitsRepository.instance.logHabit(
        habit.id,
        logDate: today,
        completed: completed,
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
          _putTodayLog(today, habit.id, previous);
          if (delta != 0) _snapshot = _snapshotWithHabitCompletion(-delta);
        });
        showAppSnack(context, e.vnMessage, isError: true);
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
      return const AppSpinner();
    }
    if (_snapshot == null) {
      return AppErrorState(
        message: 'Không tải được dashboard',
        onRetry: _refresh,
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
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
            child: Text(
              AppDateUtils.formatDashboardTitle(snap.date),
              style: Theme.of(context).textTheme.titleLarge,
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
          if (remainingHabits.isNotEmpty) ...[
            SectionHeader(
              label:
                  'Bạn còn ${remainingHabits.length} thói quen cho ngày hôm nay',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _HabitChipGrid(
                habits: remainingHabits,
                completedByHabitId: _todayCal[today] ?? const {},
                onHabitTap: _openHabitLog,
              ),
            ),
          ] else if (_habits.isNotEmpty) ...[
            const SectionHeader(label: 'Thói quen hôm nay'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _AllHabitsDoneTile(),
            ),
          ],
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
    final isDark = context.isDark;
    final exceptional = snapshot.score > 100;
    final belowMinimumGate =
        snapshot.score == 0 &&
        (snapshot.todosTotal < 3 || snapshot.todosDone < 3);
    final bg = exceptional
        ? AppColors.warning.withValues(alpha: isDark ? 0.18 : 0.12)
        : context.appPrimarySoft;
    final borderColor = exceptional
        ? AppColors.warning.withValues(alpha: 0.75)
        : Colors.transparent;
    // Chữ huy hiệu "vượt mốc": vàng đậm hơn ở light mode để đủ tương phản.
    final badgeText = isDark ? AppColors.warning : const Color(0xFFB45309);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: ShapeDecoration(
          color: bg,
          shape: AppShape.squircle(
            AppRadius.xl,
            side: BorderSide(color: borderColor, width: exceptional ? 1.4 : 0),
          ),
          shadows: exceptional
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
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: ShapeDecoration(
                        color: AppColors.warning.withValues(alpha: 0.2),
                        shape: AppShape.pill,
                      ),
                      child: Text(
                        '+${snapshot.score - 100} vượt mốc',
                        style: TextStyle(
                          fontSize: 12,
                          color: badgeText,
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
                      color: context.appTextSecondary,
                    ),
                  ),
                  if (belowMinimumGate) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Cần ít nhất 3 việc hoàn thành để tính điểm',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appTextSecondary,
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
    final statusColor = frog.isDone ? AppColors.success : context.appPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppSurface(
        clipBehavior: Clip.antiAlias,
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TodoDetailScreen(todoId: frog.id),
            ),
          );
          onRefresh();
        },
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: AppColors.frog),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.eco_rounded, color: AppColors.frog, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'ƯU TIÊN HÔM NAY',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
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
                      letterSpacing: -0.2,
                      decoration: frog.isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: ShapeDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      shape: AppShape.pill,
                    ),
                    child: Text(
                      frog.isDone ? 'Hoàn thành' : 'Mở',
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
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
}

class _HabitChipGrid extends StatelessWidget {
  final List<Habit> habits;
  final Map<String, bool> completedByHabitId;
  final ValueChanged<Habit> onHabitTap;

  const _HabitChipGrid({
    required this.habits,
    required this.completedByHabitId,
    required this.onHabitTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 360 ? 2 : 3;
        const spacing = 8.0;
        // Mỗi hàng cao bằng thẻ cao nhất (tên 1 dòng / 2 dòng không còn lệch).
        final rows = <Widget>[];
        for (var start = 0; start < habits.length; start += columns) {
          final slice = habits.skip(start).take(columns).toList();
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) const SizedBox(width: spacing),
                    Expanded(
                      child: i < slice.length
                          ? DashboardHabitCard(
                              habit: slice[i],
                              completed:
                                  completedByHabitId[slice[i].id] ?? false,
                              onTap: () => onHabitTap(slice[i]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: spacing),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// Hiện khi người dùng đã hoàn thành mọi thói quen trong ngày.
class _AllHabitsDoneTile extends StatelessWidget {
  const _AllHabitsDoneTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: context.appSuccessSoft,
        shape: AppShape.squircle(AppRadius.lg),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Bạn đã hoàn thành tất cả thói quen hôm nay',
              style: TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
