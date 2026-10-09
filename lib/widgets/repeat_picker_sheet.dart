import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import '../utils/json_utils.dart' show formatDateOnly;
import 'app_list_section.dart';
import 'app_segmented_control.dart';
import 'app_sheet.dart';
import 'pressable.dart';
import 'primary_button.dart';
import 'weekday_picker.dart';

// ─── RepeatSettings data class ─────────────────────────────────────────────

/// Immutable value object describing a recurrence pattern.
class RepeatSettings {
  final String? type; // null | "daily" | "weekly" | "custom"
  final int interval; // >= 1
  final String? daysOfWeek; // "1,3,5" or null
  final String? endDate; // "YYYY-MM-DD" or null

  const RepeatSettings({
    this.type,
    this.interval = 1,
    this.daysOfWeek,
    this.endDate,
  });

  static const RepeatSettings none = RepeatSettings();

  bool get hasRepeat => type != null;

  /// Same tolerant parsing as `Todo.activeDaysOfWeek` (and the backend): junk
  /// entries are dropped, the rest is de-duplicated and sorted.
  List<int> get activeDays {
    final days = <int>{};
    for (final part in (daysOfWeek ?? '').split(',')) {
      final day = int.tryParse(part.trim());
      if (day != null && day >= DateTime.monday && day <= DateTime.sunday) {
        days.add(day);
      }
    }
    return days.toList()..sort();
  }

  String get label {
    if (!hasRepeat) return 'Không lặp lại';
    switch (type) {
      case 'daily':
        if (interval == 1) return 'Mỗi ngày';
        if (interval == 7) return 'Mỗi tuần';
        return 'Mỗi $interval ngày';
      case 'weekly':
        final days = activeDays;
        if (days.isEmpty) return 'Mỗi tuần';
        const names = ['', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
        return days.map((d) => names[d]).join(', ');
      case 'custom':
        return 'Tùy chỉnh';
      default:
        return 'Lặp lại';
    }
  }

  RepeatSettings copyWith({
    String? type,
    int? interval,
    String? daysOfWeek,
    String? endDate,
    bool clearDaysOfWeek = false,
    bool clearEndDate = false,
  }) {
    return RepeatSettings(
      type: type ?? this.type,
      interval: interval ?? this.interval,
      daysOfWeek: clearDaysOfWeek ? null : (daysOfWeek ?? this.daysOfWeek),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
    );
  }
}

// ─── Sheet entry-point ─────────────────────────────────────────────────────

/// Shows the repeat picker bottom sheet and returns the chosen [RepeatSettings],
/// or null if the user dismissed without choosing.
Future<RepeatSettings?> showRepeatPicker(
  BuildContext context, {
  RepeatSettings? initial,
}) {
  return showAppSheet<RepeatSettings>(
    context: context,
    builder: (ctx) =>
        _RepeatPickerSheet(initial: initial ?? RepeatSettings.none),
  );
}

// ─── Private sheet widget ──────────────────────────────────────────────────

class _RepeatPickerSheet extends StatefulWidget {
  final RepeatSettings initial;
  const _RepeatPickerSheet({required this.initial});

  @override
  State<_RepeatPickerSheet> createState() => _RepeatPickerSheetState();
}

class _RepeatPickerSheetState extends State<_RepeatPickerSheet> {
  late RepeatSettings _current;

