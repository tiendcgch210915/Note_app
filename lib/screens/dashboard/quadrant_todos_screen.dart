import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../models/dashboard.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/habit_stacking_dialog.dart';
import '../../utils/date_utils.dart';
import '../../utils/json_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../utils/todo_delete_dialog.dart';
import '../../utils/todo_time_utils.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/habit_link_chip.dart';
import '../../widgets/tag_chip.dart';
import '../../widgets/todo_timed_title.dart';
import '../../widgets/todo_swipe_actions.dart';
import '../todos/todo_detail_screen.dart';

/// EXP 10 — Hiển thị full list todos của 1 quadrant khi tap ô Dashboard.
class QuadrantTodosScreen extends StatefulWidget {
  final Quadrant quadrant;
  final List<DashboardEisenhowerTodo> todos;
  final DateTime date;

  const QuadrantTodosScreen({
    super.key,
    required this.quadrant,
    required this.todos,
    required this.date,
  });

  @override
  State<QuadrantTodosScreen> createState() => _QuadrantTodosScreenState();
}

class _QuadrantTodosScreenState extends State<QuadrantTodosScreen> {
  late List<DashboardEisenhowerTodo> _todos;
  final Set<String> _completedIds = {};
  final Set<String> _savingIds = {};

  @override
  void initState() {
    super.initState();
    _todos = _sortTodos(widget.todos);
  }

