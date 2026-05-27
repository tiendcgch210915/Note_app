import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/json_utils.dart' show formatDateOnly;

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

  List<int> get activeDays =>
      (daysOfWeek ?? '').isEmpty
          ? []
          : daysOfWeek!.split(',').map(int.parse).toList();

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
  return showModalBottomSheet<RepeatSettings>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _RepeatPickerSheet(initial: initial ?? RepeatSettings.none),
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
    (
      label: 'Mỗi ngày',
      value: RepeatSettings(type: 'daily', interval: 1)
    ),
    (
      label: 'Mỗi 2 ngày',
      value: RepeatSettings(type: 'daily', interval: 2)
    ),
    (
      label: 'Mỗi 3 ngày',
      value: RepeatSettings(type: 'daily', interval: 3)
    ),
    (
      label: 'Mỗi tuần',
      value: RepeatSettings(type: 'daily', interval: 7)
    ),
    (
      label: 'Các ngày trong tuần',
      value: RepeatSettings(type: 'weekly', interval: 1, daysOfWeek: '1,2,3,4,5')
    ),
    (
      label: 'Cuối tuần',
      value: RepeatSettings(type: 'weekly', interval: 1, daysOfWeek: '6,7')
    ),
  ];

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  void _pickCustom() async {
    final result = await showModalBottomSheet<RepeatSettings>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CustomRepeatSheet(initial: _current),
    );
    if (result != null && mounted) {
      setState(() => _current = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Lặp lại',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (_current.hasRepeat)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(RepeatSettings.none),
                      child: const Text('Xoá'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ..._presets.map((p) => _PresetTile(
                  label: p.label,
                  selected: _isPresetMatch(p.value),
                  onTap: () => Navigator.of(context).pop(p.value),
                )),
            _PresetTile(
              label: 'Tùy chỉnh...',
              selected: _isCustom(),
              subtitle: _isCustom() ? _current.label : null,
              onTap: _pickCustom,
            ),
            if (_current.hasRepeat) ...[
              const Divider(height: 1),
              _EndDateTile(
                endDate: _current.endDate,
                onPick: (date) {
                  setState(() => _current = _current.copyWith(
                        endDate: date == null ? null : formatDateOnly(date),
                        clearEndDate: date == null,
                      ));
                },
              ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_current),
                  child: const Text('Xác nhận'),
                ),
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
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.primary : null,
        size: 22,
      ),
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle!) : null,
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
    return ListTile(
      leading: const Icon(Icons.event_available, size: 20),
      title: const Text('Ngày kết thúc'),
      subtitle: Text(endDate ?? 'Không có'),
      trailing: endDate == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => onPick(null),
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

  static const _dayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tùy chỉnh lặp lại',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            // Type selector
            Row(
              children: [
                _TypeChip(
                  label: 'Theo ngày',
                  selected: _type == 'daily',
                  onTap: () => setState(() => _type = 'daily'),
                ),
                const SizedBox(width: 8),
                _TypeChip(
                  label: 'Theo tuần',
                  selected: _type == 'weekly',
                  onTap: () {
                    setState(() {
                      _type = 'weekly';
                      if (_selectedDays.isEmpty) {
                        _selectedDays = {DateTime.now().weekday};
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Interval row
            Row(
              children: [
                const Text('Mỗi', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 12),
                _IntervalButton(
                  icon: Icons.remove,
                  enabled: _interval > 1,
                  onTap: () => setState(() => _interval--),
                ),
                const SizedBox(width: 8),
                Text('$_interval',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                _IntervalButton(
                  icon: Icons.add,
                  enabled: _interval < 90,
                  onTap: () => setState(() => _interval++),
                ),
                const SizedBox(width: 12),
                Text(_type == 'weekly' ? 'tuần' : 'ngày',
                    style: const TextStyle(fontSize: 15)),
              ],
            ),
            if (_type == 'weekly') ...[
              const SizedBox(height: 16),
              const Text('Các ngày trong tuần',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: List.generate(7, (i) {
                  final day = i + 1;
                  final selected = _selectedDays.contains(day);
                  return FilterChip(
                    label: Text(_dayNames[i]),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedDays.add(day);
                      } else if (_selectedDays.length > 1) {
                        _selectedDays.remove(day);
                      }
                    }),
                  );
                }),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _confirm,
                child: const Text('Xác nhận'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : null,
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : null,
            fontWeight: selected ? FontWeight.w600 : null,
          ),
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
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? AppColors.primary : Colors.grey),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.primary : Colors.grey,
        ),
      ),
    );
  }
}
