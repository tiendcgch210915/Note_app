import 'package:flutter/material.dart';

import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../data/todos_repository.dart';
import '../../models/habit.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/json_utils.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import '../todos/todo_detail_screen.dart';

class HabitEditScreen extends StatefulWidget {
  final Habit habit;

  const HabitEditScreen({super.key, required this.habit});

  @override
  State<HabitEditScreen> createState() => _HabitEditScreenState();
}

class _HabitEditScreenState extends State<HabitEditScreen> {
  late Habit _habit = widget.habit;
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late String _iconName;
  late Color _color;
  late FrequencyType _frequency;
  late Set<int> _weekdays;
  late DateTime _startDate;
  late DateTime? _endDate;
  List<Todo> _relatedTodos = const [];
  bool _saving = false;
  bool _loadingTodos = false;
  final Set<String> _savingTodoIds = {};

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
  void initState() {
    super.initState();
    _title = TextEditingController(text: _habit.title);
    _desc = TextEditingController(text: _habit.description ?? '');
    _iconName = _habit.iconName ?? 'flag';
    _color = _habit.color;
    _frequency = _habit.frequencyType;
    _weekdays = (_habit.activeWeekdays ?? const [1, 2, 3, 4, 5]).toSet();
    _startDate = AppDateUtils.dateOnly(_habit.startDate);
    _endDate = _habit.endDate == null
        ? null
        : AppDateUtils.dateOnly(_habit.endDate!);
    _loadRelatedTodos();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _showError('Vui lòng nhập tên thói quen');
      return;
    }
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      _showError('Ngày kết thúc phải sau ngày bắt đầu');
      return;
    }

    setState(() => _saving = true);
    try {
      final weekdays = _frequency == FrequencyType.daily
          ? null
          : (_weekdays.toList()..sort());
      final body = <String, dynamic>{
        'title': title,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'icon': _iconName,
        'color': formatColorHex(_color),
        'frequency_type': _frequency.backendValue,
        'target_per_period': Habit.createTargetPerPeriod(
          frequencyType: _frequency,
          startDate: _startDate,
          endDate: _endDate,
          activeWeekdays: weekdays,
        ),
        'active_weekdays': weekdays?.join(','),
        'start_date': formatDateOnly(_startDate),
        'end_date': _endDate == null ? null : formatDateOnly(_endDate!),
      };
      final updated = await HabitsRepository.instance.updateLocalFirst(
        _habit,
        body,
      );
      if (!mounted) return;
      setState(() => _habit = updated);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã lưu thói quen')));
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadRelatedTodos() async {
    setState(() => _loadingTodos = true);
    final local = await TodosRepository.instance.listByHabitLocal(_habit.id);
    if (mounted) setState(() => _relatedTodos = local);
    try {
      final remote = await TodosRepository.instance.list(
        habitId: _habit.id,
        limit: 100,
      );
      if (mounted) setState(() => _relatedTodos = remote.items);
    } on ApiException catch (e) {
      if (e.code != 'no_connection' && mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loadingTodos = false);
    }
  }

  Future<void> _addRelatedTodo() async {
    final todo = await _pickTodoToLink();
    if (todo == null || !mounted) return;
    await _setTodoHabit(todo, _habit.id);
  }

  Future<Todo?> _pickTodoToLink() async {
    var candidates = await TodosRepository.instance.listLocal(
      includeDone: false,
    );
    try {
      final remote = await TodosRepository.instance.list(limit: 100);
      candidates = remote.items
          .where(
            (todo) =>
                todo.parentId == null &&
                todo.status != TodoStatus.done &&
                todo.status != TodoStatus.archived,
          )
          .toList();
    } on ApiException catch (e) {
      if (e.code != 'no_connection' && mounted) _showError(e.vnMessage);
    }

    final currentIds = _relatedTodos.map((todo) => todo.id).toSet();
    final selectable = candidates
        .where((todo) => !currentIds.contains(todo.id))
        .toList();
    if (!mounted) return null;
    if (selectable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có todo phù hợp để liên kết')),
      );
      return null;
    }

    return showModalBottomSheet<Todo>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, color: _color, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Chọn todo liên quan',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: selectable.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final todo = selectable[index];
                    return ListTile(
                      leading: Icon(
                        todo.habitId == null
                            ? Icons.radio_button_unchecked
                            : Icons.swap_horiz_rounded,
                        color: todo.habitId == null
                            ? AppColors.textSecondary
                            : AppColors.warning,
                      ),
                      title: Text(
                        todo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_todoSubtitle(todo)),
                      onTap: () => Navigator.of(ctx).pop(todo),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unlinkTodo(Todo todo) async {
    await _setTodoHabit(todo, null);
  }

  Future<void> _setTodoHabit(Todo todo, String? habitId) async {
    if (_savingTodoIds.contains(todo.id)) return;
    final previous = _relatedTodos;
    final optimistic = todo.copyWith(habitId: habitId);
    setState(() {
      _savingTodoIds.add(todo.id);
      if (habitId == null) {
        _relatedTodos = _relatedTodos
            .where((item) => item.id != todo.id)
            .toList();
      } else {
        _relatedTodos = [
          optimistic,
          ..._relatedTodos.where((item) => item.id != optimistic.id),
        ];
      }
    });
    try {
      final updated = await TodosRepository.instance.updateLocalFirst(todo, {
        'habit_id': habitId,
      });
      if (!mounted) return;
      setState(() {
        if (habitId == null) {
          _relatedTodos = _relatedTodos
              .where((item) => item.id != todo.id)
              .toList();
        } else {
          _relatedTodos = [
            updated,
            ..._relatedTodos.where((item) => item.id != updated.id),
          ];
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _relatedTodos = previous);
      _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _savingTodoIds.remove(todo.id));
    }
  }

  Future<void> _openTodo(Todo todo) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: todo.id)),
    );
    if (mounted) _loadRelatedTodos();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sửa thói quen'),
        backgroundColor: _color.withValues(alpha: 0.12),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Lưu',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: 'Tên thói quen'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _desc,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Mô tả (tùy chọn)'),
            ),
          ),
          const SizedBox(height: 8),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SegmentedButton<FrequencyType>(
              segments: const [
                ButtonSegment(
                  value: FrequencyType.daily,
                  label: Text('Hàng ngày'),
                ),
                ButtonSegment(
                  value: FrequencyType.weekly,
                  label: Text('Hàng tuần'),
                ),
                ButtonSegment(
                  value: FrequencyType.custom,
                  label: Text('Tùy chọn'),
                ),
              ],
              selected: {_frequency},
              onSelectionChanged: (s) => setState(() => _frequency = s.first),
            ),
          ),
          if (_frequency != FrequencyType.daily)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
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
            ),
          ListTile(
            leading: const Icon(Icons.play_arrow_outlined),
            title: const Text('Ngày bắt đầu'),
            subtitle: Text(AppDateUtils.formatDate(_startDate)),
            onTap: _pickStartDate,
          ),
          ListTile(
            leading: const Icon(Icons.stop_outlined),
            title: const Text('Ngày kết thúc'),
            subtitle: Text(
              _endDate == null
                  ? 'Không có'
                  : AppDateUtils.formatDate(_endDate!),
            ),
            trailing: _endDate == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _endDate = null),
                  ),
            onTap: _pickEndDate,
          ),
          const SectionHeader(label: 'Todos liên quan'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('Thêm todo liên quan'),
              onPressed: _addRelatedTodo,
            ),
          ),
          if (_loadingTodos && _relatedTodos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_relatedTodos.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Chưa có todo liên kết',
                style: TextStyle(color: secondary),
              ),
            )
          else
            ..._relatedTodos.map(
              (todo) => ListTile(
                leading: Icon(
                  todo.isDone
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: todo.isDone ? AppColors.success : secondary,
                ),
                title: Text(
                  todo.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_todoSubtitle(todo)),
                onTap: () => _openTodo(todo),
                trailing: _savingTodoIds.contains(todo.id)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.link_off_rounded),
                        tooltip: 'Bỏ liên kết',
                        onPressed: () => _unlinkTodo(todo),
                      ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: PrimaryButton(
              label: 'Lưu thay đổi',
              icon: Icons.check,
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = AppDateUtils.dateOnly(picked);
      if (_endDate != null && _endDate!.isBefore(_startDate)) _endDate = null;
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null || !mounted) return;
    setState(() => _endDate = AppDateUtils.dateOnly(picked));
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
              final selected = tuple.$1 == _iconName;
              return InkWell(
                onTap: () {
                  setState(() => _iconName = tuple.$1);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  alignment: Alignment.center,
                  decoration: selected
                      ? BoxDecoration(
                          color: _color.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        )
                      : null,
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
                        ? Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
                            width: 3,
                          )
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

  String _todoSubtitle(Todo todo) {
    final parts = <String>[todo.status.label];
    if (todo.scheduledDate != null) {
      parts.add(AppDateUtils.formatDate(todo.scheduledDate!));
    }
    if (todo.habitId != null && todo.habitId != _habit.id) {
      parts.add('Sẽ thay thế habit đang liên kết');
    }
    return parts.join(' · ');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }
}
