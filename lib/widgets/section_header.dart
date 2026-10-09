import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Tiêu đề section uppercase 12sp kiểu iOS (letterSpacing nhẹ).
class SectionHeader extends StatelessWidget {
  final String label;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.label,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 16, 8),
  });

  /// Chấm màu nhỏ đặt trước nhãn (thay cho emoji).
  static Widget dot(Color color) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  @override
  Widget build(BuildContext context) {
    final color = context.appTextSecondary;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTextStyles.sectionLabel.copyWith(color: color),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
