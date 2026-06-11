import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/habit_stacking_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/todo_tile.dart';
import 'todo_create_screen.dart';
import 'todo_detail_screen.dart';

class TodosListScreen extends StatefulWidget {
  const TodosListScreen({super.key});

  @override
  State<TodosListScreen> createState() => _TodosListScreenState();
}

class _TodosListScreenState extends State<TodosListScreen> {
  List<Todo> _today = [];
  List<Todo> _upcoming = [];
  List<Todo> _overdue = [];
  List<Todo> _unscheduled = [];
  List<Todo> _done = [];
  String? _doneCursor;
  bool _loading = false;
  bool _doneExpanded = false;
  String _filter = 'all';

  /// IDs đang trong quá trình fade-out sau khi user tick complete.
  /// Khi 1 id ở đây, hàng tương ứng được wrap trong animation
  /// shrink-to-zero + opacity-to-zero trong 500ms.
  final Set<String> _fadingIds = {};

  /// Duration cho cả strikethrough delay + fade animation.
  static const _strikethroughDelay = Duration(milliseconds: 120);
  static const _fadeDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      // Fetch song song. "Đã xong" chỉ lấy top-level (parent_id null).
      final today = TodosRepository.instance.getDay(DateTime.now());
      final all = TodosRepository.instance.list(limit: 100);
      final done = TodosRepository.instance.list(
        status: TodoStatus.done,
        parentId: 'null',
        limit: 20,
      );
      final results = await Future.wait([today, all, done]);
      if (!mounted) return;
      final dayTodos = results[0] as List<DayTopLevelTodo>;
      final allRes = results[1] as ({List<Todo> items, String? nextCursor});
      final doneRes = results[2] as ({List<Todo> items, String? nextCursor});

      // Chỉ giữ todo CHƯA done ở "Hôm nay" — done sẽ nằm trong section "Đã xong".
      final todayList = dayTodos
          .map((d) => d.todo)
          .where((t) => !t.isDone)
          .toList();
      final todayIds = todayList.map((t) => t.id).toSet();
      final blockedRecurringSeries = _activeRecurringSeriesKeys(
        todayList,
        allRes.items,
      );

