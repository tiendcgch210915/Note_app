import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'primary_button.dart';

/// Trạng thái rỗng: biểu tượng trong ô squircle, tiêu đề, mô tả và nút tuỳ chọn.
/// Hiện dần khi xuất hiện (animation hữu hạn).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.buttonLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = context.appTextSecondary;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.slow,
        curve: AppMotion.curve,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: child,
          ),
        ),
        // Cuộn được để không tràn khi vùng chứa thấp (màn nhỏ, chữ lớn, bàn phím).
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: ShapeDecoration(
                  color: context.appPrimarySoft,
                  shape: AppShape.squircle(AppRadius.xl + 4),
                ),
                child: Icon(icon, size: 34, color: context.appPrimary),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.4, color: secondary),
                ),
              ],
              if (buttonLabel != null) ...[
                const SizedBox(height: 20),
                PrimaryButton(
                  label: buttonLabel!,
                  fullWidth: false,
                  onPressed: onPressed,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
