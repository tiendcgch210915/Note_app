import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../theme/app_colors.dart';

class HabitCard extends StatelessWidget {
  final Habit habit;
  final VoidCallback? onTap;
  final int recentCompletions; // số ngày completed trong 7 ngày qua

  const HabitCard({
    super.key,
    required this.habit,
    this.onTap,
    this.recentCompletions = 5,
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
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final progress = (recentCompletions / 7).clamp(0.0, 1.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_fire_department,
                  size: 16,
                  color: AppColors.streakGold,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    '${habit.currentStreak}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'ngày',
                    style: TextStyle(fontSize: 10, color: textSecondary),
                  ),
                ),
                const Spacer(),
                if (habit.icon != null)
                  Icon(habit.icon, size: 16, color: habit.color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              habit.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              habit.frequencyLabel,
              style: TextStyle(fontSize: 10, color: textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: isDark
                    ? AppColors.dividerDark
                    : AppColors.divider,
                valueColor: AlwaysStoppedAnimation(habit.color),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Kỷ lục: ${habit.longestStreak}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
