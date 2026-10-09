import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/active_session_guard.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_snack.dart';
import '../../utils/date_utils.dart';
import '../../utils/focus_session_controller.dart';
import '../../utils/frog_completion_events.dart';
import '../../utils/habit_stacking_dialog.dart';
import '../../utils/todo_delete_dialog.dart';
import '../../utils/todo_local_events.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/duration_picker_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/habit_link_chip.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tag_chip.dart';
import '../../widgets/todo_detail_route_tracker.dart';
import '../calendar/calendar_day_detail_screen.dart';
import '../shell/home_shell_controller.dart';
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

  /// Bắt đầu = true để khung đầu hiện spinner thay vì nháy "Không tìm thấy".
  bool _loading = true;
  bool _celebrating = false;
  bool _draftingSubtask = false;
  bool _savingDraftSubtask = false;
  bool _queueNextDraftAfterSave = false;
  bool _doneSubtasksExpanded = false;
  int _celebrationSeed = 0;
  final Set<String> _expandedSubtaskIds = {};

  @override
  void initState() {
    super.initState();
    TodoLocalEvents.instance.revision.addListener(_onLocalTodoChanged);
    _load();
  }

  @override
  void dispose() {
    TodoLocalEvents.instance.revision.removeListener(_onLocalTodoChanged);
    super.dispose();
  }

  void _onLocalTodoChanged() {
    unawaited(_loadLocalDetail());
  }

  Future<void> _loadLocalDetail() async {
    final local = await TodosRepository.instance.getLocalDetail(widget.todoId);
    if (!mounted || local == null) return;
    setState(() => _detail = local);
  }

  Future<void> _load() async {
    if (_detail == null) {
      await _loadLocalDetail();
    }
    final hasPending = await TodosRepository.instance.hasPendingLocalWrites();
    if (hasPending && _detail != null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final detail = await TodosRepository.instance.getDetail(widget.todoId);
      if (!mounted) return;
      final hasPendingAfter = await TodosRepository.instance
          .hasPendingLocalWrites();
      if (hasPendingAfter) {
        await _loadLocalDetail();
        return;
      }
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
        final shouldCelebrateFrog = todo.isFrog && !todo.isDone;
        final res = await TodosRepository.instance.completeLocalFirst(
          todo,
          celebrateFrog: false,
        );
        if (!mounted) return;
        _returnAfterComplete(
          completedTodo: res.todo,
          celebrateFrog: shouldCelebrateFrog,
        );
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _toggleSubtaskComplete(Todo subtask) async {
    if (_hasLoadedChildren(subtask.id)) {
      _toggleSubtaskExpansion(subtask.id);
      return;
    }
    try {
      final triggeredTodos = <Todo>[];
      Todo updated;
      if (subtask.isDone) {
        updated = await TodosRepository.instance.uncompleteLocalFirst(subtask);
      } else {
        final res = await TodosRepository.instance.completeLocalFirst(subtask);
        updated = res.todo;
        triggeredTodos.addAll(res.triggeredTodos);
      }
      final reconciled = await TodosRepository.instance
          .reconcileSubtaskAncestorsLocalFirst(updated);
      triggeredTodos.addAll(reconciled.triggeredTodos);
      if (!mounted) return;
      await _loadLocalDetail();
      if (!mounted) return;
      if (triggeredTodos.isNotEmpty) {
        await showHabitStackingDialog(context, triggeredTodos, (t) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: t.id)),
          );
        });
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  void _returnAfterComplete({
    required Todo completedTodo,
    required bool celebrateFrog,
  }) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
    }

    if (!celebrateFrog) return;
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      FrogCompletionCelebrations.instance.celebrate(completedTodo);
    });
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
    final scope = await showTodoDeleteScopeDialog(context, todo);
    if (scope == null || !mounted) return;
    try {
      await TodosRepository.instance.deleteTodoLocalFirst(todo, scope: scope);
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
    final result = await Navigator.of(context).push<TodoWithRelations>(
      MaterialPageRoute(builder: (_) => TodoEditScreen(todoId: widget.todoId)),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _detail = result);
      return;
    }
    await _loadLocalDetail();
    if (!mounted) return;
    final hasPending = await TodosRepository.instance.hasPendingLocalWrites();
    if (!hasPending) unawaited(_load());
  }

  Future<void> _startFocus() async {
    final detail = _detail;
    if (detail == null || detail.todo.isDone) return;
    final focusController = FocusSessionController.instance;
    if (!focusController.isActiveFor(detail.todo.id)) {
      // Đang làm việc khác (todo hay checklist) thì phải xong/hủy nó trước.
      if (!await ensureNoActiveSession(context) || !mounted) return;
      var focusMinutes = detail.todo.estimatedMinutes;
      if (focusMinutes == null || focusMinutes <= 0) {
        focusMinutes = await _pickFocusDuration();
        if (focusMinutes == null || focusMinutes <= 0 || !mounted) return;
      }
      if (!focusController.start(detail, Duration(minutes: focusMinutes))) {
        // Có phiên khác chen vào trong lúc người dùng chọn thời lượng.
        await ensureNoActiveSession(context);
        return;
      }
    }
    final result = await openTodoFocusScreen(Navigator.of(context));
    if (result == null || !mounted) return;
    setState(() {
      _detail = _detailWith(todo: result.todo, subtasks: result.subtasks);
    });
    if (result.completedAll && !result.todo.isFrog) {
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
    return showAppSheet<int>(
      context: context,
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

  List<Todo> _childrenOf(String parentId) {
    final detail = _detail;
    if (detail == null) return const [];
    final children =
        detail.subtasks
            .where((subtask) => subtask.parentId == parentId)
            .toList()
          ..sort(_compareSubtaskOrder);
    return children;
  }

  bool _hasLoadedChildren(String todoId) {
    final detail = _detail;
    if (detail == null) return false;
    return detail.subtasks.any((subtask) => subtask.parentId == todoId);
  }

  void _toggleSubtaskExpansion(String todoId) {
    setState(() {
      if (!_expandedSubtaskIds.add(todoId)) {
        _expandedSubtaskIds.remove(todoId);
      }
    });
  }

  Future<void> _openSubtaskDetail(Todo subtask) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: subtask.id)),
    );
    if (mounted) _load();
  }

  Future<void> _reorderSubtaskSection({
    required String parentId,
    required List<Todo> section,
    required bool doneSection,
    required int oldIndex,
    required int newIndex,
  }) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= section.length) {
      return;
    }
    final movedSection = [...section];
    final moved = movedSection.removeAt(oldIndex);
    final targetIndex = newIndex.clamp(0, movedSection.length).toInt();
    movedSection.insert(targetIndex, moved);

    final allChildren = _childrenOf(parentId);
    final pending = allChildren.where((subtask) => !subtask.isDone).toList();
    final done = allChildren.where((subtask) => subtask.isDone).toList();
    final fullOrder = doneSection
        ? [...pending, ...movedSection]
        : [...movedSection, ...done];

    _applyOptimisticSubtaskOrder(fullOrder);
    try {
      await TodosRepository.instance.reorderSubtasksLocalFirst(
        parentId: parentId,
        orderedIds: fullOrder.map((subtask) => subtask.id).toList(),
      );
      await _loadLocalDetail();
    } on ApiException catch (e) {
      if (!mounted) return;
      await _loadLocalDetail();
      _showError(e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      await _loadLocalDetail();
      _showError('Không thể đổi thứ tự việc con');
    }
  }

  void _applyOptimisticSubtaskOrder(List<Todo> ordered) {
    final positions = <String, int>{};
    for (var i = 0; i < ordered.length; i++) {
      positions[ordered[i].id] = i;
    }
    setState(() {
      _detail = _detailWith(
        subtasks: [
          for (final subtask in _detail!.subtasks)
            if (positions.containsKey(subtask.id))
              subtask.copyWith(position: positions[subtask.id])
            else
              subtask,
        ],
      );
    });
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
    showAppSnack(context, msg, isError: true);
  }

  Widget _buildNestedSubtasks(String parentId, int depth) {
    final children = _childrenOf(parentId);
    if (children.isEmpty) return const SizedBox.shrink();
    final pending = children.where((subtask) => !subtask.isDone).toList();
    final done = children.where((subtask) => subtask.isDone).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending.isNotEmpty)
          _buildSubtaskReorderList(
            parentId: parentId,
            subtasks: pending,
            doneSection: false,
            depth: depth,
          ),
        if (done.isNotEmpty)
          _buildSubtaskReorderList(
            parentId: parentId,
            subtasks: done,
            doneSection: true,
            depth: depth,
          ),
      ],
    );
  }

  Widget _buildSubtaskReorderList({
    required String parentId,
    required List<Todo> subtasks,
    required bool doneSection,
    required int depth,
  }) {
    if (subtasks.isEmpty) return const SizedBox.shrink();
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: subtasks.length,
      onReorderStart: (_) => AppHaptics.medium(),
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = Curves.easeOut.transform(animation.value);
          return Transform.scale(
            scale: 1 + 0.02 * t,
            child: Material(
              color: context.appSurface,
              elevation: 8 * t,
              shadowColor: Colors.black.withValues(alpha: 0.25),
              shape: AppShape.squircle(AppRadius.sm),
              child: child,
            ),
          );
        },
      ),
      onReorder: (oldIndex, newIndex) {
        unawaited(
          _reorderSubtaskSection(
            parentId: parentId,
            section: subtasks,
            doneSection: doneSection,
            oldIndex: oldIndex,
            newIndex: newIndex,
          ),
        );
      },
      itemBuilder: (context, index) {
        final subtask = subtasks[index];
        final hasChildren = _hasLoadedChildren(subtask.id);
        final expanded = _expandedSubtaskIds.contains(subtask.id);
        return Column(
          key: ValueKey('subtask_${parentId}_${subtask.id}_$doneSection'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _SubtaskRow(
              subtask: subtask,
              depth: depth,
              hasChildren: hasChildren,
              expanded: expanded,
              dragIndex: index,
              canReorder: subtasks.length > 1,
              onToggle: () => _toggleSubtaskComplete(subtask),
              onToggleExpand: () => _toggleSubtaskExpansion(subtask.id),
              onSaveTitle: (newTitle) => _saveTitle(subtask.id, newTitle),
              onOpenDetail: () => _openSubtaskDetail(subtask),
            ),
            if (hasChildren && expanded)
              _buildNestedSubtasks(subtask.id, depth + 1),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TodoDetailRouteTracker(
      todoId: widget.todoId,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
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
    final todo = _detail!.todo;
    final secondary = context.appTextSecondary;
    final rootSubtasks = _childrenOf(todo.id);
    final pendingSubtasks = rootSubtasks
        .where((subtask) => !subtask.isDone)
        .toList();
    final doneSubtasks = rootSubtasks
        .where((subtask) => subtask.isDone)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(todo.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Chỉnh sửa',
            onPressed: _openEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
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
                if (_detail!.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TodoTagWrap(tags: _detail!.tags, compact: false),
                  ),
                if (todo.habitId != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: HabitLinkChip(habitId: todo.habitId),
                    ),
                  ),
                const SizedBox(height: 4),
                const SectionHeader(label: 'Việc con'),
                if (pendingSubtasks.isEmpty &&
                    doneSubtasks.isEmpty &&
                    !_draftingSubtask)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_tree_outlined,
                          size: 18,
                          color: secondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Chưa có việc con',
                          style: TextStyle(color: secondary),
                        ),
                      ],
                    ),
                  )
                else
                  _buildSubtaskReorderList(
                    parentId: todo.id,
                    subtasks: pendingSubtasks,
                    doneSection: false,
                    depth: 0,
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
                    child: PrimaryButton(
                      label: 'Thêm việc con',
                      icon: Icons.add_rounded,
                      variant: PrimaryButtonVariant.tonal,
                      onPressed: _addSubtask,
                    ),
                  ),
                ),
                if (doneSubtasks.isNotEmpty) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      AppHaptics.selection();
                      setState(
                        () => _doneSubtasksExpanded = !_doneSubtasksExpanded,
                      );
                    },
                    child: SectionHeader(
                      label: 'Đã xong (${doneSubtasks.length})',
                      leading: SectionHeader.dot(AppColors.success),
                      trailing: AnimatedRotation(
                        turns: _doneSubtasksExpanded ? 0.5 : 0,
                        duration: AppMotion.normal,
                        curve: AppMotion.curve,
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: secondary,
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: AppMotion.normal,
                    curve: AppMotion.curve,
                    alignment: Alignment.topCenter,
                    child: _doneSubtasksExpanded
                        ? _buildSubtaskReorderList(
                            parentId: todo.id,
                            subtasks: doneSubtasks,
                            doneSection: true,
                            depth: 0,
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
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
          child: ValueListenableBuilder<FocusSession?>(
            valueListenable: FocusSessionController.instance.session,
            builder: (context, session, _) {
              if (todo.isDone) return const _DoneStatusBar();
              final resuming = session?.todo.id == todo.id;
              return PrimaryButton(
                label: todo.isDone
                    ? 'Đã hoàn thành'
                    : (resuming ? 'Tiếp tục tập trung' : 'Bắt đầu'),
                icon: todo.isDone
                    ? Icons.check_circle
                    : (resuming
                          ? Icons.timer_outlined
                          : Icons.play_arrow_rounded),
                onPressed: todo.isDone ? null : _startFocus,
              );
            },
          ),
        ),
      ),
    );
  }
}

