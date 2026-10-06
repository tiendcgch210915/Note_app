import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../data/todos_repository.dart';
import '../../models/habit.dart';
import '../../models/tag.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/json_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../utils/todo_trigger_picker.dart';
import '../../widgets/duration_picker_sheet.dart';
import '../../widgets/habit_selector_sheet.dart';
import '../../widgets/repeat_picker_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tag_chip.dart';
import '../../widgets/todo_flag_button.dart';
import '../../widgets/todo_tag_selector_sheet.dart';

/// Màn hình "chỉnh sửa" — chỉnh tất cả properties của todo:
/// meta (ngày làm, ước lượng), classify Eisenhower, frog, tags,
/// linked notes. KHÔNG có subtask list (subtask quản lý ở TodoDetailScreen).
class TodoEditScreen extends StatefulWidget {
  final String todoId;
  const TodoEditScreen({super.key, required this.todoId});

  @override
  State<TodoEditScreen> createState() => _TodoEditScreenState();
}

class _TodoEditScreenState extends State<TodoEditScreen> {
  TodoWithRelations? _detail;
  final _titleCtrl = TextEditingController();
  Habit? _selectedHabit;
  String? _selectedHabitId;
  String? _triggerTodoTitle;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_detail == null) {
      final local = await TodosRepository.instance.getLocalDetail(
        widget.todoId,
      );
      if (!mounted) return;
      if (local != null) {
        setState(() {
          _detail = local;
          _titleCtrl.text = local.todo.title;
          _selectedHabitId = local.todo.habitId;
          _selectedHabit = null;
          _triggerTodoTitle = null;
        });
        _loadSelectedHabit(local.todo.habitId);
      }
    }
    final hasPending = await TodosRepository.instance.hasPendingLocalWrites();
    if (hasPending && _detail != null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final detail = await TodosRepository.instance.getDetail(widget.todoId);
      final triggerTitle =
          detail.todo.parentId != null || detail.todo.triggerAfterTodoId == null
          ? null
          : await TodosRepository.instance.getTodoTitle(
              detail.todo.triggerAfterTodoId!,
            );
      if (!mounted) return;
      final hasPendingAfter = await TodosRepository.instance
          .hasPendingLocalWrites();
      if (hasPendingAfter) {
        final local = await TodosRepository.instance.getLocalDetail(
          widget.todoId,
        );
        if (!mounted || local == null) return;
        setState(() {
          _detail = local;
          _titleCtrl.text = local.todo.title;
          _selectedHabitId = local.todo.habitId;
          _selectedHabit = null;
          _triggerTodoTitle = null;
        });
        _loadSelectedHabit(local.todo.habitId);
        return;
      }
      setState(() {
        _detail = detail;
        _titleCtrl.text = detail.todo.title;
        _selectedHabitId = detail.todo.habitId;
        _selectedHabit = null;
        _triggerTodoTitle = triggerTitle;
      });
      _loadSelectedHabit(detail.todo.habitId);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_detail == null || e.code != 'no_connection') {
        _showError(e.vnMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // EXP 3 — Move to Day
  Future<void> _moveToDay() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Đổi ngày'),
              onTap: () => Navigator.of(ctx).pop('pick'),
            ),
            if (todo.scheduledDate != null)
              ListTile(
                leading: const Icon(Icons.event_busy),
                title: const Text('Bỏ ngày (floating)'),
                onTap: () => Navigator.of(ctx).pop('clear'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'clear') {
      _doMove(null);
    } else if (action == 'pick') {
      final picked = await showDatePicker(
        context: context,
        initialDate: todo.scheduledDate ?? DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null && mounted) _doMove(picked);
    }
  }

  Future<void> _doMove(DateTime? date) async {
    final todo = _detail?.todo;
    if (todo == null) return;
    final body = <String, dynamic>{
      'scheduled_date': date == null ? null : formatDateOnly(date),
      if (date == null) 'time': null,
      'due_at': date == null ? null : formatEndOfDayIso(date),
      if (todo.isFrog) ...{
        'is_frog': date != null,
        'frog_date': date == null ? null : formatDateOnly(date),
      },
    };
    await _updateTodo(body);
  }

  Future<void> _classifyLocalFirst(bool? important, bool? urgent) async {
    final todo = _detail?.todo;
    if (todo == null) return;
    if (todo.isFrog) {
      _showError('Frog luôn là việc quan trọng và khẩn cấp');
      return;
    }
    await _updateTodo({'is_important': important, 'is_urgent': urgent});
  }

  Future<void> _setFrogLocalFirst(bool value) async {
    final todo = _detail?.todo;
    if (todo == null) return;
    if (value && todo.scheduledDate == null) {
      _showError('Chọn ngày làm trước khi đặt Frog');
      return;
    }
    final body = value
        ? {
            'is_frog': true,
            'frog_date': formatDateOnly(todo.scheduledDate!),
            'is_important': true,
            'is_urgent': true,
          }
        : const {'is_frog': false, 'frog_date': null};
    final optimistic = _optimisticTodo(todo, body);
    _replaceTodo(optimistic);
    try {
      final localTodo = await TodosRepository.instance.setTodoFrogLocalFirst(
        todo,
        enabled: value,
        date: todo.scheduledDate,
      );
      _replaceTodo(localTodo);
    } on ApiException catch (e) {
      _rollbackTodo(todo);
      if (mounted) _showError(e.vnMessage);
    } catch (_) {
      _rollbackTodo(todo);
      if (mounted) _showError('Không thể cập nhật Frog');
    }
  }

  void _replaceTodo(Todo newTodo) {
    if (!mounted) return;
    setState(() {
      _selectedHabitId = newTodo.habitId;
      if (newTodo.habitId == null || _selectedHabit?.id != newTodo.habitId) {
        _selectedHabit = null;
      }
      _detail = TodoWithRelations(
        todo: newTodo,
        tags: _detail!.tags,
        subtasks: _detail!.subtasks,
        linkedNotes: _detail!.linkedNotes,
      );
    });
    _loadSelectedHabit(newTodo.habitId);
  }

  Future<void> _loadSelectedHabit(String? habitId) async {
    if (habitId == null) return;
    final habit = await HabitsRepository.instance.getLocalHabit(habitId);
    if (!mounted || _selectedHabitId != habitId) return;
    setState(() => _selectedHabit = habit);
  }

  Future<void> _pickTags() async {
    final detail = _detail;
    if (detail == null) return;
    final selected = await showTodoTagSelectorSheet(
      context,
      initialTags: detail.tags,
    );
    if (selected == null || !mounted) return;

    final previous = detail;
    final optimisticTodo = detail.todo.copyWith(
      tags: selected,
      tagIds: selected.map((tag) => tag.id).toList(),
      tagsLoaded: true,
    );
    setState(() {
      _detail = TodoWithRelations(
        todo: optimisticTodo,
        tags: selected,
        subtasks: detail.subtasks,
        linkedNotes: detail.linkedNotes,
      );
    });

    try {
      final saved = await TodosRepository.instance.replaceTagsLocalFirst(
        detail.todo.id,
        selected,
      );
      if (!mounted) return;
      setState(() {
        _detail = TodoWithRelations(
          todo: detail.todo.copyWith(
            tags: saved,
            tagIds: saved.map((tag) => tag.id).toList(),
            tagsLoaded: true,
          ),
          tags: saved,
          subtasks: detail.subtasks,
          linkedNotes: detail.linkedNotes,
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _detail = previous);
      _showError(e.vnMessage);
    }
  }

  void _rollbackTodo(Todo previous) {
    if (!mounted) return;
    _replaceTodo(previous);
  }

  Future<bool> _runOptimisticUpdate(
    Map<String, dynamic> body, {
    String? errorPrefix,
  }) async {
    final current = _detail?.todo;
    if (current == null) return false;
    final optimistic = _optimisticTodo(current, body);
    _replaceTodo(optimistic);

    try {
      final localTodo = await TodosRepository.instance.updateLocalFirst(
        current,
        body,
      );
      _replaceTodo(localTodo);
      return true;
    } on ApiException catch (e) {
      _rollbackTodo(current);
      if (mounted) {
        _showError(
          errorPrefix == null ? e.vnMessage : '$errorPrefix: ${e.vnMessage}',
        );
      }
      return false;
    } catch (_) {
      _rollbackTodo(current);
      if (mounted) {
        _showError(errorPrefix ?? 'Không thể lưu thay đổi cục bộ');
      }
      return false;
    }
  }

  Todo _optimisticTodo(Todo current, Map<String, dynamic> body) {
    final parentId = body.containsKey('parent_id')
        ? body['parent_id'] as String?
        : current.parentId;
    final scheduledDate = body.containsKey('scheduled_date')
        ? _dateOnlyFromBody(body['scheduled_date'])
        : current.scheduledDate;
    final time = parentId != null || scheduledDate == null
        ? null
        : body.containsKey('time')
        ? body['time'] as String?
        : current.time;
    final recurrenceType = body.containsKey('recurrence_type')
        ? body['recurrence_type'] as String?
        : current.recurrenceType;

    var isFrog = body.containsKey('is_frog')
        ? jsonBool(body['is_frog'])
        : current.isFrog;
    var frogDate = body.containsKey('frog_date')
        ? _dateOnlyFromBody(body['frog_date'])
        : current.frogDate;
    var isImportant = body.containsKey('is_important')
        ? jsonBoolNullable(body['is_important'])
        : current.isImportant;
    var isUrgent = body.containsKey('is_urgent')
        ? jsonBoolNullable(body['is_urgent'])
        : current.isUrgent;
    if (parentId != null || scheduledDate == null) {
      isFrog = false;
      frogDate = null;
    } else if (isFrog) {
      frogDate ??= scheduledDate;
      isImportant = true;
      isUrgent = true;
    } else {
      frogDate = null;
    }

    return Todo(
      id: current.id,
      parentId: parentId,
      title: body.containsKey('title')
          ? body['title'] as String? ?? current.title
          : current.title,
      description: body.containsKey('description')
          ? body['description'] as String?
          : current.description,
      status: body.containsKey('status')
          ? TodoStatus.parse(
              body['status'] as String? ?? current.status.backendValue,
            )
          : current.status,
      position: body.containsKey('position')
          ? (body['position'] as num?)?.toInt() ?? current.position
          : current.position,
      isFrog: isFrog,
      frogDate: frogDate,
      isImportant: isImportant,
      isUrgent: isUrgent,
      estimatedMinutes: body.containsKey('estimated_minutes')
          ? (body['estimated_minutes'] as num?)?.toInt()
          : current.estimatedMinutes,
      actualMinutes: current.actualMinutes,
      startAt: body.containsKey('start_at')
          ? _dateTimeFromBody(body['start_at'])
          : current.startAt,
      dueAt: body.containsKey('due_at')
          ? _dateTimeFromBody(body['due_at'])
          : current.dueAt,
      scheduledDate: scheduledDate,
      time: time,
      triggerAfterTodoId: body.containsKey('trigger_after_todo_id')
          ? body['trigger_after_todo_id'] as String?
          : current.triggerAfterTodoId,
      habitId: body.containsKey('habit_id')
          ? body['habit_id'] as String?
          : current.habitId,
      tags: current.tags,
      tagIds: current.tagIds,
      tagsLoaded: current.tagsLoaded,
      completedAt: current.completedAt,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toUtc(),
      recurrenceType: recurrenceType,
      recurrenceInterval: body.containsKey('recurrence_interval')
          ? (body['recurrence_interval'] as num?)?.toInt() ??
                current.recurrenceInterval
          : current.recurrenceInterval,
      recurrenceDaysOfWeek: body.containsKey('recurrence_days_of_week')
          ? body['recurrence_days_of_week'] as String?
          : current.recurrenceDaysOfWeek,
      recurrenceEndDate: body.containsKey('recurrence_end_date')
          ? body['recurrence_end_date'] as String?
          : current.recurrenceEndDate,
      recurrenceTemplateId: recurrenceType == null
          ? current.recurrenceTemplateId
          : current.recurrenceTemplateId,
    );
  }

  DateTime? _dateOnlyFromBody(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return AppDateUtils.dateOnly(value);
    return jsonDateOnlyNullable(value as String?);
  }

  DateTime? _dateTimeFromBody(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return jsonDateNullable(value as String?);
  }

  Future<void> _pickEstimate() async {
    const clearEstimate = -1;
    const customEstimate = -2;
    final selected = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Bỏ ước lượng'),
              onTap: () => Navigator.of(ctx).pop(clearEstimate),
            ),
            ...[15, 25, 45, 60].map((m) {
              return ListTile(
                leading: const Icon(Icons.hourglass_empty),
                title: Text('$m phút'),
                onTap: () => Navigator.of(ctx).pop(m),
              );
            }),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Tùy chỉnh'),
              subtitle: _detail?.todo.estimatedMinutes == null
                  ? null
                  : Text(
                      'Hiện tại: ${formatDurationMinutes(_detail!.todo.estimatedMinutes!)}',
                    ),
              onTap: () => Navigator.of(ctx).pop(customEstimate),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == customEstimate) {
      final custom = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => DurationPickerSheet(
          initialMinutes: _detail?.todo.estimatedMinutes ?? 25,
          title: 'Bạn muốn ước lượng bao nhiêu thời gian cho việc này?',
          actionLabel: 'Lưu',
          actionIcon: Icons.check_rounded,
        ),
      );
      if (custom == null || !mounted) return;
      await _updateTodo({'estimated_minutes': custom});
      return;
    }
    await _updateTodo({
      'estimated_minutes': selected == clearEstimate ? null : selected,
    });
  }

  Future<void> _pickTime() async {
    final todo = _detail?.todo;
    if (todo == null || todo.parentId != null) return;
    if (todo.scheduledDate == null) {
      _showError('Chọn ngày làm trước khi đặt giờ');
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: todo.time == null
          ? TimeOfDay.now()
          : _timeOfDayFromString(todo.time!),
    );
    if (picked == null || !mounted) return;
    await _updateTodo({'time': _formatTimeOfDay(picked)});
  }

  Future<void> _clearTime() async {
    final todo = _detail?.todo;
    if (todo == null || todo.parentId != null || todo.time == null) return;
    await _updateTodo({'time': null});
  }

  TimeOfDay _timeOfDayFromString(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTimeOfDay(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickRepeat() async {
    final todo = _detail?.todo;
    if (todo == null || todo.parentId != null) {
      return;
    }
    if (todo.isRecurrenceInstance) {
      await _openTemplateEditor(todo.recurrenceTemplateId!);
      return;
    }
    final result = await showRepeatPicker(
      context,
      initial: _repeatFromTodo(todo),
    );
    if (result == null || !mounted) return;

    final body = <String, dynamic>{
      'recurrence_type': result.type,
      'recurrence_interval': result.hasRepeat ? result.interval : null,
      'recurrence_days_of_week': result.hasRepeat ? result.daysOfWeek : null,
      'recurrence_end_date': result.hasRepeat ? result.endDate : null,
    };
    await _updateTodo(body);
  }

  Future<void> _openTemplateEditor(String templateId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TodoEditScreen(todoId: templateId)),
    );
    if (mounted) {
      final local = await TodosRepository.instance.getLocalDetail(
        widget.todoId,
      );
      if (!mounted) return;
      if (local != null) {
        setState(() => _detail = local);
      }
    }
  }

  RepeatSettings _repeatFromTodo(Todo todo) {
    if (!todo.isRecurrenceTemplate) return RepeatSettings.none;
    return RepeatSettings(
      type: todo.recurrenceType,
      interval: todo.recurrenceInterval,
      daysOfWeek: todo.recurrenceDaysOfWeek,
      endDate: todo.recurrenceEndDate,
    );
  }

  Future<void> _updateTodo(Map<String, dynamic> body) async {
    await _runOptimisticUpdate(body);
  }

  Future<void> _pickTriggerTodo() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    final picked = await showTodoTriggerPicker(context, excludeTodoId: todo.id);
    if (picked == null || !mounted) return;
    await _setTriggerTodo(picked.id, picked.title);
  }

  Future<void> _pickHabit() async {
    final selected = await showHabitSelectorSheet(
      context,
      selectedHabitId: _detail?.todo.habitId,
    );
    if (selected == null || !mounted) return;
    await _setHabit(selected.habit);
  }

  Future<void> _clearHabit() async {
    await _setHabit(null);
  }

  Future<void> _setHabit(Habit? habit) async {
    final previousHabit = _selectedHabit;
    final previousId = _selectedHabitId;
    setState(() {
      _selectedHabit = habit;
      _selectedHabitId = habit?.id;
    });
    final ok = await _runOptimisticUpdate({
      'habit_id': habit?.id,
    }, errorPrefix: 'Không thể cập nhật habit');
    if (!ok && mounted) {
      setState(() {
        _selectedHabit = previousHabit;
        _selectedHabitId = previousId;
      });
    }
  }

  Future<void> _clearTriggerTodo() async {
    await _setTriggerTodo(null, null);
  }

  Future<void> _setTriggerTodo(String? id, String? title) async {
    final previousTitle = _triggerTodoTitle;
    setState(() => _triggerTodoTitle = title);
    final ok = await _runOptimisticUpdate({
      'trigger_after_todo_id': id,
    }, errorPrefix: 'Không thể cập nhật việc nối tiếp');
    if (!ok && mounted) {
      setState(() => _triggerTodoTitle = previousTitle);
    }
  }

  Future<void> _toggleImportant() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    if (todo.isFrog) return;
    await _classifyLocalFirst(
      !(todo.isImportant == true),
      todo.isUrgent == true,
    );
  }

  Future<void> _toggleUrgent() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    if (todo.isFrog) return;
    await _classifyLocalFirst(
      todo.isImportant == true,
      !(todo.isUrgent == true),
    );
  }

  Future<void> _toggleFrog() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    await _setFrogLocalFirst(!todo.isFrog);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  Future<void> _saveSubtaskTitle() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showError('Vui lòng nhập tiêu đề');
      return;
    }
    final ok = await _runOptimisticUpdate({'title': title});
    if (ok && mounted) {
      Navigator.of(context).pop(_detail);
    }
  }

  Future<void> _saveTodoTitle() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showError('Vui lòng nhập tiêu đề');
      return;
    }
    if (title == todo.title) return;
    final ok = await _runOptimisticUpdate({'title': title});
    if (ok && mounted) {
      _titleCtrl.text = title;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã lưu tiêu đề')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Không tìm thấy todo')),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final todo = _detail!.todo;
    if (todo.parentId != null) {
      return _buildSubtaskEditor();
    }
    final qInfo = QuadrantUtils.info(
      QuadrantUtils.from(important: todo.isImportant, urgent: todo.isUrgent),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _titleCtrl,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: 'Tiêu đề todo',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_rounded),
                    tooltip: 'Lưu tiêu đề',
                    onPressed: _saveTodoTitle,
                  ),
                ),
                onSubmitted: (_) => _saveTodoTitle(),
              ),
            ),
            if (todo.description != null && todo.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  todo.description!,
                  style: TextStyle(fontSize: 15, color: secondary, height: 1.4),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _badge(todo.status.label, AppColors.primary),
                  _badge(qInfo.label, qInfo.color),
                  if (todo.isFrog) _badge('🐸 Frog', AppColors.frog),
                  if (todo.estimatedMinutes != null)
                    _badge(
                      formatDurationMinutes(todo.estimatedMinutes!),
                      secondary,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _PriorityFlagsPanel(
              todo: todo,
              qInfo: qInfo,
              onToggleFrog: _toggleFrog,
              onToggleImportant: todo.isFrog ? null : _toggleImportant,
              onToggleUrgent: todo.isFrog ? null : _toggleUrgent,
            ),
            const SizedBox(height: 8),
            _MetaList(
              todo: todo,
              tags: _detail!.tags,
              secondary: secondary,
              onMoveToDay: _moveToDay,
              onPickTime: _pickTime,
              onClearTime: _clearTime,
              onPickEstimate: _pickEstimate,
              onPickRepeat: _pickRepeat,
              triggerTodoTitle: _triggerTodoTitle,
              onPickTriggerTodo: _pickTriggerTodo,
              onClearTriggerTodo: _clearTriggerTodo,
              onPickTags: _pickTags,
              selectedHabit: _selectedHabit,
              selectedHabitId: _selectedHabitId,
              onPickHabit: _pickHabit,
              onClearHabit: _clearHabit,
            ),
            const SectionHeader(label: 'Note liên quan'),
            if (_detail!.linkedNotes.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Chưa có note liên kết',
                  style: TextStyle(color: secondary),
                ),
              )
            else
              ..._detail!.linkedNotes.map(
                (n) => ListTile(
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: Text(
                    n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mở note (TODO)')),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtaskEditor() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Việc con'),
        actions: [
          TextButton(
            onPressed: _saveSubtaskTitle,
            child: const Text(
              'Lưu',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: 'Tiêu đề việc con',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _saveSubtaskTitle(),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PriorityFlagsPanel extends StatelessWidget {
  final Todo todo;
  final QuadrantInfo qInfo;
  final VoidCallback onToggleFrog;
  final VoidCallback? onToggleImportant;
  final VoidCallback? onToggleUrgent;

  const _PriorityFlagsPanel({
    required this.todo,
    required this.qInfo,
    required this.onToggleFrog,
    required this.onToggleImportant,
    required this.onToggleUrgent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TodoFlagButton(
                  selected: todo.isFrog,
                  selectedColor: AppColors.frog,
                  label: 'Frog',
                  emoji: '🐸',
                  onTap: onToggleFrog,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TodoFlagButton(
                  selected: todo.isImportant == true,
                  selectedColor: const Color(0xFFB91C1C),
                  label: 'Quan trọng',
                  icon: Icons.star_rounded,
                  onTap: onToggleImportant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TodoFlagButton(
                  selected: todo.isUrgent == true,
                  selectedColor: AppColors.warning,
                  selectedForeground: AppColors.textPrimary,
                  label: 'Khẩn cấp',
                  icon: Icons.bolt_rounded,
                  onTap: onToggleUrgent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: qInfo.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${qInfo.label} → ${qInfo.action}',
              style: TextStyle(
                fontSize: 12,
                color: qInfo.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaList extends StatelessWidget {
  final Todo todo;
  final List<Tag> tags;
  final Color secondary;
  final Habit? selectedHabit;
  final String? selectedHabitId;
  final VoidCallback onMoveToDay;
  final VoidCallback onPickTime;
  final VoidCallback onClearTime;
  final VoidCallback onPickEstimate;
  final VoidCallback onPickRepeat;
  final String? triggerTodoTitle;
  final VoidCallback onPickTriggerTodo;
  final VoidCallback onClearTriggerTodo;
  final VoidCallback onPickTags;
  final VoidCallback onPickHabit;
  final VoidCallback onClearHabit;
  const _MetaList({
    required this.todo,
    required this.tags,
    required this.secondary,
    required this.selectedHabit,
    required this.selectedHabitId,
    required this.onMoveToDay,
    required this.onPickTime,
    required this.onClearTime,
    required this.onPickEstimate,
    required this.onPickRepeat,
    required this.triggerTodoTitle,
    required this.onPickTriggerTodo,
    required this.onClearTriggerTodo,
    required this.onPickTags,
    required this.onPickHabit,
    required this.onClearHabit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.calendar_today, size: 20),
          title: const Text('Ngày làm'),
          subtitle: Text(
            todo.scheduledDate == null
                ? 'Chưa chọn (floating)'
                : AppDateUtils.formatDate(todo.scheduledDate!),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: onMoveToDay,
          ),
        ),
        if (todo.parentId == null)
          ListTile(
            enabled: todo.scheduledDate != null,
            leading: Icon(
              Icons.schedule,
              size: 20,
              color: todo.time == null ? null : AppColors.primary,
            ),
            title: const Text('Giờ nhắc'),
            subtitle: Text(
              todo.scheduledDate == null
                  ? 'Chọn ngày làm trước'
                  : todo.time ?? 'Không đặt giờ',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (todo.time != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Bỏ giờ nhắc',
                    onPressed: onClearTime,
                  ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Chọn giờ',
                  onPressed: todo.scheduledDate == null ? null : onPickTime,
                ),
              ],
            ),
            onTap: todo.scheduledDate == null ? null : onPickTime,
          ),
        ListTile(
          leading: const Icon(Icons.hourglass_empty, size: 20),
          title: const Text('Ước lượng'),
          subtitle: Text(
            todo.estimatedMinutes == null
                ? 'Chưa chọn'
                : formatDurationMinutes(todo.estimatedMinutes!),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: onPickEstimate,
          ),
          onTap: onPickEstimate,
        ),
        if (todo.parentId == null)
          ListTile(
            leading: Icon(Icons.repeat, size: 20, color: AppColors.primary),
            title: const Text('Lặp lại'),
            subtitle: Text(
              todo.isRecurrenceInstance
                  ? 'Theo lịch lặp gốc'
                  : todo.isRecurrenceTemplate
                  ? todo.recurrenceLabel
                  : 'Không lặp lại',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: onPickRepeat,
            ),
            onTap: onPickRepeat,
          ),
        ListTile(
          leading: const Icon(Icons.account_tree_outlined, size: 20),
          title: const Text('Làm sau khi hoàn thành...'),
          subtitle: Text(
            todo.triggerAfterTodoId == null
                ? 'Không có'
                : triggerTodoTitle ?? 'Đã chọn việc trigger',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (todo.triggerAfterTodoId != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Bỏ liên kết',
                  onPressed: onClearTriggerTodo,
                ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                tooltip: 'Chọn việc',
                onPressed: onPickTriggerTodo,
              ),
            ],
          ),
          onTap: onPickTriggerTodo,
        ),
        ListTile(
          leading: const Icon(Icons.local_offer_outlined, size: 20),
          title: tags.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: const Icon(Icons.local_offer_outlined, size: 16),
                    label: const Text('Chọn tag'),
                    onPressed: onPickTags,
                  ),
                )
              : TodoTagWrap(tags: tags),
          trailing: tags.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: onPickTags,
                ),
          onTap: onPickTags,
        ),
        ListTile(
          leading: Icon(
            selectedHabit?.icon ?? Icons.flag_outlined,
            size: 20,
            color: selectedHabit?.color,
          ),
          title: const Text('Habit liên kết'),
          subtitle: Text(
            selectedHabitId == null
                ? 'Không liên kết'
                : selectedHabit?.title ?? 'Habit liên kết',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedHabitId != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Bỏ liên kết',
                  onPressed: onClearHabit,
                ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                tooltip: 'Chọn habit',
                onPressed: onPickHabit,
              ),
            ],
          ),
          onTap: onPickHabit,
        ),
      ],
    );
  }
}
