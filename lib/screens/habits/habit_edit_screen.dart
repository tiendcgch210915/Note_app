import 'package:flutter/material.dart';

import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../data/todos_repository.dart';
import '../../models/habit.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_snack.dart';
import '../../utils/date_utils.dart';
import '../../utils/json_utils.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/habit_form_sections.dart';
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
  String? _titleError;
  final Set<String> _savingTodoIds = {};

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
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      AppHaptics.heavy();
      setState(() => _titleError = 'Vui lòng nhập tên thói quen');
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
      AppHaptics.medium();
      Navigator.of(context).pop(true);
      showAppSnack(context, 'Đã lưu thói quen');
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
      showAppSnack(context, 'Không có todo phù hợp để liên kết');
      return null;
    }

    return showAppSheet<Todo>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppSheetHeader(title: 'Chọn todo liên quan'),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: selectable.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 0.5, indent: 56, color: ctx.appDivider),
                  itemBuilder: (_, index) {
                    final todo = selectable[index];
                    return ListTile(
                      leading: Icon(
                        todo.habitId == null
                            ? Icons.radio_button_unchecked
                            : Icons.swap_horiz_rounded,
                        color: todo.habitId == null
                            ? ctx.appTextSecondary
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

  void _toggleWeekday(int day) {
    setState(() {
      if (!_weekdays.add(day)) _weekdays.remove(day);
    });
    AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = context.appTextSecondary;
    // AppBar đổi màu mượt khi người dùng chọn màu khác.
    final appBar = PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: _color.withValues(alpha: 0.12)),
        duration: AppMotion.normal,
        builder: (context, color, _) => AppBar(
          title: const Text('Sửa thói quen'),
          backgroundColor: color,
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
      ),
    );

    return Scaffold(
      appBar: appBar,
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
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
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
            onPickStart: _pickStartDate,
            onPickEnd: _pickEndDate,
            onClearEnd: () => setState(() => _endDate = null),
          ),
          const SectionHeader(label: 'Todos liên quan'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: PrimaryButton(
              label: 'Thêm todo liên quan',
              icon: Icons.add_link_rounded,
              variant: PrimaryButtonVariant.tonal,
              onPressed: _addRelatedTodo,
            ),
          ),
          if (_loadingTodos && _relatedTodos.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: AppSpinner())
          else if (_relatedTodos.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
              child: Text(
                'Chưa có todo liên kết',
                style: TextStyle(color: secondary),
              ),
            )
          else
            AppListSection(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              dividerIndent: AppListSection.iconIndent,
              children: [
                for (final todo in _relatedTodos)
                  AppListTile(
                    icon: todo.isDone
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    iconColor: todo.isDone
                        ? AppColors.success
                        : AppColors.tagSlate,
                    title: todo.title,
                    subtitle: _todoSubtitle(todo),
                    onTap: () => _openTodo(todo),
                    trailing: _savingTodoIds.contains(todo.id)
                        ? const SizedBox(
                            width: 36,
                            height: 36,
                            child: AppSpinner(radius: 8),
                          )
                        : AppClearButton(
                            tooltip: 'Bỏ liên kết',
                            onTap: () => _unlinkTodo(todo),
                          ),
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: PrimaryButton(
              label: 'Lưu thay đổi',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
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
    showAppSnack(context, msg, isError: true);
  }
}
