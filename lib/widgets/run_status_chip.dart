import 'package:flutter/material.dart';

import '../models/run.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Huy hiệu trạng thái của một lượt chạy checklist (đang làm / xong / hủy).
/// Dùng chung cho tab Lịch sử và màn Lịch sử run.
class RunStatusChip extends StatelessWidget {
  final RunStatus status;

  const RunStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color c = switch (status) {
      RunStatus.inProgress => AppColors.success,
      RunStatus.completed => context.appTextSecondary,
      RunStatus.abandoned => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: c.withValues(alpha: 0.15),
        shape: AppShape.pill,
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w700),
      ),
    );
  }
}