  @override
  void didUpdateWidget(covariant QuadrantTodosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todos != widget.todos) {
      _todos = _sortTodos(widget.todos);
    }
  }

  Future<void> _completeTodo(DashboardEisenhowerTodo todo) async {
    if (todo.isDailyLog) {
      _showError('Ngày này đã chốt, không thể tick trực tiếp từ lịch sử');
      return;
    }
    if (todo.id.isEmpty ||
        todo.isFrog ||
        todo.effectiveDone ||
        _completedIds.contains(todo.id) ||
        _savingIds.contains(todo.id)) {
      return;
    }

    setState(() {
      _completedIds.add(todo.id);
      _savingIds.add(todo.id);
    });

    try {
      final localDetail = await TodosRepository.instance.getLocalDetail(
        todo.todoId,
      );
      final source = localDetail?.todo ?? _todoFromDashboard(todo);
      final result = await TodosRepository.instance.completeLocalFirst(source);
      if (!mounted) return;
      setState(() => _savingIds.remove(todo.id));
      await showHabitStackingDialog(context, result.triggeredTodos, (t) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: t.id)),
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _completedIds.remove(todo.id);
        _savingIds.remove(todo.id);
      });
      _showError(e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _completedIds.remove(todo.id);
        _savingIds.remove(todo.id);
      });
      _showError('Không thể hoàn thành việc này');
    }
  }

  Todo _todoFromDashboard(DashboardEisenhowerTodo todo) {
    final now = DateTime.now().toUtc();
    return Todo(
      id: todo.todoId,
      title: todo.title,
      status: TodoStatus.parse(todo.status),
      isFrog: todo.isFrog,
      frogDate: todo.frogDate,
      isImportant: todo.isImportant,
      isUrgent: todo.isUrgent,
      scheduledDate: todo.scheduledDate,
      time: todo.time,
      habitId: todo.habitId,
      tags: todo.tags,
      tagIds: todo.tagIds,
      tagsLoaded: todo.tags.isNotEmpty || todo.tagIds.isNotEmpty,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Todo> _sourceTodo(DashboardEisenhowerTodo todo) async {
    final localDetail = await TodosRepository.instance.getLocalDetail(
      todo.todoId,
    );
    return localDetail?.todo ?? _todoFromDashboard(todo);
  }

  DashboardEisenhowerTodo _dashboardTodoFromTodo(
    DashboardEisenhowerTodo previous,
    Todo todo,
  ) {
    return DashboardEisenhowerTodo(
      id: todo.id,
      source: previous.source,
      isDailyLog: previous.isDailyLog,
      logId: previous.logId,
      todoId: previous.todoId,
      lockedCompleted: previous.lockedCompleted,
      title: todo.title,
      status: todo.status.backendValue,
      scheduledDate: todo.scheduledDate,
      time: todo.time,
      isImportant: todo.isImportant ?? previous.isImportant,
      isUrgent: todo.isUrgent ?? previous.isUrgent,
      isFrog: todo.isFrog,
      frogDate: todo.frogDate,
      quadrant: previous.quadrant,
      habitId: todo.habitId,
      tags: todo.tags,
      tagIds: todo.tagIds,
    );
  }

  Future<void> _pickTodoDate(DashboardEisenhowerTodo todo) async {
    if (todo.isDailyLog) {
      _showError('Ngày này đã chốt, không thể đổi ngày từ lịch sử');
      return;
    }
    if (todo.id.isEmpty || _savingIds.contains(todo.id)) return;
    final initial = todo.scheduledDate ?? widget.date;
    final defaultFirst = DateTime.now().subtract(const Duration(days: 365));
    final defaultLast = DateTime.now().add(const Duration(days: 365 * 5));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.isBefore(defaultFirst) ? initial : defaultFirst,
      lastDate: initial.isAfter(defaultLast) ? initial : defaultLast,
    );
    if (picked == null || !mounted) return;
    await _changeTodoDateLocalFirst(todo, picked);
  }

  Future<void> _changeTodoDateLocalFirst(
    DashboardEisenhowerTodo todo,
    DateTime date,
  ) async {
    final optimisticSource = _todoFromDashboard(todo).copyWith(
      scheduledDate: AppDateUtils.dateOnly(date),
      frogDate: todo.isFrog ? AppDateUtils.dateOnly(date) : todo.frogDate,
    );
    setState(() {
      _savingIds.add(todo.id);
      if (AppDateUtils.isSameDay(date, widget.date)) {
        _todos = _sortTodos(
          _todos
              .map(
                (item) => item.id == todo.id
                    ? _dashboardTodoFromTodo(item, optimisticSource)
                    : item,
              )
              .toList(),
        );
      } else {
        _todos = _todos.where((item) => item.id != todo.id).toList();
      }
    });
    try {
      final source = await _sourceTodo(todo);
      final updated = await TodosRepository.instance.updateLocalFirst(source, {
        'scheduled_date': formatDateOnly(date),
        'due_at': formatEndOfDayIso(date),
        if (source.isFrog) 'frog_date': formatDateOnly(date),
      });
      if (!mounted) return;
      setState(() {
        _savingIds.remove(todo.id);
        if (AppDateUtils.isSameDay(date, widget.date)) {
          _todos = _sortTodos(
            _todos
                .map(
                  (item) => item.id == todo.id
                      ? _dashboardTodoFromTodo(item, updated)
                      : item,
                )
                .toList(),
          );
        } else {
          _todos = _todos.where((item) => item.id != todo.id).toList();
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã đổi ngày')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _savingIds.remove(todo.id);
        _restoreTodoInCurrentList(todo);
      });
      _showError(e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingIds.remove(todo.id);
        _restoreTodoInCurrentList(todo);
      });
      _showError('Không thể đổi ngày');
    }
  }

  Future<void> _pickTodoTime(DashboardEisenhowerTodo todo) async {
    if (todo.isDailyLog) {
      _showError('Ngày này đã chốt, không thể đổi giờ từ lịch sử');
      return;
    }
    if (todo.id.isEmpty || _savingIds.contains(todo.id)) return;
    final action = todo.time == null
        ? 'pick'
        : await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Chọn giờ'),
                    subtitle: Text('Hiện tại: ${todo.time}'),
                    onTap: () => Navigator.of(ctx).pop('pick'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.close_rounded),
                    title: const Text('Bỏ giờ'),
                    onTap: () => Navigator.of(ctx).pop('clear'),
                  ),
                ],
              ),
            ),
          );
    if (action == null || !mounted) return;
    if (action == 'clear') {
      await _changeTodoTimeLocalFirst(todo, null);
      return;
    }

    var date = todo.scheduledDate;
    if (date == null) {
      date = await _pickDateBeforeTime(todo);
      if (date == null || !mounted) return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDayFromString(todo.time),
    );
    if (picked == null || !mounted) return;
    await _changeTodoTimeLocalFirst(
      todo,
      _formatTimeOfDay(picked),
      scheduledDate: date,
    );
  }

  Future<DateTime?> _pickDateBeforeTime(DashboardEisenhowerTodo todo) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chọn ngày làm trước khi đặt giờ')),
    );
    final initial = todo.scheduledDate ?? widget.date;
    final defaultFirst = DateTime.now().subtract(const Duration(days: 365));
    final defaultLast = DateTime.now().add(const Duration(days: 365 * 5));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.isBefore(defaultFirst) ? initial : defaultFirst,
      lastDate: initial.isAfter(defaultLast) ? initial : defaultLast,
    );
    return picked == null ? null : AppDateUtils.dateOnly(picked);
  }

  Future<void> _changeTodoTimeLocalFirst(
    DashboardEisenhowerTodo todo,
    String? time, {
    DateTime? scheduledDate,
  }) async {
    final optimisticSource = _todoFromDashboard(todo).copyWith(
      scheduledDate: scheduledDate ?? todo.scheduledDate,
      time: time,
      frogDate: scheduledDate != null && todo.isFrog
          ? scheduledDate
          : todo.frogDate,
    );
    setState(() {
      _savingIds.add(todo.id);
      final updatedDate = optimisticSource.scheduledDate;
      if (updatedDate != null &&
          AppDateUtils.isSameDay(updatedDate, widget.date)) {
        _todos = _sortTodos(
          _todos
              .map(
                (item) => item.id == todo.id
                    ? _dashboardTodoFromTodo(item, optimisticSource)
                    : item,
              )
              .toList(),
        );
      } else {
        _todos = _todos.where((item) => item.id != todo.id).toList();
      }
    });
    try {
      final source = await _sourceTodo(todo);
      final updated = await TodosRepository.instance.updateLocalFirst(source, {
        if (scheduledDate != null) ...{
          'scheduled_date': formatDateOnly(scheduledDate),
          'due_at': formatEndOfDayIso(scheduledDate),
          if (source.isFrog) 'frog_date': formatDateOnly(scheduledDate),
        },
        'time': time,
      });
      if (!mounted) return;
      setState(() {
        _savingIds.remove(todo.id);
        final updatedDate = updated.scheduledDate;
        if (updatedDate != null &&
            AppDateUtils.isSameDay(updatedDate, widget.date)) {
          _todos = _sortTodos(
            _todos
                .map(
                  (item) => item.id == todo.id
                      ? _dashboardTodoFromTodo(item, updated)
                      : item,
                )
                .toList(),
          );
        } else {
          _todos = _todos.where((item) => item.id != todo.id).toList();
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã đổi giờ')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _savingIds.remove(todo.id);
        _restoreTodoInCurrentList(todo);
      });
      _showError(e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingIds.remove(todo.id);
        _restoreTodoInCurrentList(todo);
      });
      _showError('Không thể đổi giờ');
    }
  }

  void _restoreTodoInCurrentList(DashboardEisenhowerTodo todo) {
    final date = todo.scheduledDate;
    if (date != null && !AppDateUtils.isSameDay(date, widget.date)) {
      _todos = _todos.where((item) => item.id != todo.id).toList();
      return;
    }
    _todos = _sortTodos([todo, ..._todos.where((item) => item.id != todo.id)]);
  }

  TimeOfDay _timeOfDayFromString(String? value) {
    final minutes = todoTimeMinutes(value);
    if (minutes == null) return TimeOfDay.now();
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  String _formatTimeOfDay(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _deleteTodoLocalFirst(DashboardEisenhowerTodo todo) async {
    if (todo.isDailyLog) {
      _showError('Ngày này đã chốt, không thể xóa log từ ma trận');
      return;
    }
    if (todo.id.isEmpty || _savingIds.contains(todo.id)) return;
    Todo? localTodo = (await TodosRepository.instance.getLocalDetail(
      todo.todoId,
    ))?.todo;
    if (localTodo == null) {
      try {
        localTodo = (await TodosRepository.instance.getDetail(
          todo.todoId,
        )).todo;
      } on ApiException catch (e) {
        if (mounted) _showError(e.vnMessage);
        return;
      }
    }
    if (!mounted) return;
    final scope = await showTodoDeleteScopeDialog(context, localTodo);
    if (scope == null || !mounted) return;
    final index = _todos.indexWhere((item) => item.id == todo.id);
    if (index < 0) return;
    final removed = _todos[index];
    setState(
      () => _todos = _todos.where((item) => item.id != todo.id).toList(),
    );
    try {
      await TodosRepository.instance.deleteTodoLocalFirst(
        localTodo,
        scope: scope,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xóa todo')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        final next = [..._todos];
        next.insert(index.clamp(0, next.length), removed);
        _todos = next;
      });
      _showError(e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final next = [..._todos];
        next.insert(index.clamp(0, next.length), removed);
        _todos = next;
      });
      _showError('Không thể xóa todo');
    }
  }

  void _openDetail(DashboardEisenhowerTodo todo) {
    final todoId = todo.todoId.isNotEmpty ? todo.todoId : todo.id;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: todoId)));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  List<DashboardEisenhowerTodo> _sortTodos(
    Iterable<DashboardEisenhowerTodo> todos,
  ) {
    final sorted = todos.toList();
    sorted.sort((a, b) {
      final byTime = compareTodoTimes(a.time, b.time);
      if (byTime != 0) return byTime;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final info = QuadrantUtils.info(widget.quadrant);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(info.label),
        backgroundColor: Color.alphaBlend(
          info.color.withValues(alpha: 0.12),
          background,
        ),
      ),
      body: _todos.isEmpty
          ? EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Không có việc nào trong ${info.label}',
              subtitle: 'Action gợi ý: ${info.action}',
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  color: Color.alphaBlend(
                    info.color.withValues(alpha: isDark ? 0.14 : 0.08),
                    background,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 32,
                        decoration: BoxDecoration(
                          color: info.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_todos.length} việc',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Gợi ý: ${info.action}',
                              style: TextStyle(
                                fontSize: 12,
                                color: info.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _todos.length,
                    itemBuilder: (ctx, i) {
                      final t = _todos[i];
                      return TodoSwipeActions(
                        enabled:
                            t.id.isNotEmpty &&
                            !t.isDailyLog &&
                            !_savingIds.contains(t.id),
                        onPickDate: () => _pickTodoDate(t),
                        onPickTime: () => _pickTodoTime(t),
                        onDelete: () => _deleteTodoLocalFirst(t),
                        child: _DashboardTodoTile(
                          todo: t,
                          completed: _completedIds.contains(t.id),
                          saving: _savingIds.contains(t.id),
                          onTap: () => _openDetail(t),
                          onComplete: () => _completeTodo(t),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      backgroundColor: background,
    );
  }
}

class _DashboardTodoTile extends StatelessWidget {
  final DashboardEisenhowerTodo todo;
  final bool completed;
  final bool saving;
  final VoidCallback onTap;
  final VoidCallback onComplete;

  const _DashboardTodoTile({
    required this.todo,
    required this.completed,
    required this.saving,
    required this.onTap,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final isDone = completed || todo.effectiveDone;
    return ListTile(
      onTap: todo.id.isEmpty ? null : onTap,
      leading: SizedBox(
        width: 52,
        height: 52,
        child: Center(
          child: todo.isDailyLog
              ? Icon(
                  Icons.lock_outline_rounded,
                  color: isDone ? AppColors.success : secondary,
                  size: 28,
                )
              : todo.isFrog
              ? const Icon(Icons.eco, color: AppColors.frog)
              : IconButton(
                  tooltip: isDone ? 'Đã hoàn thành' : 'Hoàn thành',
                  onPressed: todo.id.isEmpty || isDone || saving
                      ? null
                      : onComplete,
                  iconSize: 30,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Icon(
                    isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isDone ? AppColors.success : secondary,
                  ),
                ),
        ),
      ),
      title: TodoTimedTitle(
        title: todo.title,
        time: todo.time,
        scheduledDate: todo.scheduledDate,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: isDone ? TextDecoration.lineThrough : null,
          color: isDone ? secondary : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _subtitle(todo),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: secondary),
          ),
          if (todo.isDailyLog) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 13, color: secondary),
                const SizedBox(width: 4),
                Text(
                  todo.lockedCompleted == true
                      ? 'Đã chốt'
                      : 'Đã chốt: chưa xong',
                  style: TextStyle(
                    fontSize: 12,
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          if (todo.tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            TodoTagWrap(tags: todo.tags),
          ],
          if (todo.habitId != null) ...[
            const SizedBox(height: 4),
            HabitLinkChip(habitId: todo.habitId),
          ],
        ],
      ),
      trailing: todo.id.isEmpty
          ? null
          : Icon(Icons.chevron_right, color: secondary),
    );
  }

  String _subtitle(DashboardEisenhowerTodo todo) {
    final parts = <String>[_statusLabel(todo.status)];
    if (todo.isDailyLog && todo.lockedCompleted == false) {
      parts[0] = 'Chưa xong khi chốt ngày';
    }
    if (todo.scheduledDate != null) {
      parts.add(AppDateUtils.formatDate(todo.scheduledDate!));
    }
    if (todo.isFrog) parts.add('Frog');
    return parts.join(' · ');
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'Đang làm';
      case 'done':
        return 'Hoàn thành';
      case 'archived':
        return 'Lưu trữ';
      default:
        return 'Mở';
    }
  }
}
