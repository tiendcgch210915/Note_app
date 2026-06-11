import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class TodoFlagButton extends StatelessWidget {
  final bool selected;
  final Color selectedColor;
  final Color? selectedForeground;
  final String label;
  final IconData? icon;
  final String? emoji;
  final VoidCallback onTap;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabledBackground = isDark
        ? AppColors.dividerDark
        : const Color(0xFFF3F4F6);
    final disabledForeground = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final foreground = selected
        ? (selectedForeground ?? Colors.white)
        : disabledForeground;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? selectedColor : disabledBackground,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 1,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (emoji != null)
                    Opacity(
                      opacity: selected ? 1 : 0.35,
                      child: Text(
                        emoji!,
                        style: const TextStyle(fontSize: 32, height: 1),
                      ),
                    )
                  else
                    Icon(icon, size: 32, color: foreground),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
