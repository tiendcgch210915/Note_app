import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/date_utils.dart';

/// Ô lịch hiển thị 1 ngày, dùng cho CalendarScreen.
class CalendarDayCell extends StatelessWidget {
  final DateTime date;
  final bool isFuture;
  final int? score; // 0..100 nếu past/today
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: isToday ? Border.all(color: primary, width: 1.5) : null,
        ),
        child: Column(
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
                      color: textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (!isFuture && score != null)
                  Text(
                    '${score!.clamp(0, 100)}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.danger,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: textPrimary,
                height: 1,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            if (isFuture) ...[
              _MetricLine(label: '$totalTodos todos', color: textSecondary),
              const SizedBox(height: 3),
              _MetricLine(label: '$habitsTotal habits', color: textSecondary),
            ] else ...[
              _MetricLine(
                label: '$doneTodos/$totalTodos todos',
                color: textSecondary,
              ),
              const SizedBox(height: 3),
              _MetricLine(
                label: '$habitsCompleted/$habitsTotal habits',
                color: textSecondary,
              ),
            ],
          ],
        ),
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
