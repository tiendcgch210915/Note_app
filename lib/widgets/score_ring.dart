import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Vòng tròn điểm dashboard. Progress được cap ở 100 để giữ UI ổn định,
/// nhưng số điểm hiển thị luôn là điểm thật so với mốc mục tiêu 100.
class ScoreRing extends StatelessWidget {
  final int score;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? backgroundColor;
  final bool showLabel;

  const ScoreRing({
    super.key,
    required this.score,
    this.size = 112,
    this.strokeWidth = 8,
    this.color,
    this.backgroundColor,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ringColor =
        color ?? (isDark ? AppColors.primaryDark : AppColors.primary);
    final bgColor =
        backgroundColor ?? (isDark ? AppColors.dividerDark : AppColors.divider);
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final displayScore = math.max(0, score);
    final exceptional = displayScore > 100;
    final progress = math.min(displayScore, 100) / 100;
    final effectiveRingColor =
        color ?? (exceptional ? AppColors.warning : ringColor);
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(
              progress: progress,
              color: effectiveRingColor,
              backgroundColor: bgColor,
              strokeWidth: strokeWidth,
              overachieved: exceptional,
            ),
          ),
          if (showLabel)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size * 0.72,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$displayScore',
                      style: TextStyle(
                        fontSize: size * 0.34,
                        fontWeight: FontWeight.w800,
                        color: exceptional ? AppColors.warning : textColor,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
                Text(
                  '/100',
                  style: TextStyle(
                    fontSize: 12,
                    color: exceptional ? AppColors.warning : secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;
  final bool overachieved;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
    required this.overachieved,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, bgPaint);

    if (overachieved) {
      final haloPaint = Paint()
        ..color = color.withValues(alpha: 0.14)
        ..strokeWidth = strokeWidth * 1.75
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, radius, haloPaint);
    }

    if (progress <= 0) return;
    final fgPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Bắt đầu từ 12h (-π/2), quét theo chiều kim đồng hồ.
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.backgroundColor != backgroundColor ||
      old.strokeWidth != strokeWidth ||
      old.overachieved != overachieved;
}
