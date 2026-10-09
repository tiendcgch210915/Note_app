import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'pressable.dart';

/// Hàng 7 nút tròn chọn thứ trong tuần (1 = Thứ Hai … 7 = Chủ nhật).
/// Mỗi nút luôn ≥ 36px và thu nhỏ vừa chiều rộng khả dụng.
class WeekdayPicker extends StatelessWidget {
  static const _labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  const WeekdayPicker({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final size = math.min(44.0, (constraints.maxWidth - gap * 6) / 7);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 7; i++)
              _DayButton(
                label: _labels[i],
                size: size,
                selected: selected.contains(i + 1),
                onTap: () => onToggle(i + 1),
              ),
          ],
        );
      },
    );
  }
}

class _DayButton extends StatelessWidget {
  final String label;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  const _DayButton({
    required this.label,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected
                ? AppColors.accentFill
                : context.appTextSecondary.withValues(alpha: 0.12),
            shape: const CircleBorder(),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : context.appTextPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
