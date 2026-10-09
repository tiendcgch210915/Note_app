import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import '../utils/date_utils.dart';
import '../utils/habit_style_pool.dart';
import 'app_list_section.dart';
import 'app_segmented_control.dart';
import 'app_sheet.dart';
import 'pressable.dart';
import 'weekday_picker.dart';

/// Chọn icon cho thói quen. Trả về định danh icon hoặc `null` nếu đóng sheet.
Future<String?> showHabitIconSheet(
  BuildContext context, {
  required String selectedIcon,
  required Color color,
}) {
  return showAppSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSheetHeader(
              title: 'Chọn icon',
              padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
            ),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final (name, icon) in HabitStylePool.icons)
                  _IconCell(
                    icon: icon,
                    color: color,
                    selected: name == selectedIcon,
                    onTap: () {
                      AppHaptics.selection();
                      Navigator.of(ctx).pop(name);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Chọn màu cho thói quen. Trả về màu hoặc `null` nếu đóng sheet.
Future<Color?> showHabitColorSheet(
  BuildContext context, {
  required Color selected,
}) {
  return showAppSheet<Color>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSheetHeader(
              title: 'Chọn màu',
              padding: EdgeInsets.only(bottom: 16),
            ),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final c in HabitStylePool.colors)
                  _ColorSwatch(
                    color: c,
                    selected: c.toARGB32() == selected.toARGB32(),
                    onTap: () {
                      AppHaptics.selection();
                      Navigator.of(ctx).pop(c);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _IconCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _IconCell({
    required this.icon,
    required this.color,
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
          decoration: ShapeDecoration(
            color: selected
                ? color.withValues(alpha: 0.16)
                : context.appTextSecondary.withValues(alpha: 0.08),
            shape: AppShape.squircle(
              AppRadius.md,
              side: selected
                  ? BorderSide(color: color, width: 1.6)
                  : BorderSide.none,
            ),
          ),
          child: Icon(icon, size: 28, color: color),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: context.appTextPrimary, width: 3)
                : null,
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }
}

/// Nhóm "Giao diện": chọn icon + màu của thói quen.
class HabitAppearanceSection extends StatelessWidget {
  final String iconName;
  final Color color;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<Color> onColorChanged;

  const HabitAppearanceSection({
    super.key,
    required this.iconName,
    required this.color,
    required this.onIconChanged,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppListSection(
      header: 'Giao diện',
      dividerIndent: AppListSection.iconIndent,
      children: [
        AppListTile(
          icon: Habit.iconFor(iconName) ?? Icons.flag,
          iconColor: color,
          title: 'Icon',
          onTap: () async {
            final picked = await showHabitIconSheet(
              context,
              selectedIcon: iconName,
              color: color,
            );
            if (picked != null) onIconChanged(picked);
          },
        ),
        AppListTile(
          icon: Icons.palette_rounded,
          iconColor: color,
          title: 'Màu sắc',
          trailing: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          onTap: () async {
            final picked = await showHabitColorSheet(context, selected: color);
            if (picked != null) onColorChanged(picked);
          },
        ),
      ],
    );
  }
}

/// Nhóm "Lịch": tần suất, thứ trong tuần, ngày bắt đầu/kết thúc.
class HabitScheduleSection extends StatelessWidget {
  final FrequencyType frequency;
  final Set<int> weekdays;
  final DateTime startDate;
  final DateTime? endDate;
  final ValueChanged<FrequencyType> onFrequencyChanged;
  final ValueChanged<int> onToggleWeekday;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onClearEnd;

  const HabitScheduleSection({
    super.key,
    required this.frequency,
    required this.weekdays,
    required this.startDate,
    required this.endDate,
    required this.onFrequencyChanged,
    required this.onToggleWeekday,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onClearEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: AppSegmentedControl<FrequencyType>(
            value: frequency,
            onChanged: onFrequencyChanged,
            segments: const [
              AppSegment(value: FrequencyType.daily, label: 'Hàng ngày'),
              AppSegment(value: FrequencyType.weekly, label: 'Hàng tuần'),
              AppSegment(value: FrequencyType.custom, label: 'Tùy chọn'),
            ],
          ),
        ),
        AnimatedSize(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: frequency == FrequencyType.daily
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: WeekdayPicker(
                    selected: weekdays,
                    onToggle: onToggleWeekday,
                  ),
                ),
        ),
        AppListSection(
          dividerIndent: AppListSection.iconIndent,
          children: [
            AppListTile(
              icon: Icons.play_arrow_rounded,
              iconColor: AppColors.success,
              title: 'Ngày bắt đầu',
              value: AppDateUtils.formatDate(startDate),
              onTap: onPickStart,
            ),
            AppListTile(
              icon: Icons.stop_rounded,
              iconColor: AppColors.tagRed,
              title: 'Ngày kết thúc',
              value: endDate == null
                  ? 'Không có'
                  : AppDateUtils.formatDate(endDate!),
              trailing: endDate == null
                  ? null
                  : AppClearButton(
                      tooltip: 'Bỏ ngày kết thúc',
                      onTap: onClearEnd,
                    ),
              showChevron: endDate == null,
              onTap: onPickEnd,
            ),
          ],
        ),
      ],
    );
  }
}