int _compareSubtaskOrder(Todo a, Todo b) {
  final byPosition = a.position.compareTo(b.position);
  if (byPosition != 0) return byPosition;
  return a.createdAt.compareTo(b.createdAt);
}

/// Mở màn hình Focus cho phiên đang chạy. Trả về kết quả khi người dùng kết
/// thúc/hoàn thành; rời bằng Home/Lịch/back trả về null và phiên vẫn chạy ngầm.
Future<FocusSessionResult?> openTodoFocusScreen(
  NavigatorState navigator,
) async {
  final controller = FocusSessionController.instance;
  if (controller.session.value == null || controller.focusScreenOpen.value) {
    return null;
  }
  controller.focusScreenOpen.value = true;
  try {
    return await navigator.push<FocusSessionResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const TodoFocusScreen(),
      ),
    );
  } finally {
    controller.focusScreenOpen.value = false;
  }
}

/// Quay lại phiên đang chạy ngầm (từ banner toàn app). Không có
/// TodoDetailScreen nào chờ kết quả nên ở đây xử lý nốt: mở lại trang chi tiết
/// khi người dùng hủy bấm giờ, và gợi ý habit-stacking sau khi hoàn thành.
///
/// [detailBuilder] chỉ dùng trong test để không chạm repository thật.
Future<void> resumeFocusSession({
  Widget Function(String todoId)? detailBuilder,
}) async {
  final navigator = rootNavigatorKey.currentState;
  final session = FocusSessionController.instance.session.value;
  if (navigator == null || session == null) return;
  Widget buildDetail(String todoId) =>
      detailBuilder?.call(todoId) ?? TodoDetailScreen(todoId: todoId);

  final detailBeneath = TodoDetailRouteTracker.currentTodoId == session.todo.id;
  final result = await openTodoFocusScreen(navigator);
  if (result == null) return;
  if (!result.completedAll && !detailBeneath) {
    navigator.push(
      MaterialPageRoute(builder: (_) => buildDetail(result.todo.id)),
    );
  }
  if (result.triggeredTodos.isNotEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 650));
  } else if (!result.completedAll) {
    return;
  }
  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  await showHabitStackingDialog(context, result.triggeredTodos, (todo) {
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => buildDetail(todo.id)),
    );
  });
}

