import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'pressable.dart';

class TodoFlagButton extends StatelessWidget {
  final bool selected;
  final Color selectedColor;
  final Color? selectedForeground;
  final String label;
  final IconData? icon;
  final String? emoji;
  final VoidCallback? onTap;

  const TodoFlagButton({
    super.key,
    required this.selected,
    required this.selectedColor,
    this.selectedForeground,
    required this.label,
    this.icon,
    this.emoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = context.appTextSecondary;
    final idleBackground = secondary.withValues(alpha: 0.12);
    final foreground = selected
        ? (selectedForeground ?? Colors.white)
        : secondary;
    final enabled = onTap != null;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.62,
        child: Pressable(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null
                ? null
                : () {
                    AppHaptics.selection();
                    onTap!();
                  },
            child: AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              decoration: ShapeDecoration(
                color: selected ? selectedColor : idleBackground,
                shape: AppShape.squircle(AppRadius.sm),
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  // Ô vuông có kích thước cố định: chữ hệ thống lớn / màn hẹp
                  // thì thu nhỏ cả khối thay vì tràn đáy.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (emoji != null)
                          AnimatedOpacity(
                            duration: AppMotion.normal,
                            opacity: selected ? 1 : 0.35,
                            child: Text(
                              emoji!,
                              style: const TextStyle(fontSize: 32, height: 1),
                            ),
                          )
                        else
                          Icon(icon, size: 32, color: foreground),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
