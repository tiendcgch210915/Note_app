import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';

class AppSegment<T extends Object> {
  final T value;
  final String label;
  final IconData? icon;

  const AppSegment({required this.value, required this.label, this.icon});
}

/// Thanh phân đoạn kiểu iOS (thumb trượt). Thay cho [SegmentedButton].
class AppSegmentedControl<T extends Object> extends StatelessWidget {
  final List<AppSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final background = isDark
        ? const Color(0xFF2A2B31)
        : const Color(0xFFE9EAF0);
    final thumb = isDark ? const Color(0xFF4A4B54) : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final n = segments.length;
        // Chia đều chiều rộng (control mặc định co theo nội dung).
        final childWidth = constraints.hasBoundedWidth && n > 0
            ? ((constraints.maxWidth - 4 - (n - 1)) / n).floorToDouble()
            : null;

        return CupertinoSlidingSegmentedControl<T>(
          groupValue: value,
          thumbColor: thumb,
          backgroundColor: background,
          onValueChanged: (v) {
            if (v == null || v == value) return;
            AppHaptics.selection();
            onChanged(v);
          },
          children: {
            for (final s in segments)
              s.value: SizedBox(
                width: childWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (s.icon != null) ...[
                        Icon(
                          s.icon,
                          size: 16,
                          color: s.value == value
                              ? context.appTextPrimary
                              : context.appTextSecondary,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: s.value == value
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: s.value == value
                                ? context.appTextPrimary
                                : context.appTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          },
        );
      },
    );
  }
}