/// Màn hình "tập trung" cho 1 todo. State thực của phiên (đồng hồ, task hiện
/// tại, triggeredTodos) sống trong [FocusSessionController] ở cấp app — màn
/// hình này chỉ là view. Nhờ vậy khi người dùng bấm Home/Lịch để rời màn
/// hình, đồng hồ vẫn tiếp tục chạy ngầm và có thể resume lại đúng tiến độ.
///
/// Nút back hệ thống chỉ thu nhỏ phiên xuống banner. Nút X luôn hỏi lại trước:
/// "Trở lại" (về trang chủ, đồng hồ chạy tiếp) hoặc "Hủy bấm giờ" (dừng phiên).
class TodoFocusScreen extends StatefulWidget {
  /// Chỉ dùng trong test: thay màn hình lịch ngày để không chạm repository.
  @visibleForTesting
  final Widget Function(DateTime today)? todayCalendarBuilder;

  const TodoFocusScreen({super.key, this.todayCalendarBuilder});

  @override
  State<TodoFocusScreen> createState() => _TodoFocusScreenState();
}

enum _FocusLeaveChoice { back, cancelTimer }

class _TodoFocusScreenState extends State<TodoFocusScreen> {
  bool _completing = false;
  bool _closed = false;
  bool _leaveDialogOpen = false;
  late FocusSession? _lastSession = _controller.session.value;

