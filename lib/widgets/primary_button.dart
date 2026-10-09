import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'pressable.dart';

enum PrimaryButtonVariant {
  /// Nút điền màu chủ đạo.
  primary,

  /// Nút điền nhạt (tonal) — hành động phụ.
  tonal,

  /// Nút điền đỏ — hành động nguy hiểm.
  destructive,

  /// Nút chỉ có chữ.
  text,
}

/// Nút chính: cao 50, bo squircle, hiệu ứng nhấn + haptic nhẹ.
/// Giữ API cũ (`label`, `icon`, `onPressed`, `loading`, `fullWidth`).
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;
  final PrimaryButtonVariant variant;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.fullWidth = true,
    this.variant = PrimaryButtonVariant.primary,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final (bg, fg) = switch (variant) {
      PrimaryButtonVariant.primary => (AppColors.accentFill, Colors.white),
      PrimaryButtonVariant.tonal => (
        context.appPrimarySoft,
        context.appPrimary,
      ),
      PrimaryButtonVariant.destructive => (AppColors.danger, Colors.white),
      PrimaryButtonVariant.text => (Colors.transparent, context.appPrimary),
    };
    final secondary = context.appTextSecondary;
    final disabledBg = variant == PrimaryButtonVariant.text
        ? Colors.transparent
        : secondary.withValues(alpha: 0.16);

    final content = AnimatedSwitcher(
      duration: AppMotion.fast,
      child: loading
          ? SizedBox(
              key: const ValueKey('primary-button-loading'),
              width: 22,
              height: 22,
              child: CupertinoActivityIndicator(color: fg, radius: 10),
            )
          : Row(
              key: const ValueKey('primary-button-label'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );

    final button = FilledButton(
      // Khi đang loading vẫn giữ màu "active" nhưng nuốt thao tác chạm.
      onPressed: onPressed == null
          ? null
          : loading
          ? () {}
          : () {
              AppHaptics.light();
              onPressed!();
            },
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: disabledBg,
        disabledForegroundColor: secondary.withValues(alpha: 0.6),
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        elevation: 0,
        shape: AppShape.squircle(AppRadius.md),
      ),
      child: content,
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 50,
      child: Pressable(enabled: enabled, child: button),
    );
  }
}
