import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../models/habit.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
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
  Color _color = AppColors.tagIndigo;
  FrequencyType _frequency = FrequencyType.daily;
  int _target = 1;
  final Set<int> _weekdays = {1, 2, 3, 4, 5};
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _saving = false;

  /// Identifier strings + IconData để render preview.
  static const _iconPool = <(String, IconData)>[
    ('book', Icons.menu_book),
    ('fitness', Icons.fitness_center),
    ('water', Icons.local_drink),
    ('meditation', Icons.self_improvement),
    ('run', Icons.directions_run),
    ('sleep', Icons.bedtime),
    ('money', Icons.savings),
    ('code', Icons.code),
    ('brush', Icons.brush),
    ('music', Icons.music_note),
    ('brain', Icons.psychology),
    ('eco', Icons.eco),
    ('lightbulb', Icons.lightbulb_outline),
    ('heart', Icons.favorite_outline),
    ('spa', Icons.spa),
    ('school', Icons.school),
    ('bolt', Icons.bolt),
    ('flower', Icons.local_florist),
    ('sun', Icons.sunny),
    ('terrain', Icons.terrain),
  ];

  static const _colorPool = [
    Color(0xFF4F46E5),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFFA855F7),
    Color(0xFF64748B),
  ];

  IconData get _iconData => Habit.iconFor(_iconName) ?? Icons.flag;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên thói quen')),
      );
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
        targetPerPeriod: _target,
        activeWeekdays: weekdays,
        startDate: _startDate,
        endDate: _endDate,
      );
      await HabitsRepository.instance.create(body);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã tạo thói quen')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.vnMessage), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thói quen mới'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Lưu',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(hintText: 'Tên thói quen'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Mô tả (tùy chọn)'),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(_iconData, color: _color, size: 20),
            ),
            title: const Text('Icon'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickIcon,
          ),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
            ),
            title: const Text('Màu sắc'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickColor,
          ),
          const SizedBox(height: 12),
          SegmentedButton<FrequencyType>(
            segments: const [
              ButtonSegment(value: FrequencyType.daily, label: Text('Hàng ngày')),
              ButtonSegment(value: FrequencyType.weekly, label: Text('Hàng tuần')),
              ButtonSegment(value: FrequencyType.custom, label: Text('Tùy chọn')),
            ],
            selected: {_frequency},
            onSelectionChanged: (s) => setState(() => _frequency = s.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Mục tiêu:'),
              Expanded(
                child: Slider(
                  value: _target.toDouble(),
                  min: 1,
                  max: 7,
                  divisions: 6,
                  label: '$_target',
                  onChanged: (v) => setState(() => _target = v.round()),
                ),
              ),
              Text('$_target'),
            ],
          ),
          if (_frequency != FrequencyType.daily) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(7, (i) {
                final day = i + 1;
                final on = _weekdays.contains(day);
                return FilterChip(
                  label: Text(AppDateUtils.weekdayShort(day)),
                  selected: on,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _weekdays.add(day);
                    } else {
                      _weekdays.remove(day);
                    }
                  }),
                );
              }),
            ),
          ],
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.play_arrow_outlined),
            title: const Text('Ngày bắt đầu'),
            subtitle: Text(AppDateUtils.formatDate(_startDate)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _startDate = picked);
            },
          ),
          ListTile(
            leading: const Icon(Icons.stop_outlined),
            title: const Text('Ngày kết thúc'),
            subtitle: Text(_endDate == null ? 'Không có' : AppDateUtils.formatDate(_endDate!)),
            trailing: _endDate == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _endDate = null),
                  ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
                firstDate: _startDate,
                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              );
              if (picked != null) setState(() => _endDate = picked);
            },
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Tạo thói quen', icon: Icons.check, onPressed: _save),
        ],
      ),
    );
  }

  void _pickIcon() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            children: _iconPool.map((tuple) {
              return InkWell(
                onTap: () {
                  setState(() => _iconName = tuple.$1);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  alignment: Alignment.center,
                  child: Icon(tuple.$2, size: 28, color: _color),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _pickColor() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: _colorPool.map((c) {
              return GestureDetector(
                onTap: () {
                  setState(() => _color = c);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: c == _color
                        ? Border.all(color: AppColors.primary, width: 3)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
