import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/json_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../utils/todo_trigger_picker.dart';
import '../../widgets/duration_picker_sheet.dart';
import '../../widgets/repeat_picker_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/todo_flag_button.dart';

/// Màn hình "chỉnh sửa" — chỉnh tất cả properties của todo:
/// meta (ngày làm, hạn chót, ước lượng), classify Eisenhower, frog, tags,
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
          _triggerTodoTitle = null;
        });
      }
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
      setState(() {
        _detail = detail;
        _titleCtrl.text = detail.todo.title;
        _triggerTodoTitle = triggerTitle;
      });
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
      if (todo.isFrog) 'frog_date': date == null ? null : formatDateOnly(date),
    };
    await _updateTodo(body);
  }

  Future<void> _classifyLocalFirst(bool? important, bool? urgent) async {
    final todo = _detail?.todo;
    if (todo == null) return;
    await _updateTodo({'is_important': important, 'is_urgent': urgent});
  }

  Future<void> _setFrogLocalFirst(bool value) async {
    final todo = _detail?.todo;
    if (todo == null) return;
    final date = todo.scheduledDate ?? DateTime.now();
    await _updateTodo({
      'is_frog': value,
      'frog_date': value ? formatDateOnly(date) : null,
    });
  }

  void _replaceTodo(Todo newTodo) {
    if (!mounted) return;
    setState(() {
      _detail = TodoWithRelations(
        todo: newTodo,
        tags: _detail!.tags,
        subtasks: _detail!.subtasks,
        linkedNotes: _detail!.linkedNotes,
      );
    });
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

  Future<void> _pickRepeat() async {
    final todo = _detail?.todo;
    if (todo == null || todo.parentId != null || todo.isRecurrenceInstance) {
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
    await _classifyLocalFirst(
      !(todo.isImportant == true),
      todo.isUrgent == true,
    );
  }

  Future<void> _toggleUrgent() async {
    final todo = _detail?.todo;
    if (todo == null) return;
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
      Navigator.of(context).pop(true);
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
              child: Text(
                todo.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
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
              onToggleImportant: _toggleImportant,
              onToggleUrgent: _toggleUrgent,
            ),
            const SizedBox(height: 8),
            _MetaList(
              todo: todo,
              tags: _detail!.tags,
              secondary: secondary,
              onMoveToDay: _moveToDay,
              onPickEstimate: _pickEstimate,
              onPickRepeat: _pickRepeat,
              triggerTodoTitle: _triggerTodoTitle,
              onPickTriggerTodo: _pickTriggerTodo,
              onClearTriggerTodo: _clearTriggerTodo,
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
  final VoidCallback onToggleImportant;
  final VoidCallback onToggleUrgent;

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
  final List tags;
  final Color secondary;
  final VoidCallback onMoveToDay;
  final VoidCallback onPickEstimate;
  final VoidCallback onPickRepeat;
  final String? triggerTodoTitle;
  final VoidCallback onPickTriggerTodo;
  final VoidCallback onClearTriggerTodo;
  const _MetaList({
    required this.todo,
    required this.tags,
    required this.secondary,
    required this.onMoveToDay,
    required this.onPickEstimate,
    required this.onPickRepeat,
    required this.triggerTodoTitle,
    required this.onPickTriggerTodo,
    required this.onClearTriggerTodo,
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
        if (todo.dueAt != null)
          ListTile(
            leading: const Icon(Icons.access_time, size: 20),
            title: Text(
              'Hạn chót: ${AppDateUtils.formatDate(todo.dueAt!)} ${AppDateUtils.formatTime(todo.dueAt!)}',
            ),
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
                  ? 'Instance của lịch lặp'
                  : todo.isRecurrenceTemplate
                  ? todo.recurrenceLabel
                  : 'Không lặp lại',
            ),
            trailing: todo.isRecurrenceInstance
                ? null
                : IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: onPickRepeat,
                  ),
            onTap: todo.isRecurrenceInstance ? null : onPickRepeat,
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
        if (tags.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.local_offer_outlined, size: 20),
            title: Wrap(
              spacing: 6,
              children: tags.map<Widget>((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tag.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tag.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: tag.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
