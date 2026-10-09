import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'pressable.dart';

/// Thẻ nền squircle dùng chung: viền chân tóc + bóng rất nhẹ (chỉ light mode).
///
/// Khi có [onTap]/[onLongPress], thẻ tự có hiệu ứng nhấn ([Pressable]) — thay
/// cho `InkWell` bọc `Container` đặc (ripple bị che mất).
class AppSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final bool showBorder;
  final bool showShadow;
  final Clip clipBehavior;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AppSurface({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppRadius.lg,
    this.color,
    this.borderColor,
    this.showBorder = true,
    this.showShadow = true,
    this.clipBehavior = Clip.none,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final side = showBorder
        ? BorderSide(
            color:
                borderColor ??
                context.appDivider.withValues(alpha: isDark ? 1 : 0.8),
            width: 0.8,
          )
        : BorderSide.none;

    Widget content = Container(
      padding: padding,
      clipBehavior: clipBehavior,
      decoration: ShapeDecoration(
        color: color ?? context.appSurface,
        shape: AppShape.squircle(radius, side: side),
        shadows: showShadow ? AppShadows.card(isDark) : null,
      ),
      child: child,
    );

    if (onTap == null && onLongPress == null) return content;

    content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: content,
    );
    return Pressable(child: content);
  }
}
