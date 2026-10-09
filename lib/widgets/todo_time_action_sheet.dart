import 'package:flutter/material.dart';

import 'app_list_section.dart';
import 'app_sheet.dart';

/// Hành động trả về từ [showTodoTimeActionSheet].
const String todoTimeActionPick = 'pick';
const String todoTimeActionClear = 'clear';

/// Sheet hỏi người dùng muốn đổi giờ hay bỏ giờ của một todo đã có giờ.
/// Trả về [todoTimeActionPick] / [todoTimeActionClear] hoặc `null` nếu đóng.
Future<String?> showTodoTimeActionSheet(
  BuildContext context, {
  required String currentTime,
}) {
  return showAppSheet<String>(
    context: context,
    builder: (ctx) => AppSheetScaffold(
      title: 'Giờ làm',
      child: AppListSection(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        dividerIndent: AppListSection.iconIndent,
        children: [
          AppListTile(
            icon: Icons.schedule_rounded,
            title: 'Chọn giờ',
            subtitle: 'Hiện tại: $currentTime',
            showChevron: false,
            onTap: () => Navigator.of(ctx).pop(todoTimeActionPick),
          ),
          AppListTile(
            icon: Icons.close_rounded,
            title: 'Bỏ giờ',
            showChevron: false,
            destructive: true,
            onTap: () => Navigator.of(ctx).pop(todoTimeActionClear),
          ),
        ],
      ),
    ),
  );
}