  // Preset definitions
  static const _presets = [
    (label: 'Không lặp lại', value: RepeatSettings.none),
    (label: 'Mỗi ngày', value: RepeatSettings(type: 'daily', interval: 1)),
    (label: 'Mỗi tuần', value: RepeatSettings(type: 'daily', interval: 7)),
  ];

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  void _pickCustom() async {
    final result = await showAppSheet<RepeatSettings>(
      context: context,
      builder: (ctx) => _CustomRepeatSheet(initial: _current),
    );
    if (result != null && mounted) {
      setState(() => _current = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSheetHeader(
              title: 'Lặp lại',
              trailing: _current.hasRepeat
                  ? TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(RepeatSettings.none),
                      child: const Text('Xoá'),
                    )
                  : null,
            ),
            AppListSection(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                ..._presets.map(
                  (p) => _PresetTile(
                    label: p.label,
                    selected: _isPresetMatch(p.value),
                    onTap: () => Navigator.of(context).pop(p.value),
                  ),
                ),
                _PresetTile(
                  label: 'Tùy chỉnh...',
                  selected: _isCustom(),
                  subtitle: _isCustom() ? _current.label : null,
                  onTap: _pickCustom,
                ),
              ],
            ),
            if (_current.hasRepeat)
              AppListSection(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  _EndDateTile(
                    endDate: _current.endDate,
                    onPick: (date) {
                      setState(
                        () => _current = _current.copyWith(
                          endDate: date == null ? null : formatDateOnly(date),
                          clearEndDate: date == null,
                        ),
                      );
                    },
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: PrimaryButton(
                label: 'Xác nhận',
                onPressed: () => Navigator.of(context).pop(_current),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isPresetMatch(RepeatSettings preset) {
    if (!preset.hasRepeat && !_current.hasRepeat) return true;
    return _current.type == preset.type &&
        _current.interval == preset.interval &&
        _current.daysOfWeek == preset.daysOfWeek &&
        !_isCustom();
  }

  bool _isCustom() {
    if (!_current.hasRepeat) return false;
    for (final p in _presets.skip(1)) {
      if (_current.type == p.value.type &&
          _current.interval == p.value.interval &&
          _current.daysOfWeek == p.value.daysOfWeek) {
        return false;
      }
    }
    return true;
  }
}

// ─── Preset tile ──────────────────────────────────────────────────────────

class _PresetTile extends StatelessWidget {
  final String label;
  final bool selected;
  final String? subtitle;
  final VoidCallback onTap;

  const _PresetTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      title: label,
      subtitle: subtitle,
      showChevron: false,
      trailing: selected
          ? Icon(Icons.check_rounded, color: context.appPrimary, size: 22)
          : null,
      onTap: onTap,
    );
  }
}

// ─── End-date tile ────────────────────────────────────────────────────────

class _EndDateTile extends StatelessWidget {
  final String? endDate;
  final void Function(DateTime? date) onPick;

  const _EndDateTile({required this.endDate, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      icon: Icons.event_available_rounded,
      title: 'Ngày kết thúc',
      value: endDate ?? 'Không có',
      showChevron: endDate == null,
      trailing: endDate == null
          ? null
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(null),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: context.appTextSecondary,
                ),
              ),
            ),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: now.add(const Duration(days: 30)),
          firstDate: now,
          lastDate: now.add(const Duration(days: 730)),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}

// ─── Custom sub-picker ────────────────────────────────────────────────────

class _CustomRepeatSheet extends StatefulWidget {
  final RepeatSettings initial;
  const _CustomRepeatSheet({required this.initial});

  @override
  State<_CustomRepeatSheet> createState() => _CustomRepeatSheetState();
}

class _CustomRepeatSheetState extends State<_CustomRepeatSheet> {
  late String _type; // 'daily' | 'weekly'
  late int _interval;
  late Set<int> _selectedDays; // 1=Mon…7=Sun

  @override
  void initState() {
    super.initState();
    _type = widget.initial.type ?? 'daily';
    if (_type == 'custom') _type = 'daily';
    _interval = widget.initial.interval.clamp(1, 90);
    _selectedDays = widget.initial.activeDays.toSet();
    if (_selectedDays.isEmpty && _type == 'weekly') {
      _selectedDays = {DateTime.now().weekday};
    }
  }

  void _confirm() {
    final settings = RepeatSettings(
      type: _type == 'weekly' ? 'weekly' : 'daily',
      interval: _interval,
      daysOfWeek: _type == 'weekly' && _selectedDays.isNotEmpty
          ? (_selectedDays.toList()..sort()).join(',')
          : null,
    );
    Navigator.of(context).pop(settings);
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        if (_selectedDays.length > 1) _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
    AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSheetHeader(
              title: 'Tùy chỉnh lặp lại',
              padding: EdgeInsets.only(bottom: 16),
            ),
            AppSegmentedControl<String>(
              value: _type,
              onChanged: (value) => setState(() {
                _type = value;
                if (value == 'weekly' && _selectedDays.isEmpty) {
                  _selectedDays = {DateTime.now().weekday};
                }
              }),
              segments: const [
                AppSegment(value: 'daily', label: 'Theo ngày'),
                AppSegment(value: 'weekly', label: 'Theo tuần'),
              ],
            ),
            const SizedBox(height: 20),
            // Interval row
            Row(
              children: [
                const Text('Mỗi', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 12),
                _IntervalButton(
                  icon: Icons.remove_rounded,
                  enabled: _interval > 1,
                  onTap: () => setState(() => _interval--),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$_interval',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _IntervalButton(
                  icon: Icons.add_rounded,
                  enabled: _interval < 90,
                  onTap: () => setState(() => _interval++),
                ),
                const SizedBox(width: 12),
                Text(
                  _type == 'weekly' ? 'tuần' : 'ngày',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            if (_type == 'weekly') ...[
              const SizedBox(height: 20),
              Text(
                'Chọn thứ lặp lại',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.appTextSecondary,
                ),
              ),
              const SizedBox(height: 10),
              WeekdayPicker(selected: _selectedDays, onToggle: _toggleDay),
            ],
            const SizedBox(height: 24),
            PrimaryButton(label: 'Xác nhận', onPressed: _confirm),
          ],
        ),
      ),
    );
  }
}

class _IntervalButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _IntervalButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? context.appPrimary
        : context.appTextSecondary.withValues(alpha: 0.5);
    return Pressable(
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                AppHaptics.selection();
                onTap();
              }
            : null,
        child: Container(
          width: 44,
          height: 44,
          decoration: ShapeDecoration(
            color: enabled ? context.appPrimarySoft : Colors.transparent,
            shape: AppShape.squircle(
              AppRadius.sm,
              side: enabled
                  ? BorderSide.none
                  : BorderSide(color: context.appDivider),
            ),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}
