import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../data/todos_repository.dart';
import '../../models/habit.dart';
import '../../models/tag.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_snack.dart';
import '../../utils/date_utils.dart';
import '../../utils/json_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../utils/todo_trigger_picker.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/duration_picker_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/habit_selector_sheet.dart';
import '../../widgets/repeat_picker_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tag_chip.dart';
import '../../widgets/todo_flag_button.dart';
import '../../widgets/todo_tag_selector_sheet.dart';
import '../notes/note_detail_screen.dart';

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

  /// Bắt đầu = true để khung đầu tiên hiện spinner thay vì nháy chữ
  /// "Không tìm thấy todo" trước khi dữ liệu kịp tải.
  bool _loading = true;

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
    final action = await showAppSheet<String>(
      context: context,
      builder: (ctx) => AppSheetScaffold(
        title: 'Ngày làm',
        child: AppListSection(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          dividerIndent: AppListSection.iconIndent,
          children: [
            AppListTile(
              icon: Icons.calendar_today_rounded,
              title: 'Đổi ngày',
              showChevron: false,
              onTap: () => Navigator.of(ctx).pop('pick'),
            ),
            if (todo.scheduledDate != null)
              AppListTile(
                icon: Icons.event_busy_rounded,
                title: 'Bỏ ngày (floating)',
                destructive: true,
                showChevron: false,
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
    final currentEstimate = _detail?.todo.estimatedMinutes;
    final selected = await showAppSheet<int?>(
      context: context,
      builder: (ctx) => AppSheetScaffold(
        title: 'Ước lượng thời gian',
        child: AppListSection(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          dividerIndent: AppListSection.iconIndent,
          children: [
            ...[15, 25, 45, 60].map((m) {
              return AppListTile(
                icon: Icons.hourglass_empty_rounded,
                iconColor: AppColors.tagAmber,
                title: '$m phút',
                showChevron: false,
                trailing: currentEstimate == m
                    ? Icon(Icons.check_rounded, color: ctx.appPrimary, size: 22)
                    : null,
                onTap: () => Navigator.of(ctx).pop(m),
              );
            }),
            AppListTile(
              icon: Icons.tune_rounded,
              iconColor: AppColors.tagPurple,
              title: 'Tùy chỉnh',
              subtitle: currentEstimate == null
                  ? null
                  : 'Hiện tại: ${formatDurationMinutes(currentEstimate)}',
              onTap: () => Navigator.of(ctx).pop(customEstimate),
            ),
            if (currentEstimate != null)
              AppListTile(
                icon: Icons.close_rounded,
                title: 'Bỏ ước lượng',
                destructive: true,
                showChevron: false,
                onTap: () => Navigator.of(ctx).pop(clearEstimate),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == customEstimate) {
      final custom = await showAppSheet<int>(
        context: context,
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
    showAppSnack(context, msg, isError: true);
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
      return Scaffold(appBar: AppBar(), body: const AppSpinner());
    }
    if (_detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Không tìm thấy todo',
        ),
      );
    }
    final secondary = context.appTextSecondary;
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
                  _badge(todo.status.label, context.appPrimary),
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
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                child: Text(
                  'Chưa có note liên kết',
                  style: TextStyle(color: secondary),
                ),
              )
            else
              AppListSection(
                dividerIndent: AppListSection.iconIndent,
                children: [
                  for (final n in _detail!.linkedNotes)
                    AppListTile(
                      icon: Icons.sticky_note_2_rounded,
                      iconColor: AppColors.tagAmber,
                      title: n.title,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NoteDetailScreen(noteId: n.id),
                        ),
                      ),
                    ),
                ],
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
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
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
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.15),
        shape: AppShape.pill,
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
            decoration: ShapeDecoration(
              color: qInfo.color.withValues(alpha: 0.15),
              shape: AppShape.pill,
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
    final primary = context.appPrimary;
    final hasDate = todo.scheduledDate != null;
    return AppListSection(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      dividerIndent: AppListSection.iconIndent,
      children: [
        AppListTile(
          icon: Icons.calendar_today_rounded,
          title: 'Ngày làm',
          value: todo.scheduledDate == null
              ? 'Chưa chọn (floating)'
              : AppDateUtils.formatDate(todo.scheduledDate!),
          onTap: onMoveToDay,
        ),
        if (todo.parentId == null)
          Opacity(
            opacity: hasDate ? 1 : 0.5,
            child: AppListTile(
              icon: Icons.schedule_rounded,
              iconColor: todo.time == null ? AppColors.tagSlate : primary,
              title: 'Giờ nhắc',
              value: !hasDate
                  ? 'Chọn ngày làm trước'
                  : todo.time ?? 'Không đặt giờ',
              trailing: todo.time == null
                  ? null
                  : AppClearButton(tooltip: 'Bỏ giờ nhắc', onTap: onClearTime),
              showChevron: hasDate && todo.time == null,
              onTap: hasDate ? onPickTime : null,
            ),
          ),
        AppListTile(
          icon: Icons.hourglass_empty_rounded,
          iconColor: AppColors.tagAmber,
          title: 'Ước lượng',
          value: todo.estimatedMinutes == null
              ? 'Chưa chọn'
              : formatDurationMinutes(todo.estimatedMinutes!),
          onTap: onPickEstimate,
        ),
        if (todo.parentId == null)
          AppListTile(
            icon: Icons.repeat_rounded,
            iconColor: primary,
            title: 'Lặp lại',
            value: todo.repeatRowValue,
            onTap: onPickRepeat,
          ),
        AppListTile(
          icon: Icons.account_tree_rounded,
          iconColor: AppColors.tagCyan,
          title: 'Làm sau khi hoàn thành...',
          value: todo.triggerAfterTodoId == null
              ? 'Không có'
              : triggerTodoTitle ?? 'Đã chọn việc trigger',
          trailing: todo.triggerAfterTodoId == null
              ? null
              : AppClearButton(
                  tooltip: 'Bỏ liên kết',
                  onTap: onClearTriggerTodo,
                ),
          showChevron: todo.triggerAfterTodoId == null,
          onTap: onPickTriggerTodo,
        ),
        AppListTile(
          icon: Icons.local_offer_rounded,
          iconColor: AppColors.tagPink,
          title: 'Tags',
          value: tags.isEmpty ? 'Chọn tag' : '${tags.length} tag',
          onTap: onPickTags,
        ),
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TodoTagWrap(tags: tags),
            ),
          ),
        AppListTile(
          icon: selectedHabit?.icon ?? Icons.flag_rounded,
          iconColor: selectedHabit?.color ?? AppColors.tagSlate,
          title: 'Habit liên kết',
          value: selectedHabitId == null
              ? 'Không liên kết'
              : selectedHabit?.title ?? 'Habit liên kết',
          trailing: selectedHabitId == null
              ? null
              : AppClearButton(tooltip: 'Bỏ liên kết', onTap: onClearHabit),
          showChevron: selectedHabitId == null,
          onTap: onPickHabit,
        ),
      ],
    );
  }
}
