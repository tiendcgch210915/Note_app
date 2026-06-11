import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class DurationPickerSheet extends StatefulWidget {
  final int initialMinutes;
  final String title;
  final String actionLabel;
  final IconData actionIcon;

  const DurationPickerSheet({
    super.key,
    this.initialMinutes = 25,
    this.title =
        'Bạn sẽ cho bản thân mình bao nhiêu thời gian để hoàn thiện todos này?',
    this.actionLabel = 'Bắt đầu',
    this.actionIcon = Icons.play_arrow_rounded,
  });

  @override
  State<DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<DurationPickerSheet> {
  late int _hours;
  late int _minutes;

  int get _totalMinutes => _hours * 60 + _minutes;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMinutes.clamp(0, 12 * 60 + 59);
    _hours = initial ~/ 60;
    _minutes = initial.remainder(60);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _DurationWheel(
                    label: 'Giờ',
                    value: _hours,
                    max: 12,
                    onChanged: (value) => setState(() => _hours = value),
                  ),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: secondary,
                  ),
                ),
                Expanded(
                  child: _DurationWheel(
                    label: 'Phút',
                    value: _minutes,
                    max: 59,
                    onChanged: (value) => setState(() => _minutes = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${_hours.toString().padLeft(2, '0')}:${_minutes.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _totalMinutes == 0 ? secondary : AppColors.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _totalMinutes == 0
                    ? null
                    : () => Navigator.of(context).pop(_totalMinutes),
                icon: Icon(widget.actionIcon),
                label: Text(widget.actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationWheel extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _DurationWheel({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 150,
          child: CupertinoPicker(
            scrollController: FixedExtentScrollController(initialItem: value),
            itemExtent: 40,
            magnification: 1.08,
            useMagnifier: true,
            onSelectedItemChanged: onChanged,
            children: [
              for (var i = 0; i <= max; i++)
                Center(
                  child: Text(
                    i.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String formatDurationMinutes(int minutes) {
  if (minutes < 60) return '$minutes phút';
  final hours = minutes ~/ 60;
  final rest = minutes.remainder(60);
  if (rest == 0) return '$hours giờ';
  return '$hours giờ $rest phút';
}

String formatDurationMinutesShort(int minutes) {
  if (minutes < 60) return '${minutes}p';
  final hours = minutes ~/ 60;
  final rest = minutes.remainder(60);
  if (rest == 0) return '${hours}h';
  return '${hours}h${rest}p';
}
