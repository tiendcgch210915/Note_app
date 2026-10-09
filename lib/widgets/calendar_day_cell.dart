import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import '../utils/date_utils.dart';
import 'pressable.dart';

/// Ô lịch hiển thị 1 ngày, dùng cho CalendarScreen.
class CalendarDayCell extends StatelessWidget {
  final DateTime date;
  final bool isFuture;
  final int? score; // null nếu future; điểm có thể vượt 100
  final int totalTodos;
  final int doneTodos;
  final int habitsTotal;
  final int habitsCompleted;
  final bool isToday;
  final VoidCallback? onTap;

  const CalendarDayCell({
    super.key,
    required this.date,
    required this.isFuture,
    this.score,
    this.totalTodos = 0,
    this.doneTodos = 0,
    this.habitsTotal = 0,
    this.habitsCompleted = 0,
    this.isToday = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final textPrimary = context.appTextPrimary;
    final textSecondary = context.appTextSecondary;
    final cardColor = context.appSurface;
    final primary = context.appPrimary;
    final scoreEligible = totalTodos >= 3 && doneTodos >= 3;
    final dayScore = score == null ? null : (scoreEligible ? score : 0);
    final exceptional = !isFuture && dayScore != null && dayScore >= 100;
    final effectiveTextPrimary = exceptional ? Colors.white : textPrimary;
    final effectiveTextSecondary = exceptional
        ? const Color(0xFFFFE8C2)
        : textSecondary;
    final borderColor = exceptional
        ? const Color(0xFFFFC107)
        : (isToday ? primary : null);

    return Pressable(
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                AppHaptics.selection();
                onTap!();
              },
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: exceptional ? 0.82 : 1, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, glow, _) {
            return Container(
              padding: const EdgeInsets.all(12),
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: exceptional ? null : cardColor,
                gradient: exceptional
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF7F1D1D),
                          Color(0xFFEA580C),
                          Color(0xFFF59E0B),
                        ],
                      )
                    : null,
                shape: AppShape.squircle(
                  AppRadius.lg,
                  side: borderColor == null
                      ? BorderSide(
                          color: context.appDivider.withValues(alpha: 0.8),
                          width: 0.8,
                        )
                      : BorderSide(
                          color: borderColor,
                          width: exceptional ? 1.8 : 1.5,
                        ),
                ),
                shadows: exceptional
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFFF97316,
                          ).withValues(alpha: 0.22 * glow),
                          blurRadius: 18 * glow,
                          spreadRadius: 1.5 * glow,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: const Color(
                            0xFFFACC15,
                          ).withValues(alpha: 0.12 * glow),
                          blurRadius: 28 * glow,
                          spreadRadius: 2 * glow,
                        ),
                      ]
                    : AppShadows.card(isDark),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (exceptional)
                    Positioned(
                      right: -8,
                      bottom: -10,
                      child: Transform.scale(
                        scale: 0.94 + (0.06 * glow),
                        child: Icon(
                          Icons.local_fire_department_rounded,
                          size: 58,
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              AppDateUtils.weekdayShort(date.weekday),
                              style: TextStyle(
                                fontSize: 11,
                                color: effectiveTextSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!isFuture && dayScore != null)
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: _ScoreBadge(
                                  score: dayScore,
                                  exceptional: exceptional,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Thu nhỏ số ngày khi ô hẹp (kèm chip lửa) thay vì tràn ngang.
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: effectiveTextPrimary,
                                  height: 1,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                          if (exceptional) ...[
                            const SizedBox(width: 6),
                            Container(
                              key: const ValueKey('calendar-fire-streak-chip'),
                              width: 24,
                              height: 24,
                              decoration: ShapeDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                shape: CircleBorder(
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.22),
                                  ),
                                ),
                              ),
                              child: const Icon(
                                Icons.local_fire_department_rounded,
                                size: 15,
                                color: Color(0xFFFFF7AD),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      if (isFuture) ...[
                        _MetricLine(
                          label: '$totalTodos todos',
                          color: effectiveTextSecondary,
                        ),
                        const SizedBox(height: 3),
                        _MetricLine(
                          label: '$habitsTotal habits',
                          color: effectiveTextSecondary,
                        ),
                      ] else ...[
                        _MetricLine(
                          label: '$doneTodos/$totalTodos todos',
                          color: effectiveTextSecondary,
                        ),
                        const SizedBox(height: 3),
                        _MetricLine(
                          label: '$habitsCompleted/$habitsTotal habits',
                          color: effectiveTextSecondary,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;
  final bool exceptional;

  const _ScoreBadge({required this.score, required this.exceptional});

  /// Thang màu theo điểm: tốt -> xanh, trung bình -> vàng, thấp -> đỏ.
  static Color _colorFor(int score) {
    if (score >= 70) return AppColors.success;
    if (score >= 40) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    if (!exceptional) {
      return Text(
        '$score',
        style: TextStyle(
          fontSize: 16,
          color: _colorFor(score),
          fontWeight: FontWeight.w800,
          height: 1,
          letterSpacing: 0,
        ),
      );
    }

    return Container(
      key: const ValueKey('calendar-fire-score-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: ShapeDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: AppShape.squircle(
          AppRadius.xs,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            key: ValueKey('calendar-fire-score-icon'),
            size: 13,
            color: Color(0xFFFFF176),
          ),
          const SizedBox(width: 2),
          Text(
            '$score',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  final String label;
  final Color color;

  const _MetricLine({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        height: 1.1,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
