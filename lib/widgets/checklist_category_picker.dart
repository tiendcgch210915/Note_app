import 'package:flutter/material.dart';

import '../models/checklist_category.dart';
import '../theme/app_colors.dart';
import 'app_list_section.dart';
import 'app_sheet.dart';

/// Giá trị trả về của [showChecklistCategorySheet] khi chọn "Chưa phân loại".
const String kUncategorizedCategory = '__uncategorized__';

/// Sheet chọn danh mục cho một template. Trả về id danh mục,
/// [kUncategorizedCategory] khi bỏ phân loại, hoặc `null` nếu đóng sheet.
Future<String?> showChecklistCategorySheet(
  BuildContext context, {
  required List<ChecklistCategory> categories,
  required String? selectedId,
}) {
  return showAppSheet<String>(
    context: context,
    builder: (ctx) {
      final check = Icon(Icons.check_rounded, color: ctx.appPrimary, size: 22);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHeader(title: 'Danh mục'),
            Flexible(
              child: SingleChildScrollView(
                child: AppListSection(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  dividerIndent: AppListSection.iconIndent,
                  children: [
                    AppListTile(
                      icon: Icons.block_rounded,
                      iconColor: AppColors.tagSlate,
                      title: 'Chưa phân loại',
                      showChevron: false,
                      trailing: selectedId == null ? check : null,
                      onTap: () =>
                          Navigator.of(ctx).pop(kUncategorizedCategory),
                    ),
                    for (final category in categories)
                      AppListTile(
                        icon: ChecklistCategory.iconFor(category.icon),
                        iconColor: category.color,
                        title: category.name,
                        subtitle: category.isSystem ? 'Hệ thống' : 'Của tôi',
                        showChevron: false,
                        trailing: selectedId == category.id ? check : null,
                        onTap: () => Navigator.of(ctx).pop(category.id),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
