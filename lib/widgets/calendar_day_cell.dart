import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/date_utils.dart';

/// Ô lịch hiển thị 1 ngày, dùng cho CalendarScreen.
/// Quá khứ (hoặc hôm nay) → hiện score 0..100. Tương lai → hiện số todo.
class CalendarDayCell extends StatelessWidget {
  final DateTime date;
  final int? score; // 0..100 nếu past/today
  final int? todoCount; // nếu future
  final bool isToday;
  final VoidCallback? onTap;

  const CalendarDayCell({
    super.key,
    required this.date,
    this.score,
    this.todoCount,
    this.isToday = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;
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
            Text(
              AppDateUtils.weekdayShort(date.weekday),
              style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500),
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
            if (score != null) ...[
              Text(
                '$score/100',
                style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (score! / 100).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: divider,
                  valueColor: AlwaysStoppedAnimation(primary),
                ),
              ),
            ] else if (todoCount != null) ...[
              Text(
                '$todoCount việc',
                style: TextStyle(fontSize: 14, color: textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
