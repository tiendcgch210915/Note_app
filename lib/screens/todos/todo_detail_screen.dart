import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/habit_stacking_dialog.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import 'todo_create_screen.dart';
import 'todo_edit_screen.dart';

/// TodoDetailScreen — màn hình "xem" đơn giản:
/// - Top: checkbox tròn + tiêu đề chỉnh sửa inline
/// - Section "Việc con": list subtask có inline-edit title + nút ">" mở chi tiết
/// - Nút "+ Thêm việc con"
/// - Bottom: Hoàn thành / Mở lại
///
/// Các thông tin meta (ngày làm, hạn, classify, frog, tags, note...) chuyển
/// sang TodoEditScreen — truy cập qua nút bút chì trên AppBar.
class TodoDetailScreen extends StatefulWidget {
  final String todoId;
  const TodoDetailScreen({super.key, required this.todoId});

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  TodoWithRelations? _detail;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail = await TodosRepository.instance.getDetail(widget.todoId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleComplete() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    try {
      if (todo.isDone) {
        await TodosRepository.instance.uncomplete(todo.id);
        _load();
      } else {
        final res = await TodosRepository.instance.complete(todo.id);
        if (!mounted) return;
        await showHabitStackingDialog(context, res.triggeredTodos, (t) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: t.id)),
          );
        });
        _load();
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _toggleSubtaskComplete(Todo subtask) async {
    try {
      if (subtask.isDone) {
        await TodosRepository.instance.uncomplete(subtask.id);
      } else {
        await TodosRepository.instance.complete(subtask.id);
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _saveTitle(String todoId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    try {
      await TodosRepository.instance.update(todoId, {'title': trimmed});
      // Cập nhật state local mà không re-fetch full để giữ focus mượt hơn
      if (todoId == widget.todoId) {
        _load();
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _confirmDelete() async {
    final todo = _detail?.todo;
    if (todo == null) return;

    // Recurring instance: show scope selector
    if (todo.isRecurrenceInstance) {
      await _confirmDeleteRecurring(todo);
      return;
    }
    // Recurring template: offer delete-all or just this
    if (todo.isRecurrenceTemplate) {
      await _confirmDeleteTemplate(todo);
      return;
    }

    // Non-recurring: simple confirm
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa việc?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await TodosRepository.instance.delete(widget.todoId);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  /// Scope picker for recurring instances.
  Future<void> _confirmDeleteRecurring(Todo todo) async {
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa lịch lặp?'),
        content: const Text('Chọn phạm vi xóa:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('this'),
            child: const Text('Lần này thôi'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('future'),
            child: const Text('Lần này và sau'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('all'),
            child: const Text('Tất cả',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;
    try {
      if (scope == 'this') {
        await TodosRepository.instance.delete(widget.todoId);
      } else if (scope == 'future') {
        await TodosRepository.instance.deleteFutureAndThis(
          widget.todoId,
          todo.recurrenceTemplateId!,
        );
      } else {
        await TodosRepository.instance
            .deleteAllRecurrences(todo.recurrenceTemplateId!);
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Đã xóa')));
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  /// Scope picker when deleting a template directly.
  Future<void> _confirmDeleteTemplate(Todo todo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa lịch lặp?'),
        content: const Text(
            'Xóa template sẽ xóa tất cả các lần lặp chưa hoàn thành.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa tất cả',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await TodosRepository.instance.deleteAllRecurrences(todo.id);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Đã xóa')));
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TodoEditScreen(todoId: widget.todoId),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _addSubtask() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TodoCreateScreen(parentId: widget.todoId),
      ),
    );
    if (created == true) _load();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
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
    final todo = _detail!.todo;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: Text(todo.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Chỉnh sửa',
            onPressed: _openEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Xóa',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // Top: checkbox + editable title
            _TitleRow(
              todo: todo,
              onToggle: _toggleComplete,
              onSave: (newTitle) => _saveTitle(todo.id, newTitle),
            ),
            const Divider(height: 1),
            const SectionHeader(label: 'Việc con'),
            if (_detail!.subtasks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Chưa có việc con',
                  style: TextStyle(color: secondary),
                ),
              )
            else
              ..._detail!.subtasks.map((s) => _SubtaskRow(
                    subtask: s,
                    onToggle: () => _toggleSubtaskComplete(s),
                    onSaveTitle: (newTitle) => _saveTitle(s.id, newTitle),
                    onOpenDetail: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TodoDetailScreen(todoId: s.id),
                        ),
                      );
                      if (mounted) _load();
                    },
                  )),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: _addSubtask,
                icon: const Icon(Icons.add),
                label: const Text('Thêm việc con'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(
            label: todo.isDone ? 'Mở lại' : 'Hoàn thành',
            icon: todo.isDone ? Icons.refresh : Icons.check,
            onPressed: _toggleComplete,
          ),
        ),
      ),
    );
  }
}

/// Hàng tiêu đề ở đầu màn hình — checkbox tròn + TextField inline editable.
class _TitleRow extends StatelessWidget {
  final Todo todo;
  final VoidCallback onToggle;
  final Future<void> Function(String) onSave;

  const _TitleRow({
    required this.todo,
    required this.onToggle,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: onToggle,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                todo.isDone
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 28,
                color: todo.isDone ? AppColors.primary : textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _InlineEditableTitle(
              key: ValueKey('title_${todo.id}_${todo.title}'),
              initial: todo.title,
              done: todo.isDone,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onSave: onSave,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hàng việc con — checkbox + tiêu đề inline edit + nút ">" mở chi tiết.
class _SubtaskRow extends StatelessWidget {
  final Todo subtask;
  final VoidCallback onToggle;
  final Future<void> Function(String) onSaveTitle;
  final VoidCallback onOpenDetail;

  const _SubtaskRow({
    required this.subtask,
    required this.onToggle,
    required this.onSaveTitle,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: onToggle,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                subtask.isDone
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 22,
                color: subtask.isDone ? AppColors.primary : textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _InlineEditableTitle(
                key: ValueKey('subtask_${subtask.id}_${subtask.title}'),
                initial: subtask.title,
                done: subtask.isDone,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                onSave: onSaveTitle,
              ),
            ),
          ),
          // Chevron với vùng nhấn rộng để dễ tap mở chi tiết
          InkWell(
            onTap: onOpenDetail,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Icon(Icons.chevron_right, size: 22, color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// TextField không khung — hiển thị như text thường, tap để edit, blur để save.
class _InlineEditableTitle extends StatefulWidget {
  final String initial;
  final bool done;
  final double fontSize;
  final FontWeight fontWeight;
  final Color textPrimary;
  final Color textSecondary;
  final Future<void> Function(String) onSave;

  const _InlineEditableTitle({
    super.key,
    required this.initial,
    required this.done,
    required this.fontSize,
    required this.fontWeight,
    required this.textPrimary,
    required this.textSecondary,
    required this.onSave,
  });

  @override
  State<_InlineEditableTitle> createState() => _InlineEditableTitleState();
}

class _InlineEditableTitleState extends State<_InlineEditableTitle> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  late final FocusNode _focus = FocusNode();
  late String _lastSaved = widget.initial;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      final current = _ctrl.text.trim();
      if (current.isNotEmpty && current != _lastSaved) {
        _lastSaved = current;
        widget.onSave(current);
      } else if (current.isEmpty) {
        // Revert nếu xóa hết — backend không cho title rỗng
        _ctrl.text = _lastSaved;
      }
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      maxLines: null,
      textInputAction: TextInputAction.done,
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: widget.fontWeight,
        color: widget.done ? widget.textSecondary : widget.textPrimary,
        decoration: widget.done ? TextDecoration.lineThrough : null,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.symmetric(vertical: 4),
        isDense: true,
      ),
      onSubmitted: (_) => _focus.unfocus(),
    );
  }
}
