import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'app_surface.dart';

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
    final textPrimary = context.appTextPrimary;
    final textSecondary = context.appTextSecondary;
    final progress = (recentCompletions / 7).clamp(0.0, 1.0);

    return AppSurface(
      onTap: onTap,
      radius: AppRadius.lg,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dòng streak chiếm trọn chiều rộng ô (icon của thói quen đã chuyển
          // xuống chân thẻ) để "🔥 12 ngày" hiển thị đủ cỡ; chỉ thu nhỏ nhẹ khi
          // streak 3-4 chữ số hoặc màn hình rất hẹp.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 16,
                  color: AppColors.streakGold,
                ),
                const SizedBox(width: 3),
                Text(
                  '${habit.currentStreak}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'ngày',
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ),
              ],
            ),
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
            style: TextStyle(fontSize: 11, color: textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: context.appDivider,
              valueColor: AlwaysStoppedAnimation(habit.color),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kỷ lục: ${habit.longestStreak}',
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ),
              ),
              if (habit.icon != null) ...[
                const SizedBox(width: 6),
                Icon(habit.icon, size: 16, color: habit.color),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
