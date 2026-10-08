import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/tags_repository.dart';
import '../../data/todos_repository.dart';
import '../../models/tag.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/featured_todo_tags.dart';
import '../../utils/habit_stacking_dialog.dart';
import '../../utils/json_utils.dart';
import '../../utils/todo_delete_dialog.dart';
import '../../utils/todo_local_events.dart';
import '../../utils/todo_time_utils.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/todo_swipe_actions.dart';
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

  /// Số lượt làm mới từ server đang chạy (cache đã hiện từ trước đó).
  int _inFlight = 0;
  bool _doneExpanded = false;
  String _filter = 'all';
  List<Tag> _tagFilters = [];
  List<Tag> _quickTags = [];

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
    TodoLocalEvents.instance.revision.addListener(_onLocalTodosChanged);
    _loadQuickTags();
    _refresh();
  }

  @override
  void dispose() {
    TodoLocalEvents.instance.revision.removeListener(_onLocalTodosChanged);
    super.dispose();
  }

  void _onLocalTodosChanged() {
    unawaited(_refreshLocal(allowEmpty: true));
    unawaited(_loadQuickTags());
  }

  Future<void> _loadQuickTags() async {
    final localTags = await TagsRepository.instance.listLocal(
      scope: 'todo',
      limit: 40,
    );
    if (!mounted) return;
    setState(() {
      _quickTags = _sortQuickTags(_dedupeTags([..._tagFilters, ...localTags]));
    });
    unawaited(_refreshQuickTagsRemote());
  }

  Future<void> _refreshQuickTagsRemote() async {
    try {
      final remoteTags = await TagsRepository.instance.list(
        scope: 'todo',
        limit: 40,
      );
      if (!mounted) return;
      setState(() {
        _quickTags = _sortQuickTags(
          _dedupeTags([..._tagFilters, ...remoteTags, ..._quickTags]),
        );
      });
    } on ApiException {
      // Quick filters are a local-first convenience; keep the cached list.
    }
  }

  /// Hiện ngay dữ liệu đã lưu trong SQLite, sau đó mới hỏi server và vẽ lại
  /// khi có kết quả.
  Future<void> _refresh() async {
    if (!_hasAnyTodos) setState(() => _loading = true);
    await _refreshLocal(allowEmpty: _hasAnyTodos);
    if (!mounted) return;
    setState(() => _inFlight++);
    try {
      // Fetch song song. "Đã xong" chỉ lấy top-level (parent_id null).
      final selectedTagIds = _tagFilters.map((tag) => tag.id).toSet();
      final hasPendingBefore = await TodosRepository.instance
          .hasPendingLocalWrites();
      final primaryTagId = selectedTagIds.isEmpty ? null : selectedTagIds.first;
      final today = TodosRepository.instance.getDay(DateTime.now());
      final all = TodosRepository.instance.list(
        limit: 100,
        tagId: primaryTagId,
      );
      final done = TodosRepository.instance.list(
        status: TodoStatus.done,
        parentId: 'null',
        limit: 20,
        tagId: primaryTagId,
      );
      final results = await Future.wait([today, all, done]);
      if (!mounted) return;
      final dayTodos = results[0] as List<DayTopLevelTodo>;
      final allRes = results[1] as ({List<Todo> items, String? nextCursor});
      final doneRes = results[2] as ({List<Todo> items, String? nextCursor});

      _applyTodoSections(
        allItems: allRes.items,
        todaySource: selectedTagIds.isEmpty
            ? dayTodos.map((d) => d.todo).toList()
            : allRes.items,
        doneItems: doneRes.items,
        doneCursor: doneRes.nextCursor,
      );
      final hasPendingAfter = await TodosRepository.instance
          .hasPendingLocalWrites();
      if (hasPendingBefore || hasPendingAfter) {
        await _refreshLocal(allowEmpty: true);
      }
    } on ApiException catch (e) {
      // Đã có dữ liệu cache để xem thì lỗi tạm thời (mất mạng, server đang
      // khởi động lại...) không đáng làm phiền người dùng.
      if (mounted && (!_hasAnyTodos || !e.isRetryable)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.vnMessage),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _inFlight--;
          _loading = false;
        });
      }
    }
  }

  bool get _revalidating => _inFlight > 0;

  bool get _hasAnyTodos =>
      _today.isNotEmpty ||
      _upcoming.isNotEmpty ||
      _overdue.isNotEmpty ||
      _unscheduled.isNotEmpty ||
      _done.isNotEmpty;

  Future<void> _refreshLocal({required bool allowEmpty}) async {
    final local = await TodosRepository.instance.listLocal(includeDone: true);
    if (!mounted) return;
    if (!allowEmpty && local.isEmpty) return;
    _applyTodoSections(
      allItems: local,
      todaySource: local,
      doneItems: local.where((todo) => todo.isDone).toList(),
      doneCursor: null,
    );
  }

  void _applyTodoSections({
    required List<Todo> allItems,
    required List<Todo> todaySource,
    required List<Todo> doneItems,
    required String? doneCursor,
  }) {
    if (!mounted) return;
    final selectedTagIds = _tagFilters.map((tag) => tag.id).toSet();
    final todayList =
        todaySource
            .where(
              (t) =>
                  !t.isDone &&
                  t.status != TodoStatus.archived &&
                  t.parentId == null &&
                  t.scheduledDate != null &&
                  AppDateUtils.isToday(t.scheduledDate!) &&
                  _matchesSelectedTags(t, selectedTagIds),
            )
            .toList()
          ..sort(_compareTodayTodos);
    final todayIds = todayList.map((t) => t.id).toSet();
    final blockedRecurringSeries = _activeRecurringSeriesKeys(
      todayList,
      allItems,
    );

    final upcoming = <Todo>[];
    final nearestUpcomingBySeries = <String, Todo>{};
    final overdue = <Todo>[];
    final unscheduled = <Todo>[];
    for (final t in allItems) {
      if (t.parentId != null) continue;
      if (t.status == TodoStatus.archived) continue;
      if (!_matchesSelectedTags(t, selectedTagIds)) continue;
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
    upcoming.sort(_compareUpcomingTodos);
    overdue.sort(_compareOverdueTodos);
    unscheduled.sort(_compareUnscheduledTodos);

    setState(() {
      _today = todayList;
      _upcoming = upcoming;
      _overdue = overdue;
      _unscheduled = unscheduled;
      _done = _sortDoneNewestFirst(
        doneItems
            .where(
              (todo) =>
                  todo.parentId == null &&
                  todo.status != TodoStatus.archived &&
                  _matchesSelectedTags(todo, selectedTagIds),
            )
            .toList(),
      );
      _doneCursor = doneCursor;
    });
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
      if (t.parentId != null ||
          t.isDone ||
          t.status == TodoStatus.archived ||
          t.scheduledDate == null) {
        continue;
      }
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

  bool _matchesSelectedTags(Todo todo, Set<String> selectedTagIds) {
    if (selectedTagIds.isEmpty) return true;
    final todoTagIds = {...todo.tagIds, for (final tag in todo.tags) tag.id};
    return selectedTagIds.every(todoTagIds.contains);
  }

  List<Tag> _dedupeTags(List<Tag> tags) {
    final seen = <String>{};
    final result = <Tag>[];
    for (final tag in tags) {
      if (!seen.add(tag.id)) continue;
      result.add(tag);
    }
    return result;
  }

  List<Tag> _sortQuickTags(List<Tag> tags) {
    final featuredOrder = <String, int>{
      for (var i = 0; i < featuredTodoTags.length; i++)
        normalizeFeaturedTodoTagName(featuredTodoTags[i].name): i,
    };
    final sorted = [...tags];
    sorted.sort((a, b) {
      final aOrder =
          featuredOrder[normalizeFeaturedTodoTagName(a.name)] ?? 9999;
      final bOrder =
          featuredOrder[normalizeFeaturedTodoTagName(b.name)] ?? 9999;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
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
        final reopened = await TodosRepository.instance.uncompleteLocalFirst(t);
        if (mounted) setState(() => _moveReopenedTodo(reopened));
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

      // 4. Ghi local-first và để sync nền đẩy lên server.
      final apiFuture = TodosRepository.instance.completeLocalFirst(t);

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
      setState(() {
        _moveCompletedTodoToDone(result.todo);
        final nextRecurringTodo = result.nextRecurringTodo;
        if (nextRecurringTodo != null) {
          _insertTodoIntoSection(nextRecurringTodo);
        }
      });
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
    if (mounted) {
      await _refreshLocal(allowEmpty: true);
      if (!mounted) return;
      final hasPending = await TodosRepository.instance.hasPendingLocalWrites();
      if (!hasPending) {
        unawaited(_refresh());
      }
      unawaited(_loadQuickTags());
    }
  }

  void _moveReopenedTodo(Todo reopened) {
    _done.removeWhere((t) => t.id == reopened.id);
    if (reopened.parentId != null) return;
    if (reopened.status == TodoStatus.archived) return;
    if (reopened.scheduledDate == null) {
      _unscheduled = [
        reopened,
        ..._unscheduled.where((t) => t.id != reopened.id),
      ]..sort(_compareUnscheduledTodos);
      return;
    }
    if (AppDateUtils.isToday(reopened.scheduledDate!)) {
      _today = [reopened, ..._today.where((t) => t.id != reopened.id)]
        ..sort(_compareTodayTodos);
    } else if (AppDateUtils.isFuture(reopened.scheduledDate!)) {
      _upcoming = [reopened, ..._upcoming.where((t) => t.id != reopened.id)]
        ..sort(_compareUpcomingTodos);
    } else {
      _overdue = [reopened, ..._overdue.where((t) => t.id != reopened.id)]
        ..sort(_compareOverdueTodos);
    }
  }

  void _removeTodoFromSections(String id) {
    _today.removeWhere((t) => t.id == id);
    _upcoming.removeWhere((t) => t.id == id);
    _overdue.removeWhere((t) => t.id == id);
    _unscheduled.removeWhere((t) => t.id == id);
    _done.removeWhere((t) => t.id == id);
  }

  void _insertTodoIntoSection(Todo todo) {
    if (todo.parentId != null) return;
    if (todo.status == TodoStatus.archived) return;
    final selectedTagIds = _tagFilters.map((tag) => tag.id).toSet();
    if (!_matchesSelectedTags(todo, selectedTagIds)) return;

    if (todo.isDone) {
      _done = _sortDoneNewestFirst([
        todo,
        ..._done.where((t) => t.id != todo.id),
      ]);
      return;
    }
    if (todo.scheduledDate == null) {
      _unscheduled = [todo, ..._unscheduled.where((t) => t.id != todo.id)]
        ..sort(_compareUnscheduledTodos);
      return;
    }
    if (AppDateUtils.isToday(todo.scheduledDate!)) {
      _today = [todo, ..._today.where((t) => t.id != todo.id)]
        ..sort(_compareTodayTodos);
    } else if (AppDateUtils.isFuture(todo.scheduledDate!)) {
      _upcoming = [todo, ..._upcoming.where((t) => t.id != todo.id)]
        ..sort(_compareUpcomingTodos);
    } else {
      _overdue = [todo, ..._overdue.where((t) => t.id != todo.id)]
        ..sort(_compareOverdueTodos);
    }
  }

  Future<void> _pickTodoDate(Todo todo) async {
    final initial = todo.scheduledDate ?? DateTime.now();
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

  Future<void> _changeTodoDateLocalFirst(Todo todo, DateTime date) async {
    final optimistic = todo.copyWith(
      scheduledDate: AppDateUtils.dateOnly(date),
      frogDate: todo.isFrog ? AppDateUtils.dateOnly(date) : todo.frogDate,
    );
    setState(() {
      _removeTodoFromSections(todo.id);
      _insertTodoIntoSection(optimistic);
    });
    try {
      final updated = await TodosRepository.instance.updateLocalFirst(todo, {
        'scheduled_date': formatDateOnly(date),
        'due_at': formatEndOfDayIso(date),
        if (todo.isFrog) 'frog_date': formatDateOnly(date),
      });
      if (!mounted) return;
      setState(() {
        _removeTodoFromSections(todo.id);
        _insertTodoIntoSection(updated);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã đổi ngày')));
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.vnMessage);
      await _refreshLocal(allowEmpty: true);
      if (mounted) unawaited(_refresh());
    }
  }

  Future<void> _pickTodoTime(Todo todo) async {
    if (todo.parentId != null) return;
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

  Future<DateTime?> _pickDateBeforeTime(Todo todo) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chọn ngày làm trước khi đặt giờ')),
    );
    final initial = todo.scheduledDate ?? DateTime.now();
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
    Todo todo,
    String? time, {
    DateTime? scheduledDate,
  }) async {
    final optimistic = todo.copyWith(
      scheduledDate: scheduledDate ?? todo.scheduledDate,
      time: time,
      frogDate: scheduledDate != null && todo.isFrog
          ? scheduledDate
          : todo.frogDate,
    );
    setState(() {
      _removeTodoFromSections(todo.id);
      _insertTodoIntoSection(optimistic);
    });
    try {
      final updated = await TodosRepository.instance.updateLocalFirst(todo, {
        if (scheduledDate != null) ...{
          'scheduled_date': formatDateOnly(scheduledDate),
          'due_at': formatEndOfDayIso(scheduledDate),
          if (todo.isFrog) 'frog_date': formatDateOnly(scheduledDate),
        },
        'time': time,
      });
      if (!mounted) return;
      setState(() {
        _removeTodoFromSections(todo.id);
        _insertTodoIntoSection(updated);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã đổi giờ')));
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.vnMessage);
      await _refreshLocal(allowEmpty: true);
      if (mounted) unawaited(_refresh());
    }
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

  Future<void> _deleteTodoLocalFirst(Todo todo) async {
    final scope = await showTodoDeleteScopeDialog(context, todo);
    if (scope == null || !mounted) return;
    setState(() => _removeTodoFromSections(todo.id));
    try {
      await TodosRepository.instance.deleteTodoLocalFirst(todo, scope: scope);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xóa todo')));
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.vnMessage);
      _refresh();
    } catch (_) {
      if (!mounted) return;
      _showError('Không thể xóa todo');
      _refresh();
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const TodoCreateScreen()));
    if (created == true && mounted) {
      _refresh();
      unawaited(_loadQuickTags());
    }
  }

  void _selectAllQuickFilter() {
    final shouldRefresh = _tagFilters.isNotEmpty;
    setState(() {
      _filter = 'all';
      _tagFilters = const [];
    });
    if (shouldRefresh) _refresh();
  }

  void _selectQuickFilter(String value) {
    final shouldRefresh = value == 'untagged' && _tagFilters.isNotEmpty;
    setState(() {
      _filter = value;
      if (value == 'untagged') _tagFilters = const [];
    });
    if (shouldRefresh) _refresh();
  }

  void _toggleQuickTag(Tag tag) {
    setState(() {
      if (_tagFilters.any((item) => item.id == tag.id)) {
        _tagFilters = _tagFilters.where((item) => item.id != tag.id).toList();
      } else {
        _tagFilters = _dedupeTags([..._tagFilters, tag]);
      }
      if (_filter == 'untagged') _filter = 'all';
      _quickTags = _sortQuickTags(_dedupeTags([tag, ..._quickTags]));
    });
    _refresh();
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _TodoFilterSheet(
        filter: _filter,
        tagFilters: _tagFilters,
        onFilterChanged: (value) {
          final shouldRefresh = value == 'untagged' && _tagFilters.isNotEmpty;
          setState(() {
            _filter = value;
            if (value == 'untagged') _tagFilters = const [];
          });
          Navigator.of(ctx).pop();
          if (shouldRefresh) _refresh();
        },
        onTagsChanged: (tags) {
          setState(() {
            _tagFilters = tags;
            if (tags.isNotEmpty && _filter == 'untagged') _filter = 'all';
            _quickTags = _sortQuickTags(_dedupeTags([...tags, ..._quickTags]));
          });
          Navigator.of(ctx).pop();
          unawaited(_loadQuickTags());
          _refresh();
        },
        onClearTags: () {
          setState(() => _tagFilters = const []);
          Navigator.of(ctx).pop();
          _refresh();
        },
      ),
    );
  }

  /// Lọc theo state _filter (client-side, không re-fetch).
  List<Todo> _applyFilter(List<Todo> list) {
    switch (_filter) {
      case 'important':
        return list.where((t) => t.isImportant == true).toList();
      case 'untagged':
        return list.where(_isUncategorizedTodo).toList();
      default:
        return list;
    }
  }

  bool _isUncategorizedTodo(Todo todo) {
    return todo.tagIds.isEmpty && todo.tags.isEmpty;
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

  int _compareTodayTodos(Todo a, Todo b) {
    return _compareTimeFirst(a, b, () => a.createdAt.compareTo(b.createdAt));
  }

  int _compareUpcomingTodos(Todo a, Todo b) {
    final byDate = a.scheduledDate!.compareTo(b.scheduledDate!);
    if (byDate != 0) return byDate;
    return _compareTimeFirst(a, b, () => a.createdAt.compareTo(b.createdAt));
  }

  int _compareOverdueTodos(Todo a, Todo b) {
    return _compareTimeFirst(a, b, () {
      final byDate = b.scheduledDate!.compareTo(a.scheduledDate!);
      if (byDate != 0) return byDate;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  int _compareUnscheduledTodos(Todo a, Todo b) {
    return _compareTimeFirst(a, b, () => b.createdAt.compareTo(a.createdAt));
  }

  int _compareTimeFirst(Todo a, Todo b, int Function() fallback) {
    final byTime = compareTodoTimes(a.time, b.time);
    return byTime != 0 ? byTime : fallback();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: _TodoQuickFilterBar(
              filter: _filter,
              quickTags: _quickTags,
              tagFilters: _tagFilters,
              onAllSelected: _selectAllQuickFilter,
              onFilterChanged: _selectQuickFilter,
              onTagToggled: _toggleQuickTag,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, size: 20),
            color: _tagFilters.isNotEmpty || _filter != 'all'
                ? AppColors.primary
                : null,
            onPressed: _openFilterSheet,
          ),
        ],
      ),
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
      child: TodoSwipeActions(
        onPickDate: () => _pickTodoDate(t),
        onPickTime: () => _pickTodoTime(t),
        onDelete: () => _deleteTodoLocalFirst(t),
        child: TodoTile(
          todo: t,
          onToggleDone: () => _toggleDone(t),
          onTap: () => _openDetail(t),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    final done = _filter == 'today'
        ? <Todo>[]
        : _filter == 'done'
        ? _sortDoneNewestFirst(_done)
        : _sortDoneNewestFirst(_applyFilter(_done));

    final isEmpty =
        today.isEmpty &&
        upcoming.isEmpty &&
        overdue.isEmpty &&
        unscheduled.isEmpty &&
        done.isEmpty;
    final hasActiveFilters = _filter != 'all' || _tagFilters.isNotEmpty;
    if (isEmpty && !hasActiveFilters) {
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Chưa có việc nào',
        subtitle: 'Bấm dấu cộng để thêm việc đầu tiên.',
        buttonLabel: 'Thêm việc',
        onPressed: _openCreate,
      );
    }

    final list = RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _buildFilterRow(),
          if (isEmpty)
            const EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'Không có việc phù hợp',
              subtitle: 'Chọn Tất cả hoặc đổi bộ lọc để xem việc khác.',
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
    if (!_revalidating) return list;
    // Đang hiện dữ liệu cache trong lúc hỏi server: báo nhẹ, không che nội dung.
    return Stack(
      fit: StackFit.expand,
      children: [
        list,
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ],
    );
  }
}

class _TodoQuickFilterBar extends StatelessWidget {
  final String filter;
  final List<Tag> quickTags;
  final List<Tag> tagFilters;
  final VoidCallback onAllSelected;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<Tag> onTagToggled;

  const _TodoQuickFilterBar({
    required this.filter,
    required this.quickTags,
    required this.tagFilters,
    required this.onAllSelected,
    required this.onFilterChanged,
    required this.onTagToggled,
  });

  @override
  Widget build(BuildContext context) {
    final selectedTagIds = tagFilters.map((tag) => tag.id).toSet();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(
            label: 'Tất cả',
            selected: filter == 'all' && selectedTagIds.isEmpty,
            onTap: onAllSelected,
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: 'Chưa phân loại',
            selected: filter == 'untagged' && selectedTagIds.isEmpty,
            icon: Icons.label_off_outlined,
            onTap: () => onFilterChanged('untagged'),
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: 'Hôm nay',
            selected: filter == 'today',
            icon: Icons.today_outlined,
            color: AppColors.primary,
            onTap: () => onFilterChanged('today'),
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: 'Quan trọng',
            selected: filter == 'important',
            icon: Icons.star_rounded,
            color: AppColors.warning,
            onTap: () => onFilterChanged('important'),
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: 'Đã xong',
            selected: filter == 'done',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
            onTap: () => onFilterChanged('done'),
          ),
          for (final tag in quickTags) ...[
            const SizedBox(width: 8),
            _tagFilterChip(
              tag: tag,
              selected: selectedTagIds.contains(tag.id),
              onTap: () => onTagToggled(tag),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? color,
  }) {
    final chipColor = color ?? AppColors.primary;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: selected ? Colors.white : chipColor),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      selected: selected,
      selectedColor: chipColor,
      labelStyle: TextStyle(color: selected ? Colors.white : null),
      onSelected: (_) => onTap(),
    );
  }

  Widget _tagFilterChip({
    required Tag tag,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = tag.color;
    final featured = featuredTodoTagForName(tag.name);
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      avatar: featured == null
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: selected ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            )
          : Icon(
              featured.icon,
              size: 16,
              color: selected ? Colors.white : color,
            ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: Text(tag.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : color,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: selected ? 1 : 0.28)),
    );
  }
}

class _TodoFilterSheet extends StatefulWidget {
  final String filter;
  final List<Tag> tagFilters;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<List<Tag>> onTagsChanged;
  final VoidCallback onClearTags;

  const _TodoFilterSheet({
    required this.filter,
    required this.tagFilters,
    required this.onFilterChanged,
    required this.onTagsChanged,
    required this.onClearTags,
  });

  @override
  State<_TodoFilterSheet> createState() => _TodoFilterSheetState();
}

class _TodoFilterSheetState extends State<_TodoFilterSheet> {
  List<Tag> _tags = [];
  late List<Tag> _selectedTags;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedTags = _dedupeTags(widget.tagFilters);
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await TagsRepository.instance.list(scope: 'todo');
      if (mounted) setState(() => _tags = tags);
    } on ApiException {
      if (mounted) setState(() => _tags = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleTag(Tag tag) {
    setState(() {
      if (_selectedTags.any((item) => item.id == tag.id)) {
        _selectedTags = _selectedTags
            .where((item) => item.id != tag.id)
            .toList();
      } else {
        _selectedTags = _dedupeTags([..._selectedTags, tag]);
      }
    });
  }

  List<Tag> _dedupeTags(List<Tag> tags) {
    final seen = <String>{};
    final result = <Tag>[];
    for (final tag in tags) {
      if (seen.contains(tag.id)) continue;
      seen.add(tag.id);
      result.add(tag);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Text(
              'Bộ lọc',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _filterTile('all', 'Tất cả'),
            _filterTile('untagged', 'Chưa phân loại'),
            _filterTile('today', 'Hôm nay'),
            _filterTile('important', 'Quan trọng'),
            _filterTile('done', 'Đã hoàn thành'),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_offer_outlined),
              title: Text(
                _selectedTags.isEmpty
                    ? 'Tags'
                    : 'Tags (${_selectedTags.length})',
              ),
              trailing: _selectedTags.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _selectedTags = []),
                    ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in _tags)
                    _FilterTagChip(
                      tag: tag,
                      selected: _selectedTags.any((item) => item.id == tag.id),
                      onTap: () => _toggleTag(tag),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectedTags.isEmpty
                        ? null
                        : widget.onClearTags,
                    icon: const Icon(Icons.clear),
                    label: const Text('Bỏ lọc tag'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => widget.onTagsChanged(_selectedTags),
                    icon: const Icon(Icons.check),
                    label: Text(
                      _selectedTags.isEmpty
                          ? 'Áp dụng'
                          : 'Áp dụng ${_selectedTags.length} tag',
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

  Widget _filterTile(String value, String label) {
    final selected = widget.filter == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.primary : null,
      ),
      title: Text(label),
      onTap: () => widget.onFilterChanged(value),
    );
  }
}

class _FilterTagChip extends StatelessWidget {
  final Tag tag;
  final bool selected;
  final VoidCallback onTap;

  const _FilterTagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle),
      ),
      label: Text(tag.name),
      labelStyle: TextStyle(
        color: selected ? tag.color : null,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      selectedColor: tag.color.withValues(alpha: 0.16),
      checkmarkColor: tag.color,
      side: BorderSide(color: tag.color.withValues(alpha: 0.32)),
    );
  }
}
