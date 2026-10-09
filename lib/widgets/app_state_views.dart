import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'primary_button.dart';

/// Spinner kiểu iOS, hiện dần để tránh nhấp nháy khi tải nhanh.
class AppSpinner extends StatelessWidget {
  final double radius;
  final bool centered;

  const AppSpinner({super.key, this.radius = 12, this.centered = true});

  @override
  Widget build(BuildContext context) {
    final spinner = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: CupertinoActivityIndicator(
        radius: radius,
        color: context.appTextSecondary,
      ),
    );
    return centered ? Center(child: spinner) : spinner;
  }
}

/// Trạng thái lỗi có nút "Thử lại", dùng khi không có dữ liệu cache để hiển thị.
class AppErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Thử lại',
  });

  @override
  Widget build(BuildContext context) {
    // Cuộn được để không tràn khi vùng chứa thấp (màn nhỏ, chữ lớn).
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: ShapeDecoration(
                color: context.appDangerSoft,
                shape: AppShape.squircle(AppRadius.xl),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 30,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              PrimaryButton(
                label: retryLabel,
                icon: Icons.refresh_rounded,
                fullWidth: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