  FocusSessionController get _controller => FocusSessionController.instance;

  @override
  void initState() {
    super.initState();
    _controller.session.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSessionChanged());
  }

  @override
  void dispose() {
    _controller.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted || _closed) return;
    final session = _controller.session.value;
    if (session == null) {
      // Phiên bị hủy từ bên ngoài (todo bị xóa, đăng xuất...).
      _closed = true;
      _dismissLeaveDialog();
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
      return;
    }
    setState(() => _lastSession = session);
    if (!_completing && _currentTaskOf(session) == null) {
      unawaited(_completeParentAndExit());
    }
  }

  List<Todo> _childrenOf(List<Todo> subtasks, String parentId) {
    final children =
        subtasks.where((subtask) => subtask.parentId == parentId).toList()
          ..sort(_compareSubtaskOrder);
    return children;
  }

  List<Todo> _orderedLeafSubtasks(List<Todo> subtasks, String parentId) {
    final result = <Todo>[];
    for (final child in _childrenOf(subtasks, parentId)) {
      final nested = _orderedLeafSubtasks(subtasks, child.id);
      if (nested.isEmpty) {
        result.add(child);
      } else {
        result.addAll(nested);
      }
    }
    return result;
  }

  Todo? _currentTaskOf(FocusSession session) {
    if (session.subtasks.isEmpty) {
      return session.todo.isDone ? null : session.todo;
    }
    final leaves = _orderedLeafSubtasks(session.subtasks, session.todo.id);
    for (final subtask in leaves) {
      if (!subtask.isDone) return subtask;
    }
    return session.todo.isDone ? null : session.todo;
  }

  List<Todo> _nextSubtasksAfter(FocusSession session, Todo current) {
    final pending = _orderedLeafSubtasks(
      session.subtasks,
      session.todo.id,
    ).where((subtask) => !subtask.isDone).toList();
    final currentIndex = pending.indexWhere(
      (subtask) => subtask.id == current.id,
    );
    if (currentIndex < 0) return const [];
    return pending.skip(currentIndex + 1).toList();
  }

  List<Todo> _parentChainFor(FocusSession session, Todo current) {
    final byId = {for (final subtask in session.subtasks) subtask.id: subtask};
    final chain = <Todo>[];
    var parentId = current.parentId;
    while (parentId != null && parentId != session.todo.id) {
      final parent = byId[parentId];
      if (parent == null) break;
      chain.add(parent);
      parentId = parent.parentId;
    }
    return chain.reversed.toList(growable: false);
  }

  Future<void> _completeCurrentTask() async {
    final session = _controller.session.value;
    if (_completing || _closed || session == null) return;
    final current = _currentTaskOf(session);
    if (current == null) {
      await _completeParentAndExit();
      return;
    }
    setState(() => _completing = true);
    try {
      if (current.id == session.todo.id) {
        await _completeParentAndExit();
        return;
      }
      final res = await TodosRepository.instance.completeLocalFirst(current);
      _controller.addTriggered(res.triggeredTodos);
      final reconciled = await TodosRepository.instance
          .reconcileSubtaskAncestorsLocalFirst(res.todo);
      _controller.addTriggered(reconciled.triggeredTodos);
      _controller.updateSubtasks([res.todo, ...reconciled.updatedTodos]);
      if (!mounted || _closed) return;
      final updated = _controller.session.value;
      if (updated == null || _currentTaskOf(updated) == null) {
        await _completeParentAndExit();
      } else {
        setState(() => _completing = false);
      }
    } on ApiException catch (e) {
      _showFocusError(e);
    }
  }

  Future<void> _completeParentAndExit() async {
    if (_closed) return;
    if (!_completing) setState(() => _completing = true);
    try {
      final todo = _controller.session.value?.todo;
      if (todo != null && !todo.isDone) {
        final res = await TodosRepository.instance.completeLocalFirst(todo);
        _controller.updateSubtasks([res.todo]);
        _controller.addTriggered(res.triggeredTodos);
      }
      _close(completedAll: true);
    } on ApiException catch (e) {
      _showFocusError(e);
    }
  }

  void _showFocusError(ApiException e) {
    if (!mounted) return;
    setState(() => _completing = false);
    showAppSnack(context, e.vnMessage, isError: true);
  }

  /// Kết thúc phiên. Vẫn dọn controller dù màn hình đã bị đóng giữa chừng
  /// (ví dụ người dùng bấm Home khi đang lưu) để không để lại banner mồ côi.
  void _close({required bool completedAll}) {
    if (_closed) return;
    _closed = true;
    final result = _controller.finish(completedAll: completedAll);
    if (!mounted) return;
    _dismissLeaveDialog();
    Navigator.of(context).pop(result);
  }

  /// Hỏi lại trước khi thoát để bấm nhầm X không làm mất phiên đang chạy.
  /// Chạm ra ngoài hộp thoại (hoặc back) là ở lại màn hình Focus.
  Future<void> _confirmLeave() async {
    if (_closed || _completing || _leaveDialogOpen) return;
    _leaveDialogOpen = true;
    const bold = TextStyle(fontWeight: FontWeight.w700);
    final choice = await showDialog<_FocusLeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thoát bấm giờ?'),
        content: const Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Trở lại', style: bold),
              TextSpan(text: ': về trang chủ, đồng hồ vẫn tiếp tục chạy.\n\n'),
              TextSpan(text: 'Hủy bấm giờ', style: bold),
              TextSpan(
                text: ': dừng đồng hồ và quay về trang chi tiết của việc này.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('focus-leave-cancel'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () =>
                Navigator.of(ctx).pop(_FocusLeaveChoice.cancelTimer),
            child: const Text('Hủy bấm giờ'),
          ),
          FilledButton(
            key: const ValueKey('focus-leave-back'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(ctx).pop(_FocusLeaveChoice.back),
            child: const Text('Trở lại'),
          ),
        ],
      ),
    );
    _leaveDialogOpen = false;
    if (!mounted || _closed) return;
    switch (choice) {
      case _FocusLeaveChoice.back:
        _goHome();
      case _FocusLeaveChoice.cancelTimer:
        _close(completedAll: false);
      case null:
        break;
    }
  }

  /// Đóng hộp thoại xác nhận nếu đang mở, để `pop` kế tiếp đóng đúng màn Focus
  /// chứ không đóng nhầm hộp thoại. Bỏ qua nếu hộp thoại đã đang được đóng
  /// (lúc đó màn Focus đã là route trên cùng).
  void _dismissLeaveDialog() {
    if (!_leaveDialogOpen) return;
    _leaveDialogOpen = false;
    if (ModalRoute.of(context)?.isCurrent == false) {
      Navigator.of(context).pop();
    }
  }

  /// Về tab "Hôm nay". Không kết thúc phiên — đồng hồ chạy tiếp ở banner.
  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    HomeShellController.instance.showToday();
  }

  /// Vào thẳng chi tiết lịch hôm nay (qua tab Lịch). Không kết thúc phiên.
  void _goToTodayCalendar() {
    final navigator = Navigator.of(context);
    final today = AppDateUtils.dateOnly(DateTime.now());
    final calendarBuilder = widget.todayCalendarBuilder;
    navigator.popUntil((route) => route.isFirst);
    HomeShellController.instance.setTab(4);
    navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            calendarBuilder?.call(today) ??
            CalendarDayDetailScreen(initialDate: today),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _lastSession;
    if (session == null) return const Scaffold(body: SizedBox.shrink());
    final current = _currentTaskOf(session);
    final secondary = context.appTextSecondary;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 96,
        leading: Row(
          children: [
            IconButton(
              key: const ValueKey('focus-home'),
              icon: const Icon(Icons.home_rounded),
              tooltip: 'Về trang chủ',
              onPressed: _goHome,
            ),
            IconButton(
              key: const ValueKey('focus-calendar'),
              icon: const Icon(Icons.calendar_month_rounded),
              tooltip: 'Lịch hôm nay',
              onPressed: _goToTodayCalendar,
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('focus-close'),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Thoát bấm giờ',
            onPressed: _completing ? null : _confirmLeave,
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: current == null || _completing
              ? null
              : () {
                  AppHaptics.medium();
                  _completeCurrentTask();
                },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: current == null
                ? const Center(child: CircularProgressIndicator())
                : _FocusSessionPane(
                    key: ValueKey(current.id),
                    current: current,
                    parentChain: _parentChainFor(session, current),
                    nextSubtasks: _nextSubtasksAfter(session, current),
                    remaining: session.remaining,
                    total: session.total,
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
  final List<Todo> parentChain;
  final List<Todo> nextSubtasks;
  final Duration remaining;
  final Duration total;
  final Color secondary;
  final bool completing;

  const _FocusSessionPane({
    super.key,
    required this.current,
    required this.parentChain,
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
                // Màn thấp / chữ hệ thống lớn: phần giữa cuộn được thay vì tràn.
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CurrentFocusTaskHeader(
                              parentChain: parentChain,
                              current: current,
                              secondary: secondary,
                              textPrimary: textPrimary,
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
                                      valueColor: AlwaysStoppedAnimation(
                                        ringColor,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: ringSize * 0.7,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        formatFocusDuration(remaining),
                                        style: TextStyle(
                                          fontSize: 34,
                                          fontWeight: FontWeight.w800,
                                          color: textPrimary,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
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
                                      isOver
                                          ? 'Hết giờ'
                                          : 'Thời gian tập trung',
                                      style: TextStyle(
                                        color: isOver
                                            ? AppColors.danger.withValues(
                                                alpha: 0.76,
                                              )
                                            : secondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _CurrentFocusTaskHeader extends StatelessWidget {
  final List<Todo> parentChain;
  final Todo current;
  final Color secondary;
  final Color textPrimary;

  const _CurrentFocusTaskHeader({
    required this.parentChain,
    required this.current,
    required this.secondary,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    if (parentChain.isEmpty) {
      return Text(
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
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParentTaskTrail(
          parents: parentChain,
          secondary: secondary,
          textPrimary: textPrimary,
        ),
        const SizedBox(height: 12),
        Text(
          current.title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.14,
            color: textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ParentTaskTrail extends StatelessWidget {
  final List<Todo> parents;
  final Color secondary;
  final Color textPrimary;

  const _ParentTaskTrail({
    required this.parents,
    required this.secondary,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.dividerDark : AppColors.divider;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ShapeDecoration(
        color: secondary.withValues(alpha: isDark ? 0.08 : 0.07),
        shape: AppShape.squircle(
          AppRadius.sm,
          side: BorderSide(color: border.withValues(alpha: 0.82)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 14,
                color: secondary.withValues(alpha: 0.82),
              ),
              const SizedBox(width: 6),
              Text(
                'Trong việc con',
                style: TextStyle(
                  color: secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < parents.length; index++)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (index > 0) SizedBox(width: 14.0 * index),
                  Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 15,
                    color: secondary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      parents[index].title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary.withValues(alpha: 0.9),
                        fontSize: 14,
                        height: 1.18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
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
    final textPrimary = context.appTextPrimary;
    final textSecondary = context.appTextSecondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: () {
              if (!todo.isDone) AppHaptics.medium();
              onToggle();
            },
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: AnimatedSwitcher(
                duration: AppMotion.normal,
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  todo.isDone
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  key: ValueKey(todo.isDone),
                  size: 28,
                  color: todo.isDone ? context.appPrimary : textSecondary,
                ),
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
    final textPrimary = context.appTextPrimary;
    final textSecondary = context.appTextSecondary;
    final divider = context.appDivider;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
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
              child: AppSpinner(radius: 8, centered: false),
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
  final int depth;
  final bool hasChildren;
  final bool expanded;
  final int dragIndex;
  final bool canReorder;
  final VoidCallback onToggle;
  final VoidCallback onToggleExpand;
  final Future<void> Function(String) onSaveTitle;
  final VoidCallback onOpenDetail;

  const _SubtaskRow({
    required this.subtask,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
    required this.dragIndex,
    required this.canReorder,
    required this.onToggle,
    required this.onToggleExpand,
    required this.onSaveTitle,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = context.appTextPrimary;
    final textSecondary = context.appTextSecondary;
    final divider = context.appDivider;
    final primary = context.appPrimary;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 8 + depth * 20),
          InkWell(
            onTap: hasChildren
                ? onToggleExpand
                : () {
                    if (!subtask.isDone) AppHaptics.medium();
                    onToggle();
                  },
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: hasChildren
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.chevron_right_rounded,
                          size: 22,
                          color: subtask.isDone ? primary : textSecondary,
                        ),
                        if (subtask.isDone)
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: primary,
                            ),
                          ),
                      ],
                    )
                  : AnimatedSwitcher(
                      duration: AppMotion.normal,
                      switchInCurve: Curves.easeOutBack,
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Icon(
                        subtask.isDone
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        key: ValueKey(subtask.isDone),
                        size: 22,
                        color: subtask.isDone ? primary : textSecondary,
                      ),
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
          if (canReorder)
            ReorderableDelayedDragStartListener(
              index: dragIndex,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: textSecondary.withValues(alpha: 0.8),
                ),
              ),
            )
          else
            const SizedBox(width: 44),
          // Chevron với vùng nhấn rộng để dễ tap mở chi tiết
          InkWell(
            onTap: onOpenDetail,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: textSecondary.withValues(alpha: 0.7),
              ),
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

/// Thanh trạng thái thay cho nút chính khi việc đã hoàn thành.
class _DoneStatusBar extends StatelessWidget {
  const _DoneStatusBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: context.appSuccessSoft,
        shape: AppShape.squircle(AppRadius.md),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
          SizedBox(width: 8),
          Text(
            'Đã hoàn thành',
            style: TextStyle(
              color: AppColors.success,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
