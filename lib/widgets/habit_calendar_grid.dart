import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/date_utils.dart';
import 'app_surface.dart';
import 'clamp_text_scale.dart';

/// Cỡ chữ hệ thống tối đa mà ô lưới cố định chiều cao có thể chứa được.
const double _maxTextScale = 1.3;

/// Lịch 28 ngày của một thói quen: 4 tuần × 7 ngày, bắt đầu từ thứ Hai của
/// 2 tuần trước (hoặc ngày bắt đầu thói quen nếu muộn hơn). Ô có lửa đỏ =
/// hoàn thành, lửa xanh = đã ghi nhận nhưng chưa làm, ô trống = chưa ghi nhận.
///
/// [completedByDate] ánh xạ ngày (chỉ phần ngày) -> đã hoàn thành hay chưa;
/// ngày vắng mặt nghĩa là chưa ghi nhận. Nếu [onLongPress] là `null` lịch chỉ
/// để xem (không nhấn giữ để sửa).
class HabitCalendarGrid extends StatelessWidget {
  final Habit habit;
  final Map<DateTime, bool> completedByDate;
  final DateTime today;
  final ValueChanged<DateTime>? onLongPress;
  final EdgeInsetsGeometry margin;

  /// Màu nền thẻ chứa lịch; mặc định là màu thẻ của app.
  final Color? surfaceColor;
  final bool showShadow;

  const HabitCalendarGrid({
    super.key,
    required this.habit,
    required this.completedByDate,
    required this.today,
    this.onLongPress,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.surfaceColor,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = context.appTextSecondary;
    final todayOnly = AppDateUtils.dateOnly(today);
    final habitStart = AppDateUtils.dateOnly(habit.startDate);
    final todayWeekStart = todayOnly.subtract(
      Duration(days: todayOnly.weekday - DateTime.monday),
    );
    final defaultGridStart = todayWeekStart.subtract(const Duration(days: 14));
    final gridStart = habitStart.isAfter(defaultGridStart)
        ? habitStart
        : defaultGridStart;
    // Chiều cao ô co giãn theo cỡ chữ hệ thống để nội dung không bị tràn.
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, _maxTextScale);

    return Padding(
      padding: margin,
      child: AppSurface(
        color: surfaceColor,
        showShadow: showShadow,
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
        child: Column(
          children: [
            Row(
              children: List.generate(7, (index) {
                final weekday = ((gridStart.weekday - 1 + index) % 7) + 1;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Center(
                      child: Text(
                        AppDateUtils.weekdayShort(weekday),
                        style: TextStyle(
                          fontSize: 11,
                          color: secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            GridView.builder(
              itemCount: 28,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                mainAxisExtent: 62 * scale,
              ),
              itemBuilder: (context, index) {
                final date = gridStart.add(Duration(days: index));
                return ClampTextScale(
                  maxScale: _maxTextScale,
                  child: _CalendarCell(
                    date: date,
                    completed: completedByDate[date],
                    accent: habit.color,
                    isToday: AppDateUtils.isSameDay(date, today),
                    isFuture: date.isAfter(todayOnly),
                    onLongPress: onLongPress == null
                        ? null
                        : () => onLongPress!(date),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  final DateTime date;
  final bool? completed;
  final Color accent;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onLongPress;

  const _CalendarCell({
    required this.date,
    required this.completed,
    required this.accent,
    required this.isToday,
    required this.isFuture,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = context.appTextSecondary;
    final recorded = completed != null;
    final done = completed == true;
    final labelColor = isToday ? accent : secondary;
    final status = !recorded
        ? 'chưa ghi nhận'
        : done
        ? 'đã hoàn thành'
        : 'chưa làm';
    final background = done
        ? accent.withValues(alpha: 0.14)
        : isToday
        ? accent.withValues(alpha: 0.08)
        : secondary.withValues(alpha: 0.07);

    return Semantics(
      button: onLongPress != null,
      label:
          'Ngày ${date.day}/${date.month}, $status'
          '${onLongPress != null ? '. Nhấn giữ để sửa' : ''}',
      child: Opacity(
        opacity: isFuture ? 0.4 : 1,
        child: GestureDetector(
          onLongPress: onLongPress,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            decoration: ShapeDecoration(
              color: background,
              shape: AppShape.squircle(
                AppRadius.xs,
                side: isToday
                    ? BorderSide(color: accent, width: 1.6)
                    : BorderSide.none,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final flame = (constraints.maxWidth - 6).clamp(18.0, 28.0);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 30,
                      child: Center(
                        child: !recorded
                            ? const SizedBox.shrink()
                            : _FlameIcon(completed: done, size: flame),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${date.day}/${date.month}',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1,
                        color: labelColor,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FlameIcon extends StatelessWidget {
  final bool completed;
  final double size;

  const _FlameIcon({required this.completed, required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FlamePainter(completed: completed),
    );
  }
}

class _FlamePainter extends CustomPainter {
  final bool completed;

  const _FlamePainter({required this.completed});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outerPath = Path()
      ..moveTo(w * 0.58, h * 0.02)
      ..cubicTo(w * 0.34, h * 0.19, w * 0.43, h * 0.37, w * 0.36, h * 0.49)
      ..cubicTo(w * 0.28, h * 0.39, w * 0.28, h * 0.29, w * 0.18, h * 0.22)
      ..cubicTo(w * 0.21, h * 0.41, w * 0.08, h * 0.50, w * 0.08, h * 0.68)
      ..cubicTo(w * 0.08, h * 0.88, w * 0.27, h * 0.99, w * 0.46, h * 0.98)
      ..cubicTo(w * 0.34, h * 0.89, w * 0.39, h * 0.74, w * 0.49, h * 0.64)
      ..cubicTo(w * 0.54, h * 0.76, w * 0.67, h * 0.83, w * 0.58, h * 0.98)
      ..cubicTo(w * 0.78, h * 0.94, w * 0.93, h * 0.79, w * 0.90, h * 0.59)
      ..cubicTo(w * 0.88, h * 0.42, w * 0.76, h * 0.32, w * 0.78, h * 0.18)
      ..cubicTo(w * 0.66, h * 0.25, w * 0.65, h * 0.38, w * 0.58, h * 0.02)
      ..close();

    final outerColors = completed
        ? const [Color(0xFFFF2D14), Color(0xFFFF7A18), Color(0xFFFFE45C)]
        : const [Color(0xFF0B6DFF), Color(0xFF1688FF), Color(0xFF74D2FF)];
    final outerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: outerColors,
      ).createShader(Offset.zero & size);
    canvas.drawPath(outerPath, outerPaint);

    final innerPath = Path()
      ..moveTo(w * 0.50, h * 0.96)
      ..cubicTo(w * 0.33, h * 0.86, w * 0.39, h * 0.70, w * 0.50, h * 0.59)
      ..cubicTo(w * 0.57, h * 0.71, w * 0.72, h * 0.79, w * 0.62, h * 0.96)
      ..cubicTo(w * 0.58, h * 0.99, w * 0.53, h * 0.99, w * 0.50, h * 0.96)
      ..close();
    final innerColors = completed
        ? const [Color(0xFFFFFFFF), Color(0xFFFFF46A), Color(0xFFFFB23F)]
        : const [Color(0xFFE8F7FF), Color(0xFF7DDCFF), Color(0xFF1E9BFF)];
    final innerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: innerColors,
      ).createShader(Offset.zero & size);
    canvas.drawPath(innerPath, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _FlamePainter oldDelegate) {
    return oldDelegate.completed != completed;
  }
}
