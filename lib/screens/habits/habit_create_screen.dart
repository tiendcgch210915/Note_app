import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../models/habit.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_snack.dart';
import '../../utils/date_utils.dart';
import '../../utils/habit_style_pool.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/habit_form_sections.dart';
import '../../widgets/primary_button.dart';

class HabitCreateScreen extends StatefulWidget {
  const HabitCreateScreen({super.key});

  @override
  State<HabitCreateScreen> createState() => _HabitCreateScreenState();
}

class _HabitCreateScreenState extends State<HabitCreateScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String _iconName = 'flag';
  Color _color = HabitStylePool.defaultColor;
  FrequencyType _frequency = FrequencyType.daily;
  final Set<int> _weekdays = {1, 2, 3, 4, 5};
  DateTime _startDate = AppDateUtils.dateOnly(DateTime.now());
  DateTime? _endDate;
  bool _saving = false;
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      AppHaptics.heavy();
      setState(() => _titleError = 'Vui lòng nhập tên thói quen');
      return;
    }
    setState(() => _saving = true);
    try {
      final weekdays = _frequency == FrequencyType.daily
          ? null
          : (_weekdays.toList()..sort());
      final body = Habit.createBody(
        title: _title.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        icon: _iconName,
        color: _color,
        frequencyType: _frequency,
        activeWeekdays: weekdays,
        startDate: _startDate,
        endDate: _endDate,
      );
      await HabitsRepository.instance.create(body);
      if (!mounted) return;
      AppHaptics.medium();
      Navigator.of(context).pop(true);
      showAppSnack(context, 'Đã tạo thói quen');
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.vnMessage, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleWeekday(int day) {
    setState(() {
      if (!_weekdays.add(day)) _weekdays.remove(day);
    });
    AppHaptics.selection();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = AppDateUtils.dateOnly(picked);
      if (_endDate != null && _endDate!.isBefore(_startDate)) {
        _endDate = null;
      }
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() => _endDate = AppDateUtils.dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thói quen mới'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: SizedBox(
              width: 36,
              child: Center(
                child: _saving
                    ? const AppSpinner(radius: 9, centered: false)
                    : const Text(
                        'Lưu',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: AppSurface(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(
                children: [
                  TextField(
                    controller: _title,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_titleError != null) {
                        setState(() => _titleError = null);
                      }
                    },
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Tên thói quen',
                      errorText: _titleError,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const Divider(height: 1),
                  TextField(
                    controller: _desc,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Mô tả (tùy chọn)',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          HabitAppearanceSection(
            iconName: _iconName,
            color: _color,
            onIconChanged: (name) => setState(() => _iconName = name),
            onColorChanged: (color) => setState(() => _color = color),
          ),
          HabitScheduleSection(
            frequency: _frequency,
            weekdays: _weekdays,
            startDate: _startDate,
            endDate: _endDate,
            onFrequencyChanged: (f) => setState(() => _frequency = f),
            onToggleWeekday: _toggleWeekday,
            onPickStart: _pickStart,
            onPickEnd: _pickEnd,
            onClearEnd: () => setState(() => _endDate = null),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PrimaryButton(
              label: 'Tạo thói quen',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
