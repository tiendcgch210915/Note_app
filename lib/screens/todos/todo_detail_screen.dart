import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/habit_stacking_dialog.dart';
import '../../widgets/duration_picker_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
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
  final _draftSubtaskKey = GlobalKey<_DraftSubtaskRowState>();
  bool _loading = false;
  bool _celebrating = false;
  bool _draftingSubtask = false;
  bool _savingDraftSubtask = false;
  bool _queueNextDraftAfterSave = false;
  int _celebrationSeed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_detail == null) {
      final local = await TodosRepository.instance.getLocalDetail(
        widget.todoId,
      );
      if (!mounted) return;
      if (local != null) {
        setState(() => _detail = local);
      }
    }
    setState(() => _loading = true);
    try {
      final detail = await TodosRepository.instance.getDetail(widget.todoId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_detail == null || e.code != 'no_connection') {
        _showError(e.vnMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleComplete() async {
    final detail = _detail;
    final todo = detail?.todo;
    if (detail == null || todo == null) return;
    try {
      if (todo.isDone) {
        final reopened = await TodosRepository.instance.uncompleteLocalFirst(
          todo,
        );
        if (!mounted) return;
        setState(() => _detail = _detailWith(todo: reopened));
      } else {
        final res = await TodosRepository.instance.completeLocalFirst(todo);
        if (!mounted) return;
        setState(() => _detail = _detailWith(todo: res.todo));
        await showHabitStackingDialog(context, res.triggeredTodos, (t) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: t.id)),
          );
        });
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _toggleSubtaskComplete(Todo subtask) async {
    try {
      if (subtask.isDone) {
        final reopened = await TodosRepository.instance.uncompleteLocalFirst(
          subtask,
        );
        if (!mounted) return;
        setState(() => _replaceSubtask(reopened));
      } else {
        final res = await TodosRepository.instance.completeLocalFirst(subtask);
        if (!mounted) return;
        setState(() => _replaceSubtask(res.todo));
        await showHabitStackingDialog(context, res.triggeredTodos, (t) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: t.id)),
          );
        });
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _saveTitle(String todoId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final current = _findTodo(todoId);
    if (current == null || current.title == trimmed) return;
    try {
      final updated = await TodosRepository.instance.updateLocalFirst(current, {
        'title': trimmed,
      });
      if (!mounted) return;
      setState(() {
        if (updated.id == _detail!.todo.id) {
          _detail = _detailWith(todo: updated);
        } else {
          _replaceSubtask(updated);
        }
      });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xóa')));
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
            child: const Text(
              'Tất cả',
              style: TextStyle(color: AppColors.danger),
            ),
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
        await TodosRepository.instance.deleteAllRecurrences(
          todo.recurrenceTemplateId!,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xóa')));
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
          'Xóa template sẽ xóa tất cả các lần lặp chưa hoàn thành.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Xóa tất cả',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await TodosRepository.instance.deleteAllRecurrences(todo.id);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xóa')));
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TodoEditScreen(todoId: widget.todoId)),
    );
    if (mounted) _load();
  }

  Future<void> _startFocus() async {
    final detail = _detail;
    if (detail == null || detail.todo.isDone) return;
    var focusMinutes = detail.todo.estimatedMinutes;
    if (focusMinutes == null || focusMinutes <= 0) {
      focusMinutes = await _pickFocusDuration();
      if (focusMinutes == null || focusMinutes <= 0) return;
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<_TodoFocusResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TodoFocusScreen(
          detail: detail,
          focusDuration: Duration(minutes: focusMinutes!),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _detail = _detailWith(todo: result.todo, subtasks: result.subtasks);
    });
    if (result.completedAll) {
      _showCelebration();
    }
    if (result.triggeredTodos.isNotEmpty && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      await showHabitStackingDialog(context, result.triggeredTodos, (t) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: t.id)),
        );
      });
    }
  }

  Future<int?> _pickFocusDuration() {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const DurationPickerSheet(),
    );
  }

  void _showCelebration() {
    setState(() {
      _celebrationSeed++;
      _celebrating = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  TodoWithRelations _detailWith({Todo? todo, List<Todo>? subtasks}) {
    final current = _detail!;
    return TodoWithRelations(
      todo: todo ?? current.todo,
      tags: current.tags,
      subtasks: subtasks ?? current.subtasks,
      linkedNotes: current.linkedNotes,
    );
  }

  Todo? _findTodo(String id) {
    final detail = _detail;
    if (detail == null) return null;
    if (detail.todo.id == id) return detail.todo;
    for (final subtask in detail.subtasks) {
      if (subtask.id == id) return subtask;
    }
    return null;
  }

  void _replaceSubtask(Todo updated) {
    _detail = _detailWith(
      subtasks: [
        for (final subtask in _detail!.subtasks)
          if (subtask.id == updated.id) updated else subtask,
      ],
    );
  }

  Future<void> _addSubtask() async {
    if (_draftingSubtask) {
      if (_savingDraftSubtask) return;
      final draftState = _draftSubtaskKey.currentState;
      final title = draftState?.draftTitle ?? '';
      if (title.isEmpty) {
        draftState?.focus();
        return;
      }
      _queueNextDraftAfterSave = true;
      await _commitDraftSubtask(title);
      return;
    }
    setState(() => _draftingSubtask = true);
  }

  Future<void> _commitDraftSubtask(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || _savingDraftSubtask) return;
    setState(() => _savingDraftSubtask = true);
    try {
      final result = await TodosRepository.instance.createLocalFirst({
        'title': trimmed,
        'parent_id': widget.todoId,
      });
      if (!mounted) return;
      final keepDrafting = _queueNextDraftAfterSave;
      _queueNextDraftAfterSave = false;
      setState(() {
        final subtasks = [..._detail!.subtasks, result.todo]
          ..sort((a, b) => a.position.compareTo(b.position));
        _detail = _detailWith(subtasks: subtasks);
        _draftingSubtask = keepDrafting;
        _savingDraftSubtask = false;
      });
      if (keepDrafting) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _draftSubtaskKey.currentState?.resetForNext();
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _queueNextDraftAfterSave = false;
      setState(() {
        _draftingSubtask = false;
        _savingDraftSubtask = false;
      });
      _showError(e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      _queueNextDraftAfterSave = false;
      setState(() {
        _draftingSubtask = false;
        _savingDraftSubtask = false;
      });
      _showError('Không thể thêm việc con');
    }
  }

  void _cancelDraftSubtask() {
    if (!_draftingSubtask || _savingDraftSubtask) return;
    setState(() => _draftingSubtask = false);
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
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

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
      body: Stack(
        children: [
          RefreshIndicator(
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
                if (_detail!.subtasks.isEmpty && !_draftingSubtask)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'Chưa có việc con',
                      style: TextStyle(color: secondary),
                    ),
                  )
                else
                  ..._detail!.subtasks.map(
                    (s) => _SubtaskRow(
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
                    ),
                  ),
                if (_draftingSubtask)
                  _DraftSubtaskRow(
                    key: _draftSubtaskKey,
                    saving: _savingDraftSubtask,
                    onCommit: _commitDraftSubtask,
                    onCancel: _cancelDraftSubtask,
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Listener(
                    onPointerDown: (_) {
                      if (!_draftingSubtask || _savingDraftSubtask) return;
                      final title =
                          _draftSubtaskKey.currentState?.draftTitle ?? '';
                      if (title.isNotEmpty) {
                        _queueNextDraftAfterSave = true;
                      }
                    },
                    child: OutlinedButton.icon(
                      onPressed: _addSubtask,
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm việc con'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_celebrating)
            Positioned.fill(
              child: IgnorePointer(
                child: _CelebrationOverlay(seed: _celebrationSeed),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(
            label: todo.isDone ? 'Đã hoàn thành' : 'Bắt đầu',
            icon: todo.isDone ? Icons.check_circle : Icons.play_arrow_rounded,
            onPressed: todo.isDone ? null : _startFocus,
          ),
        ),
      ),
    );
  }
}

class _TodoFocusResult {
  final Todo todo;
  final List<Todo> subtasks;
  final List<Todo> triggeredTodos;
  final bool completedAll;

  const _TodoFocusResult({
    required this.todo,
    required this.subtasks,
    required this.triggeredTodos,
    required this.completedAll,
  });
}

class _TodoFocusScreen extends StatefulWidget {
  final TodoWithRelations detail;
  final Duration focusDuration;

  const _TodoFocusScreen({required this.detail, required this.focusDuration});

  @override
  State<_TodoFocusScreen> createState() => _TodoFocusScreenState();
}

class _TodoFocusScreenState extends State<_TodoFocusScreen> {
  late Todo _todo = widget.detail.todo;
  late List<Todo> _subtasks = [...widget.detail.subtasks];
  late Duration _remaining = widget.focusDuration;
  final List<Todo> _triggeredTodos = [];
  Timer? _timer;
  bool _completing = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentTask == null) {
        _completeParentAndExit();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Todo? get _currentTask {
    if (_subtasks.isEmpty) return _todo.isDone ? null : _todo;
    for (final subtask in _subtasks) {
      if (!subtask.isDone) return subtask;
    }
    return _todo.isDone ? null : _todo;
  }

  List<Todo> get _pendingSubtasks =>
      _subtasks.where((subtask) => !subtask.isDone).toList();

  List<Todo> _nextSubtasksAfter(Todo current) {
    final pending = _pendingSubtasks;
    final currentIndex = pending.indexWhere(
      (subtask) => subtask.id == current.id,
    );
    if (currentIndex < 0) return const [];
    return pending.skip(currentIndex + 1).toList();
  }

  void _tick(Timer timer) {
    if (_remaining <= Duration.zero) {
      timer.cancel();
      return;
    }
    setState(() {
      _remaining = _remaining - const Duration(seconds: 1);
      if (_remaining < Duration.zero) _remaining = Duration.zero;
    });
  }

  Future<void> _completeCurrentTask() async {
    if (_completing) return;
    final current = _currentTask;
    if (current == null) {
      await _completeParentAndExit();
      return;
    }
    setState(() => _completing = true);
    try {
      if (current.id == _todo.id) {
        await _completeParentAndExit();
        return;
      }
      final res = await TodosRepository.instance.completeLocalFirst(current);
      _addTriggered(res.triggeredTodos);
      if (!mounted) return;
      setState(() {
        _subtasks = [
          for (final subtask in _subtasks)
            if (subtask.id == res.todo.id) res.todo else subtask,
        ];
      });
      if (_currentTask == null) {
        await _completeParentAndExit();
      } else if (mounted) {
        setState(() => _completing = false);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _completing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.vnMessage),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _completeParentAndExit() async {
    if (_closed) return;
    setState(() => _completing = true);
    try {
      if (!_todo.isDone) {
        final res = await TodosRepository.instance.completeLocalFirst(_todo);
        _todo = res.todo;
        _addTriggered(res.triggeredTodos);
      }
      _close(completedAll: true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _completing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.vnMessage),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _addTriggered(List<Todo> todos) {
    final existingIds = _triggeredTodos.map((todo) => todo.id).toSet();
    for (final todo in todos) {
      if (existingIds.add(todo.id)) _triggeredTodos.add(todo);
    }
  }

  void _close({required bool completedAll}) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(
      _TodoFocusResult(
        todo: _todo,
        subtasks: _subtasks,
        triggeredTodos: _triggeredTodos,
        completedAll: completedAll,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentTask;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Đóng',
          onPressed: () => _close(completedAll: false),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: current == null || _completing
              ? null
              : _completeCurrentTask,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: current == null
                ? const Center(child: CircularProgressIndicator())
                : _FocusSessionPane(
                    key: ValueKey(current.id),
                    current: current,
                    nextSubtasks: _nextSubtasksAfter(current),
                    remaining: _remaining,
                    total: widget.focusDuration,
                    secondary: secondary,
                    completing: _completing,
                  ),
          ),
        ),
      ),
    );
  }
}

class _FocusSessionPane extends StatelessWidget {
  final Todo current;
  final List<Todo> nextSubtasks;
  final Duration remaining;
  final Duration total;
  final Color secondary;
  final bool completing;

  const _FocusSessionPane({
    super.key,
    required this.current,
    required this.nextSubtasks,
    required this.remaining,
    required this.total,
    required this.secondary,
    required this.completing,
  });

  @override
  Widget build(BuildContext context) {
    final totalSeconds = math.max(1, total.inSeconds);
    final progress = remaining.inSeconds / totalSeconds;
    final isOver = remaining <= Duration.zero;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final ringColor = isOver
        ? AppColors.danger.withValues(alpha: 0.72)
        : (isDark ? AppColors.textSecondaryDark : AppColors.tagSlate)
              .withValues(alpha: 0.78);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final nextHeight = nextSubtasks.isEmpty ? 0.0 : 124.0;
          final ringLimitByHeight = constraints.maxHeight - nextHeight - 168;
          final ringSize = math
              .min(constraints.maxWidth * 0.72, ringLimitByHeight)
              .clamp(170.0, 252.0)
              .toDouble();
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        current.title,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1.14,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox.square(
                        dimension: ringSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(
                              child: CircularProgressIndicator(
                                value: progress.clamp(0, 1).toDouble(),
                                strokeWidth: 10,
                                backgroundColor: secondary.withValues(
                                  alpha: 0.14,
                                ),
                                valueColor: AlwaysStoppedAnimation(ringColor),
                              ),
                            ),
                            Text(
                              _formatDuration(remaining),
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: completing
                            ? SizedBox(
                                key: const ValueKey('saving'),
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    secondary.withValues(alpha: 0.72),
                                  ),
                                ),
                              )
                            : Text(
                                key: const ValueKey('status'),
                                isOver ? 'Hết giờ' : 'Thời gian tập trung',
                                style: TextStyle(
                                  color: isOver
                                      ? AppColors.danger.withValues(alpha: 0.76)
                                      : secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              if (nextSubtasks.isNotEmpty)
                _NextSubtasksPreview(
                  subtasks: nextSubtasks,
                  secondary: secondary,
                  textPrimary: textPrimary,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NextSubtasksPreview extends StatelessWidget {
  final List<Todo> subtasks;
  final Color secondary;
  final Color textPrimary;

  const _NextSubtasksPreview({
    required this.subtasks,
    required this.secondary,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).brightness == Brightness.dark
        ? AppColors.dividerDark
        : AppColors.divider;
    final visible = subtasks.take(3).toList();
    final hiddenCount = subtasks.length - visible.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tiếp theo',
              style: TextStyle(
                color: secondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...visible.map(
              (todo) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.radio_button_unchecked,
                      size: 16,
                      color: secondary.withValues(alpha: 0.68),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        todo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textPrimary.withValues(alpha: 0.86),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+$hiddenCount việc con',
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CelebrationOverlay extends StatefulWidget {
  final int seed;

  const _CelebrationOverlay({required this.seed});

  @override
  State<_CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<_CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _FireworksPainter(
            progress: _controller.value,
            seed: widget.seed,
          ),
          child: Center(
            child: Opacity(
              opacity: (1 - _controller.value).clamp(0, 1).toDouble(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Hoàn thành!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FireworksPainter extends CustomPainter {
  final double progress;
  final int seed;

  const _FireworksPainter({required this.progress, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    const colors = [
      AppColors.success,
      AppColors.streakGold,
      AppColors.primary,
      AppColors.q1,
      AppColors.tagCyan,
    ];
    for (var burst = 0; burst < 5; burst++) {
      final delay = burst * 0.09;
      final local = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final center = Offset(
        size.width * (0.18 + random.nextDouble() * 0.64),
        size.height * (0.18 + random.nextDouble() * 0.46),
      );
      final radius =
          size.shortestSide * (0.12 + random.nextDouble() * 0.16) * local;
      final alpha = (1 - local).clamp(0.0, 1.0);
      for (var i = 0; i < 22; i++) {
        final angle = (math.pi * 2 * i / 22) + random.nextDouble() * 0.16;
        final distance = radius * (0.68 + random.nextDouble() * 0.46);
        final start =
            center + Offset(math.cos(angle), math.sin(angle)) * distance * 0.62;
        final end =
            center + Offset(math.cos(angle), math.sin(angle)) * distance;
        final paint = Paint()
          ..color = colors[(i + burst) % colors.length].withValues(alpha: alpha)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.seed != seed;
  }
}

String _formatDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60);
  final seconds = safe.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
    final textPrimary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

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
                todo.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
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

/// Dòng nháp khi thêm việc con: chưa có id nên không có chevron/mở chi tiết.
class _DraftSubtaskRow extends StatefulWidget {
  final bool saving;
  final Future<void> Function(String) onCommit;
  final VoidCallback onCancel;

  const _DraftSubtaskRow({
    super.key,
    required this.saving,
    required this.onCommit,
    required this.onCancel,
  });

  @override
  State<_DraftSubtaskRow> createState() => _DraftSubtaskRowState();
}

class _DraftSubtaskRowState extends State<_DraftSubtaskRow> {
  late final TextEditingController _ctrl = TextEditingController();
  late final FocusNode _focus = FocusNode();
  bool _finished = false;

  String get draftTitle => _ctrl.text.trim();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => focus());
  }

  void focus() {
    if (!mounted || _finished) return;
    _focus.requestFocus();
  }

  void resetForNext() {
    if (!mounted) return;
    _ctrl.clear();
    _finished = false;
    _focus.requestFocus();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      _finish();
    }
  }

  Future<void> _finish() async {
    if (_finished || widget.saving) return;
    final title = _ctrl.text.trim();
    _finished = true;
    if (title.isEmpty) {
      widget.onCancel();
      return;
    }
    await widget.onCommit(title);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              Icons.radio_button_unchecked,
              size: 22,
              color: textSecondary.withValues(alpha: 0.7),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              maxLines: null,
              textInputAction: TextInputAction.done,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Nhập tiêu đề việc con',
                hintStyle: TextStyle(color: textSecondary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
              onSubmitted: (_) => _finish(),
            ),
          ),
          if (widget.saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            const SizedBox(width: 54),
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
    final textPrimary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
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
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );
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
