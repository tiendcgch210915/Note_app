import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../theme/app_colors.dart';

class DashboardHabitCard extends StatelessWidget {
  final Habit habit;
  final bool completed;
  final VoidCallback onToggle;

  const DashboardHabitCard({
    super.key,
    required this.habit,
    required this.completed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final streak = habit.currentStreak;
    final longest = habit.longestStreak;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: completed
                ? habit.color.withValues(alpha: 0.36)
                : Colors.transparent,
          ),
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
                  color: completed ? habit.color : textSecondary,
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
                fontSize: 10,
                color: textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.streakGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department,
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