      final upcoming = <Todo>[];
      final nearestUpcomingBySeries = <String, Todo>{};
      final overdue = <Todo>[];
      final unscheduled = <Todo>[];
      for (final t in allRes.items) {
        if (t.parentId != null) continue;
        if (t.isDone) continue;
        if (todayIds.contains(t.id)) continue;
        if (t.scheduledDate == null) {
          unscheduled.add(t);
        } else if (AppDateUtils.isFuture(t.scheduledDate!)) {
          final seriesKey = _recurringSeriesKey(t);
          if (seriesKey != null) {
            if (blockedRecurringSeries.contains(seriesKey)) continue;
            final current = nearestUpcomingBySeries[seriesKey];
            if (current == null ||
                t.scheduledDate!.isBefore(current.scheduledDate!)) {
              nearestUpcomingBySeries[seriesKey] = t;
            }
            continue;
          }
          upcoming.add(t);
        } else if (AppDateUtils.isPast(t.scheduledDate!)) {
          overdue.add(t);
        }
      }
      upcoming.addAll(nearestUpcomingBySeries.values);
      upcoming.sort((a, b) => a.scheduledDate!.compareTo(b.scheduledDate!));
      overdue.sort((a, b) => b.scheduledDate!.compareTo(a.scheduledDate!));
      // Unscheduled: mới nhất lên đầu
      unscheduled.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _today = todayList;
        _upcoming = upcoming;
        _overdue = overdue;
        _unscheduled = unscheduled;
        _done = _sortDoneNewestFirst(doneRes.items);
        _doneCursor = doneRes.nextCursor;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.vnMessage),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Set<String> _activeRecurringSeriesKeys(
    List<Todo> todayList,
    List<Todo> allTodos,
  ) {
    final keys = <String>{};
    for (final t in todayList) {
      final key = _recurringSeriesKey(t);
      if (key != null) keys.add(key);
    }
    for (final t in allTodos) {
      if (t.parentId != null || t.isDone || t.scheduledDate == null) continue;
      if (AppDateUtils.isFuture(t.scheduledDate!)) continue;
      final key = _recurringSeriesKey(t);
      if (key != null) keys.add(key);
    }
    return keys;
  }

  String? _recurringSeriesKey(Todo t) {
    if (t.recurrenceTemplateId != null) return t.recurrenceTemplateId;
    if (t.isRecurrenceTemplate) return t.id;
    return null;
  }

  /// Đánh dấu done ở state local — TodoTile sẽ render strikethrough ngay.
  void _markDoneLocally(String id) {
    List<Todo> applyDone(List<Todo> list) => list
        .map(
          (t) => t.id == id
              ? t.copyWith(status: TodoStatus.done, completedAt: DateTime.now())
              : t,
        )
        .toList();
    _today = applyDone(_today);
    _upcoming = applyDone(_upcoming);
    _overdue = applyDone(_overdue);
    _unscheduled = applyDone(_unscheduled);
  }

  void _moveCompletedTodoToDone(Todo completedTodo) {
    final id = completedTodo.id;
    _today.removeWhere((t) => t.id == id);
    _upcoming.removeWhere((t) => t.id == id);
    _overdue.removeWhere((t) => t.id == id);
    _unscheduled.removeWhere((t) => t.id == id);
    _done = _sortDoneNewestFirst([
      completedTodo,
      ..._done.where((t) => t.id != id),
    ]);
    _fadingIds.remove(id);
  }

  Future<void> _toggleDone(Todo t) async {
    // Uncomplete — chỉ refresh, không animate.
    if (t.isDone) {
      try {
        await TodosRepository.instance.uncomplete(t.id);
        if (mounted) _refresh();
      } on ApiException catch (e) {
        if (mounted) _showError(e.vnMessage);
      }
      return;
    }

    // Complete flow với fade animation.
    try {
      // 1. Strikethrough ngay lập tức (optimistic mark done).
      setState(() => _markDoneLocally(t.id));

      // 2. Delay nhỏ để user kịp nhìn strikethrough.
      await Future.delayed(_strikethroughDelay);
      if (!mounted) return;

      // 3. Trigger fade animation (heightFactor + opacity giảm về 0).
      setState(() => _fadingIds.add(t.id));

      // 4. Call API song song với animation.
      final apiFuture = TodosRepository.instance.complete(t.id);

      // 5. Chờ animation chạy xong.
      await Future.delayed(_fadeDuration);
      if (!mounted) return;

      // 6. Lấy kết quả API (đã xong từ trước).
      final result = await apiFuture;
      if (!mounted) return;

      // 7. Habit stacking popup nếu có triggered_todos.
      await showHabitStackingDialog(
        context,
        result.triggeredTodos,
        _openDetail,
      );
      if (!mounted) return;

      // 8. Move locally before clearing the fade state so the tile cannot
      // reappear in its old section while the refresh is still in flight.
      setState(() => _moveCompletedTodoToDone(result.todo));
      await _refresh();
    } on ApiException catch (e) {
      // Rollback animation state nếu API fail.
      if (mounted) {
        setState(() => _fadingIds.remove(t.id));
        _showError(e.vnMessage);
        _refresh(); // re-fetch để khôi phục trạng thái thật từ server
      }
    }
  }

  void _openDetail(Todo t) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: t.id)));
    if (mounted) _refresh();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const TodoCreateScreen()));
    if (created == true && mounted) _refresh();
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _filterTile(ctx, 'all', 'Tất cả'),
            _filterTile(ctx, 'today', 'Hôm nay'),
            _filterTile(ctx, 'important', 'Quan trọng'),
            _filterTile(ctx, 'done', 'Đã hoàn thành'),
          ],
        ),
      ),
    );
  }

  Widget _filterTile(BuildContext ctx, String value, String label) {
    // ignore: deprecated_member_use
    return RadioListTile<String>(
      value: value,
      // ignore: deprecated_member_use
      groupValue: _filter,
      title: Text(label),
      // ignore: deprecated_member_use
      onChanged: (v) {
        setState(() => _filter = v ?? 'all');
        Navigator.of(ctx).pop();
      },
    );
  }

  /// Lọc theo state _filter (client-side, không re-fetch).
  List<Todo> _applyFilter(List<Todo> list) {
    switch (_filter) {
      case 'important':
        return list.where((t) => t.isImportant == true).toList();
      default:
        return list;
    }
  }

  List<Todo> _sortDoneNewestFirst(List<Todo> todos) {
    final sorted = [...todos];
    sorted.sort((a, b) {
      final byDoneTime = _doneSortTime(b).compareTo(_doneSortTime(a));
      if (byDoneTime != 0) return byDoneTime;
      final byCreatedAt = b.createdAt.compareTo(a.createdAt);
      if (byCreatedAt != 0) return byCreatedAt;
      return b.id.compareTo(a.id);
    });
    return sorted;
  }

  DateTime _doneSortTime(Todo todo) {
    return todo.completedAt ?? todo.updatedAt;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  /// Wrap TodoTile với animation shrink + fade khi nằm trong _fadingIds.
  Widget _animatedTile(Todo t) {
    final isFading = _fadingIds.contains(t.id);
    return TweenAnimationBuilder<double>(
      key: ValueKey('tile_${t.id}'),
      tween: Tween<double>(begin: 1.0, end: isFading ? 0.0 : 1.0),
      duration: _fadeDuration,
      curve: Curves.easeInOut,
      builder: (ctx, value, child) {
        return ClipRect(
          child: Align(
            heightFactor: value.clamp(0.0, 1.0),
            alignment: Alignment.topCenter,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          ),
        );
      },
      child: TodoTile(
        todo: t,
        onToggleDone: () => _toggleDone(t),
        onTap: () => _openDetail(t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    if (_loading &&
        _today.isEmpty &&
        _upcoming.isEmpty &&
        _overdue.isEmpty &&
        _unscheduled.isEmpty &&
        _done.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final today = _filter == 'done' ? <Todo>[] : _applyFilter(_today);
    final upcoming = _filter == 'done' || _filter == 'today'
        ? <Todo>[]
        : _applyFilter(_upcoming);
    final overdue = _filter == 'done' || _filter == 'today'
        ? <Todo>[]
        : _applyFilter(_overdue);
    final unscheduled = _filter == 'done' || _filter == 'today'
        ? <Todo>[]
        : _applyFilter(_unscheduled);
    final done = _filter == 'today' ? <Todo>[] : _sortDoneNewestFirst(_done);

    final isEmpty =
        today.isEmpty &&
        upcoming.isEmpty &&
        overdue.isEmpty &&
        unscheduled.isEmpty &&
        done.isEmpty;
    if (isEmpty) {
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Chưa có việc nào',
        subtitle: 'Bấm dấu cộng để thêm việc đầu tiên.',
        buttonLabel: 'Thêm việc',
        onPressed: _openCreate,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Text(
                  _filterLabel(),
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.filter_list, size: 20),
                  onPressed: _openFilterSheet,
                ),
              ],
            ),
          ),
          if (overdue.isNotEmpty) ...[
            const SectionHeader(label: 'Quá hạn'),
            ...overdue.map(_animatedTile),
          ],
          if (today.isNotEmpty) ...[
            const SectionHeader(label: '⭐ Hôm nay'),
            ...today.map(_animatedTile),
          ],
          if (upcoming.isNotEmpty) ...[
            const SectionHeader(label: '📅 Sắp tới'),
            ...upcoming.map(_animatedTile),
          ],
          if (unscheduled.isNotEmpty) ...[
            const SectionHeader(label: '📋 Chưa lên lịch'),
            ...unscheduled.map(_animatedTile),
          ],
          if (done.isNotEmpty) ...[
            SectionHeader(
              label:
                  '✅ Đã xong (${done.length}${_doneCursor != null ? '+' : ''})',
              trailing: IconButton(
                icon: Icon(
                  _doneExpanded ? Icons.expand_less : Icons.expand_more,
                ),
                onPressed: () => setState(() => _doneExpanded = !_doneExpanded),
              ),
            ),
            if (_doneExpanded) ...done.map(_animatedTile),
          ],
        ],
      ),
    );
  }

  String _filterLabel() {
    switch (_filter) {
      case 'today':
        return 'Lọc: Hôm nay';
      case 'important':
        return 'Lọc: Quan trọng';
      case 'done':
        return 'Lọc: Đã hoàn thành';
      default:
        return 'Tất cả việc';
    }
  }
}
