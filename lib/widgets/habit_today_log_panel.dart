import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'pressable.dart';

/// Câu hỏi "Đã hoàn thành hôm nay chưa?" kèm hai nút "Hoàn thành" / "Bỏ lỡ".
///
/// Dùng chung cho trang chi tiết thói quen và bảng xác nhận ở Dashboard.
/// [completed] là trạng thái đã ghi nhận hôm nay (`null` = chưa ghi nhận).
class HabitTodayLogPanel extends StatelessWidget {
  final bool? completed;

  /// Khi `true` hai nút bị vô hiệu hoá (đang lưu).
  final bool busy;
  final ValueChanged<bool> onLog;

  const HabitTodayLogPanel({
    super.key,
    required this.completed,
    required this.onLog,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          completed == null
              ? 'Đã hoàn thành hôm nay chưa?'
              : completed!
              ? 'Bạn đã hoàn thành hôm nay'
              : 'Bạn đã đánh dấu bỏ lỡ hôm nay',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: HabitLogButton(
                label: 'Hoàn thành',
                icon: Icons.check_rounded,
                color: AppColors.success,
                selected: completed == true,
                onPressed: busy ? null : () => onLog(true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HabitLogButton(
                label: 'Bỏ lỡ',
                icon: Icons.close_rounded,
                color: AppColors.danger,
                selected: completed == false,
                onPressed: busy ? null : () => onLog(false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Nút tô màu (xanh "Hoàn thành" / đỏ "Bỏ lỡ") của [HabitTodayLogPanel].
class HabitLogButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onPressed;

  const HabitLogButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = selected ? Colors.white : color;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Pressable(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  AppHaptics.medium();
                  onPressed!();
                }
              : null,
          child: AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: selected ? color : color.withValues(alpha: 0.12),
              shape: AppShape.squircle(
                AppRadius.md,
                side: BorderSide(
                  color: selected ? color : color.withValues(alpha: 0.4),
                ),
              ),
            ),
            // Nhãn dài / chữ hệ thống lớn: thu nhỏ vừa nút thay vì tràn ngang.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 15,
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
    );
  }
}
