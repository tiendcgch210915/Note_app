import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'pressable.dart';

class DashboardHabitCard extends StatelessWidget {
  final Habit habit;
  final bool completed;

  /// Chạm vào thẻ: mở bảng xác nhận hoàn thành / bỏ lỡ (không tự tick).
  final VoidCallback onTap;

  const DashboardHabitCard({
    super.key,
    required this.habit,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = context.appTextPrimary;
    final textSecondary = context.appTextSecondary;
    final streak = habit.currentStreak;
    final longest = habit.longestStreak;

    return Pressable(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          padding: const EdgeInsets.all(12),
          decoration: ShapeDecoration(
            color: context.appSurface,
            shape: AppShape.squircle(
              AppRadius.lg,
              side: BorderSide(
                color: completed
                    ? habit.color.withValues(alpha: 0.5)
                    : context.appDivider.withValues(alpha: 0.8),
                width: completed ? 1.2 : 0.8,
              ),
            ),
            shadows: AppShadows.card(context.isDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(habit.icon ?? Icons.flag, size: 18, color: habit.color),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: AppMotion.normal,
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      completed
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      key: ValueKey(completed),
                      size: 22,
                      color: completed ? habit.color : textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                habit.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _StreakBadge(currentStreak: streak),
              const SizedBox(height: 5),
              Text(
                'Kỷ lục: $longest ngày',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  final int currentStreak;

  const _StreakBadge({required this.currentStreak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: AppColors.streakGold.withValues(alpha: 0.14),
        shape: AppShape.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            size: 14,
            color: AppColors.streakGold,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '$currentStreak ngày',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.streakGold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
