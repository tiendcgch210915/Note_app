import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../models/todo.dart';
import '../models/recurring_todo_delete_scope.dart';
import '../utils/dashboard_local_events.dart';
import '../utils/json_utils.dart';
import '../utils/frog_completion_events.dart';
import '../utils/recurrence_helper.dart';
import '../utils/todo_local_events.dart';
import '../utils/todo_trigger_candidates.dart';
import '../utils/uuid_utils.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_storage.dart';
import 'habits_repository.dart';
import 'local/database.dart';
import 'local/model_converters.dart';
import 'tags_repository.dart';
import '../sync/connectivity_sync.dart';
import '../sync/sync_payload.dart';
import '../sync/sync_worker.dart';

/// Repository cho Group T — Todos.
///
/// Strategy:
///  - All reads: REST (online) – Drift used by SyncWorker pull to populate cache
///  - All writes: REST first; on success → write to Drift + enqueue sync_queue
///               On no_connection → write to Drift + enqueue (offline mode)
///  - After any write → ConnectivitySync.scheduleWriteSync()
class TodosRepository {
  TodosRepository._({
    ApiClient? client,
    AppDatabase? database,
    String? userIdOverride,
  }) : _client = client ?? ApiClient.instance,
       _db = database ?? AppDatabase.instance,
       _userIdOverride = userIdOverride;
  static final TodosRepository instance = TodosRepository._();
  final ApiClient _client;
  final AppDatabase _db;
  final String? _userIdOverride;

  /// Per-series queue used by [_withSeriesLock].
  final Map<String, Future<void>> _seriesLocks = {};

  factory TodosRepository.forTesting(
    AppDatabase database, {
    required String userId,
    ApiClient? client,
  }) {
    return TodosRepository._(
      client: client,
      database: database,
      userIdOverride: userId,
    );
  }

  String get _userId =>
      _userIdOverride ??
      AuthStorage.instance.currentUserJson?['id'] as String? ??
      '';

  bool _belongsToCurrentUser(String rowUserId) {
    final userId = _userId;
    return userId.isEmpty || rowUserId == userId;
  }

  Future<bool> hasPendingLocalWrites() async {
    return (await _db.syncDao.getPendingCount()) > 0;
  }

  void _notifyTodoLocalChanged() {
    TodoLocalEvents.instance.notifyChanged();
    DashboardLocalEvents.instance.notifyChanged();
  }

  // ─── F-T2 List ────────────────────────────────────────────────

  Future<({List<Todo> items, String? nextCursor})> list({
    String? cursor,
    int? limit,
    DateTime? scheduledDate,
    TodoStatus? status,
    bool? isFrog,
    String? parentId,
    String? q,
    String? tag,
    String? tagId,
    String? habitId,
  }) async {
    final query = <String, dynamic>{
      if (cursor != null) 'cursor': cursor,
      if (limit != null) 'limit': limit,
      if (scheduledDate != null)
        'scheduled_date': formatDateOnly(scheduledDate),
      if (status != null) 'status': status.backendValue,
      if (isFrog != null) 'is_frog': isFrog,
      if (parentId != null) 'parent_id': parentId,
      if (q != null && q.isNotEmpty) 'q': q,
      if (tagId != null && tagId.isNotEmpty) 'tag_id': tagId,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
      if (habitId != null && habitId.isNotEmpty) 'habit_id': habitId,
    };
    final resp = await _client.get('/todos', query: query);
    final map = resp as Map<String, dynamic>;
    final items = (map['items'] as List)
        .map((e) => _normalizeSubtask(Todo.fromJson(e as Map<String, dynamic>)))
        .toList();
    // Cache in Drift (parked rows included: they are real rows, see below).
    await _cacheTodos(items);
    return (
      items: _withoutParked(items, unlessAsking: status),
      nextCursor: map['nextCursor'] as String?,
    );
  }

  /// `GET /todos` and `GET /todos/day/:date` return parked occurrences
  /// (`archived`, see [_parkGeneratedNextOccurrence]) like any other row. They
  /// are hidden bookkeeping, so callers never see them unless they explicitly
  /// ask for `status=archived`. They stay in the Drift cache so the next
  /// completion can revive the very same row.
  List<Todo> _withoutParked(List<Todo> todos, {TodoStatus? unlessAsking}) {
    if (unlessAsking == TodoStatus.archived) return todos;
    return todos.where((todo) => todo.status != TodoStatus.archived).toList();
  }

  Future<List<Todo>> listTriggerCandidates({String? excludeId}) async {
    try {
      final resp = await list(limit: 100);
      return filterTodoTriggerCandidates(resp.items, excludeId: excludeId);
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final rows = await _db.todosDao.getAllNonDeletedTodos();
      return filterTodoTriggerCandidates(
        rows
            .where((row) => _belongsToCurrentUser(row.userId))
            .map(_todoRowToModel)
            .where((todo) => !_isLegacyRecurrenceProjection(todo))
            .toList(),
        excludeId: excludeId,
      );
    }
  }

  Future<String?> getTodoTitle(String id) async {
    final cached = await _db.todosDao.getTodoById(id);
    if (cached != null) return cached.title;
    try {
      final detail = await getDetail(id);
      return detail.todo.title;
    } on ApiException {
      return null;
    }
  }

  // ─── F-T3 Day list ────────────────────────────────────────────

  Future<List<DayTopLevelTodo>> getDay(DateTime date) async {
    final resp = await _client.get('/todos/day/${formatDateOnly(date)}');
    final items = (resp as Map<String, dynamic>)['items'] as List;
    final result = items.map((e) {
      final item = DayTopLevelTodo.fromJson(e as Map<String, dynamic>);
      return DayTopLevelTodo(
        todo: _normalizeSubtask(item.todo),
        hasSubtasks: item.hasSubtasks,
      );
    }).toList();
    await _cacheTodos(result.map((d) => d.todo).toList());
    return result
        .where((item) => item.todo.status != TodoStatus.archived)
        .toList();
  }

  // ─── F-T4 Detail ──────────────────────────────────────────────

  Future<TodoWithRelations> getDetail(String id) async {
    final resp = await _client.get('/todos/$id');
    final parsed = TodoWithRelations.fromJson(resp as Map<String, dynamic>);
    final result = TodoWithRelations(
      todo: _normalizeSubtask(parsed.todo),
      tags: parsed.todo.parentId == null ? parsed.tags : const [],
      subtasks: parsed.subtasks.map(_normalizeSubtask).toList(),
      linkedNotes: parsed.todo.parentId == null ? parsed.linkedNotes : const [],
    );
    await _cacheTodoWithTags(result.todo, result.tags);
    await _cacheTodos(result.subtasks);
    final cached = await getLocalDetail(id);
    if (cached == null) return result;
    return TodoWithRelations(
      todo: result.todo,
      tags: result.tags,
      subtasks: cached.subtasks,
      linkedNotes: result.linkedNotes,
    );
  }

  Future<TodoWithRelations?> getLocalDetail(String id) async {
    final row = await _db.todosDao.getTodoById(id);
    if (row == null) return null;
    if (!_belongsToCurrentUser(row.userId)) return null;
    final baseTodo = _todoRowToModel(row);
    final subtasks = await _db.todosDao.getActiveSubtree(
      id,
      userId: row.userId,
    );
    final tags = baseTodo.parentId == null
        ? await _db.todosDao.getTagsForTodo(id)
        : const <TagRow>[];
    final tagModels = tags.map(_tagRowToModel).toList();
    final todo = baseTodo.copyWith(
      tags: tagModels,
      tagIds: tagModels.map((tag) => tag.id).toList(),
      tagsLoaded: true,
    );
    return TodoWithRelations(
      todo: todo,
      tags: tagModels,
      subtasks: subtasks.map(_todoRowToModel).toList(),
      linkedNotes: const [],
    );
  }

  Future<List<Todo>> reorderSubtasksLocalFirst({
    required String parentId,
    required List<String> orderedIds,
  }) async {
    final rows = await _db.todosDao.getSubtasks(parentId);
    if (rows.isEmpty || orderedIds.isEmpty) return const [];

    final byId = {for (final row in rows) row.id: row};
    final currentIds = byId.keys.toSet();
    final incomingIds = orderedIds.toSet();
    if (currentIds.length != incomingIds.length ||
        !currentIds.containsAll(incomingIds)) {
      throw const ApiException(400, 'bad_input', 'bad_input');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    var changed = false;
    for (var i = 0; i < orderedIds.length; i++) {
      final row = byId[orderedIds[i]]!;
      if (!_belongsToCurrentUser(row.userId) || row.position == i) continue;
      await _db.todosDao.updateTodoPosition(
        row.id,
        userId: row.userId,
        position: i,
        updatedAtIso: now,
      );
      await _enqueueTodoUpdate(row.id);
      changed = true;
    }

    final reordered = await _db.todosDao.getSubtasks(parentId);
    if (changed) {
      _notifyTodoLocalChanged();
      ConnectivitySync.instance.scheduleWriteSync();
    }
    return reordered.map(_todoRowToModel).toList(growable: false);
  }

  // ─── F-T1 Create ──────────────────────────────────────────────

  Future<TodoWithRelations> create(Map<String, dynamic> body) async {
    final writeBody = _ensureDonePatchHasCompletedAt(
      _normalizeTodoWriteBody(body, requireScheduledForTime: true),
      DateTime.now().toUtc(),
    );
    try {
      final resp = await _client.post('/todos', body: writeBody);
      final result = TodoWithRelations.fromJson(resp as Map<String, dynamic>);
      // Server already has this — cache locally only, do NOT enqueue.
      await _cacheTodoWithTags(result.todo, result.tags);
      // If a recurrence template was just created, generate instances.
      if (result.todo.isRecurrenceTemplate) {
        await _ensureInstancesExist(result.todo);
      }
      return result;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') {
        return _createOffline(writeBody);
      }
      rethrow;
    }
  }

  Future<TodoWithRelations> createLocalFirst(Map<String, dynamic> body) async {
    return _createOffline(
      _normalizeTodoWriteBody(body, requireScheduledForTime: true),
    );
  }

  /// Creates todo locally when offline. Returns optimistic result.
  Future<TodoWithRelations> _createOffline(Map<String, dynamic> body) async {
    final now = DateTime.now().toUtc();
    final id = newId();
    final parentId = body['parent_id'] as String?;
    final tags = parentId == null
        ? await _resolveTagsForLocalBody(body)
        : const <Tag>[];
    final position = body.containsKey('position')
        ? (body['position'] as num?)?.toInt() ?? 0
        : parentId == null
        ? 0
        : await _nextSubtaskPosition(parentId);
    final todo = Todo(
      id: id,
      title: body['title'] as String,
      description: body['description'] as String?,
      parentId: parentId,
      scheduledDate: body['scheduled_date'] != null
          ? jsonDateOnlyNullable(body['scheduled_date'] as String?)
          : null,
      status: TodoStatus.open,
      position: position,
      isFrog: body['is_frog'] as bool? ?? false,
      frogDate: body['frog_date'] != null
          ? jsonDateOnlyNullable(body['frog_date'] as String?)
          : null,
      isImportant: body['is_important'] as bool?,
      isUrgent: body['is_urgent'] as bool?,
      estimatedMinutes: (body['estimated_minutes'] as num?)?.toInt(),
      dueAt: body['due_at'] != null ? _dateTimeFromJson(body['due_at']) : null,
      time: parentId == null && body['scheduled_date'] != null
          ? body['time'] as String?
          : null,
      triggerAfterTodoId: body['trigger_after_todo_id'] as String?,
      habitId: parentId == null ? body['habit_id'] as String? : null,
      tags: tags,
      tagIds: tags.map((tag) => tag.id).toList(),
      tagsLoaded: true,
      createdAt: now,
      updatedAt: now,
      recurrenceType: body['recurrence_type'] as String?,
      recurrenceInterval: (body['recurrence_interval'] as num?)?.toInt() ?? 1,
      recurrenceDaysOfWeek: body['recurrence_days_of_week'] as String?,
      recurrenceEndDate: body['recurrence_end_date'] as String?,
    );
    final normalizedTodo = _normalizeSubtask(todo);
    await _upsertTodoWithSync(normalizedTodo, tags, 'create');
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
    return TodoWithRelations(
      todo: normalizedTodo,
      tags: tags,
      subtasks: const [],
      linkedNotes: const [],
    );
  }

  // ─── F-T5 Update ──────────────────────────────────────────────

  Future<Todo> update(String id, Map<String, dynamic> body) async {
    final writeBody = _ensureDonePatchHasCompletedAt(
      _normalizeTodoWriteBody(body),
      DateTime.now().toUtc(),
    );
    try {
      final resp = await _client.patch('/todos/$id', body: writeBody);
      final todo = _normalizeSubtask(
        Todo.fromJson(
          (resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>,
        ),
      );
      // Server already has this — cache locally only, do NOT enqueue.
      await _cacheTodos([todo]);
      if (todo.isRecurrenceTemplate) {
        await _ensureInstancesExist(todo);
      }
      _notifyTodoLocalChanged();
      return todo;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') {
        await _enqueueOfflineUpdate(id, writeBody);
        rethrow; // UI handles re-render
      }
      rethrow;
    }
  }

  Future<Todo> updateLocalFirst(Todo current, Map<String, dynamic> body) async {
    final localNow = DateTime.now();
    final nowUtc = localNow.toUtc();
    final nowIsoString = nowUtc.toIso8601String();
    final writeBody = _ensureDonePatchHasCompletedAt(
      _normalizeTodoWriteBody(
        body,
        current: current,
        requireScheduledForTime: true,
      ),
      nowUtc,
    );
    final updated = _normalizeSubtask(_patchTodo(current, writeBody, nowUtc));
    final recurrenceChanged = _patchTouchesRecurrence(writeBody);
    final recurrenceScheduleChanged =
        recurrenceChanged || writeBody.containsKey('scheduled_date');

    await _db.todosDao.upsertTodo(todoToCompanion(updated, _userId));
    final clearedFrogIds = await _clearOtherLocalFrogsForTodo(
      updated,
      updatedAtIso: nowIsoString,
    );

    if (current.isRecurrenceTemplate && recurrenceScheduleChanged) {
      final today = DateTime(localNow.year, localNow.month, localNow.day);
      await _softDeleteFutureInstancesForLocalEdit(
        current.id,
        formatDateOnly(today),
      );
    }

    for (final id in clearedFrogIds) {
      await _enqueueTodoUpdate(id);
    }
    await _enqueueTodoUpdate(updated.id);

    if (updated.isRecurrenceTemplate && recurrenceScheduleChanged) {
      await _ensureInstancesExist(updated);
    }

    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
    return updated;
  }

  Future<Todo> setTodoFrogLocalFirst(
    Todo current, {
    required bool enabled,
    DateTime? date,
  }) async {
    if (!enabled) {
      return updateLocalFirst(current, const {
        'is_frog': false,
        'frog_date': null,
      });
    }
    final frogDate = date ?? current.scheduledDate;
    if (frogDate == null) {
      throw const ApiException(400, 'bad_input', 'bad_input');
    }
    return updateLocalFirst(current, {
      'is_frog': true,
      'frog_date': formatDateOnly(frogDate),
      'is_important': true,
      'is_urgent': true,
    });
  }

  // ─── F-T6 Delete ──────────────────────────────────────────────

  Future<void> deleteTodoLocalFirst(
    Todo todo, {
    required RecurringTodoDeleteScope scope,
  }) async {
    await _applyTodoDeleteLocal(todo, scope: scope, enqueueDelete: true);
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
  }

  Future<void> deleteTodoRemote(
    Todo todo, {
    required RecurringTodoDeleteScope scope,
  }) async {
    await _client.delete('/todos/${todo.id}', query: {'scope': scope.apiValue});
    await _applyTodoDeleteLocal(todo, scope: scope, enqueueDelete: false);
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
  }

  Future<void> _applyTodoDeleteLocal(
    Todo todo, {
    required RecurringTodoDeleteScope scope,
    required bool enqueueDelete,
  }) async {
    final selected = await _db.todosDao.getTodoById(todo.id);
    if (selected == null || !_belongsToCurrentUser(selected.userId)) {
      throw const ApiException(404, 'not_found', 'not_found');
    }

    final deletedAt = nowIso();
    final seriesId = todo.recurrenceTemplateId ?? todo.id;
    var deletedIds = const <String>[];
    var cappedIds = const <String>[];
    String? cutoffDate;
    switch (scope) {
      case RecurringTodoDeleteScope.thisOccurrence:
        deletedIds = await _db.todosDao.softDeleteTodoTree(
          todo.id,
          selected.userId,
          deletedAt,
        );
        break;
      case RecurringTodoDeleteScope.thisAndFuture:
        final scheduledDate = todo.scheduledDate;
        if (scheduledDate == null) {
          throw const ApiException(400, 'bad_input', 'bad_input');
        }
        final cutoff = DateTime.utc(
          scheduledDate.year,
          scheduledDate.month,
          scheduledDate.day,
        ).subtract(const Duration(days: 1));
        cutoffDate = formatDateOnly(cutoff);
        final result = await _db.todosDao.softDeleteSeriesFromDate(
          seriesId: seriesId,
          userId: selected.userId,
          fromDateInclusive: formatDateOnly(scheduledDate),
          recurrenceEndDate: cutoffDate,
          deletedAtIso: deletedAt,
        );
        deletedIds = result.deletedIds;
        cappedIds = result.cappedIds;
        break;
      case RecurringTodoDeleteScope.all:
        deletedIds = await _db.todosDao.softDeleteEntireSeries(
          seriesId: seriesId,
          userId: selected.userId,
          deletedAtIso: deletedAt,
        );
        break;
    }

    for (final id in deletedIds) {
      await _db.syncDao.removeOpsForEntity('todo', id, userId: _userId);
    }
    if (cutoffDate != null) {
      await _db.syncDao.patchPendingTodoRecurrenceEndDate(
        cappedIds,
        userId: _userId,
        recurrenceEndDate: cutoffDate,
        updatedAt: deletedAt,
      );
    }

    if (enqueueDelete) {
      await _db.syncDao.enqueueSyncOp(
        userId: _userId,
        entityType: 'todo',
        entityId: todo.id,
        operation: 'delete',
        payload: SyncPayload.encode(
          SyncPayload.fromTodoDelete(
            id: todo.id,
            scope: scope,
            deletedAt: deletedAt,
          ),
        ),
      );
    }

    if (scope == RecurringTodoDeleteScope.thisOccurrence &&
        todo.parentId == null &&
        todo.isRecurring) {
      await _materializeNextRecurringOccurrence(todo, syncCreate: false);
    }
  }

  // ─── F-T7 Complete ────────────────────────────────────────────

  Future<({Todo todo, List<Todo> triggeredTodos, Todo? nextRecurringTodo})>
  complete(String id, {int? actualMinutes, bool celebrateFrog = true}) async {
    final before = await _db.todosDao.getTodoById(id);
    final wasDone = before?.status == TodoStatus.done.backendValue;
    final body = <String, dynamic>{
      if (actualMinutes != null) 'actual_minutes': actualMinutes,
    };
    try {
      final resp = await _client.post('/todos/$id/complete', body: body);
      final map = resp as Map<String, dynamic>;
      final triggeredList = (map['triggered_todos'] as List?) ?? const [];
      final nextRecurringJson =
          map['next_recurring_todo'] as Map<String, dynamic>?;
      final todo = _normalizeSubtask(
        Todo.fromJson(map['todo'] as Map<String, dynamic>),
      );
      final triggeredTodos = triggeredList
          .map(
            (e) => _normalizeSubtask(Todo.fromJson(e as Map<String, dynamic>)),
          )
          .toList();
      final nextRecurringTodo = nextRecurringJson == null
          ? null
          : _normalizeSubtask(Todo.fromJson(nextRecurringJson));
      // Write to Drift cache (no enqueue — server already has it).
      await _cacheTodos([
        todo,
        ...triggeredTodos,
        if (nextRecurringTodo != null) nextRecurringTodo,
      ]);
      if (celebrateFrog) {
        _celebrateFrogCompletionIfNeeded(todo, wasDone: wasDone);
      }
      _notifyTodoLocalChanged();
      ConnectivitySync.instance.scheduleWriteSync();
      if (nextRecurringTodo != null) {
        unawaited(SyncWorker.instance.pullChanges());
      }
      return (
        todo: todo,
        triggeredTodos: triggeredTodos,
        nextRecurringTodo: nextRecurringTodo,
      );
    } on ApiException catch (e) {
      if (e.code == 'no_connection') {
        return _completeOffline(
          id,
          actualMinutes: actualMinutes,
          celebrateFrog: celebrateFrog,
        );
      }
      rethrow;
    }
  }

  // ─── F-T8 Uncomplete ──────────────────────────────────────────

  Future<Todo> uncomplete(String id) async {
    final resp = await _client.post('/todos/$id/uncomplete', body: const {});
    final todo = _normalizeSubtask(
      Todo.fromJson(
        (resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>,
      ),
    );
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
    return todo;
  }

  Future<({Todo todo, List<Todo> triggeredTodos, Todo? nextRecurringTodo})>
  completeLocalFirst(
    Todo current, {
    int? actualMinutes,
    bool celebrateFrog = true,
  }) async {
    final now = DateTime.now().toUtc();
    final body = <String, dynamic>{
      'status': TodoStatus.done.backendValue,
      'completed_at': now,
      'actual_minutes': actualMinutes ?? current.actualMinutes,
    };
    // `current` is whatever the screen was holding; a second tap or a sync pull
    // may already have completed the row, and that must not spawn another next.
    final alreadyDone = current.isDone || await _isStoredDone(current.id);
    final completed = _normalizeSubtask(_patchTodo(current, body, now));
    await _db.todosDao.upsertTodo(todoToCompanion(completed, _userId));
    await _enqueueTodoUpdate(completed.id);
    await _applyHabitProjectionAfterComplete(completed);
    if (celebrateFrog) {
      _celebrateFrogCompletionIfNeeded(completed, wasDone: current.isDone);
    }
    final nextRecurringTodo = alreadyDone
        ? null
        : await _materializeNextRecurringOccurrence(completed);
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
    final triggeredTodos = await _localTriggeredTodos(completed.id);
    return (
      todo: completed,
      triggeredTodos: triggeredTodos,
      nextRecurringTodo: nextRecurringTodo,
    );
  }

  Future<Todo> uncompleteLocalFirst(Todo current) async {
    final now = DateTime.now().toUtc();
    final wasDone = current.isDone || await _isStoredDone(current.id);
    final reopened = _normalizeSubtask(
      _patchTodo(current, {
        'status': TodoStatus.open.backendValue,
        'completed_at': null,
      }, now),
    );
    await _db.todosDao.upsertTodo(todoToCompanion(reopened, _userId));
    await _enqueueTodoUpdate(reopened.id);
    // The occurrence this completion generated must not linger next to the
    // reopened todo (and be duplicated when the todo is completed again).
    if (wasDone) await _parkGeneratedNextOccurrence(reopened);
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
    return reopened;
  }

  Future<({List<Todo> updatedTodos, List<Todo> triggeredTodos})>
  reconcileSubtaskAncestorsLocalFirst(Todo changed) async {
    final updatedTodos = <Todo>[];
    final triggeredTodos = <Todo>[];
    var parentId = changed.parentId;

    while (parentId != null) {
      final parentRow = await _db.todosDao.getTodoById(parentId);
      if (parentRow == null || !_belongsToCurrentUser(parentRow.userId)) break;
      final parent = _todoRowToModel(parentRow);
      if (parent.parentId == null) break;

      final childRows = await _db.todosDao.getSubtasks(parent.id);
      if (childRows.isEmpty) {
        parentId = parent.parentId;
        continue;
      }

      final allChildrenDone = childRows.every(
        (row) => row.status == TodoStatus.done.backendValue,
      );
      if (allChildrenDone && !parent.isDone) {
        final result = await completeLocalFirst(parent, celebrateFrog: false);
        updatedTodos.add(result.todo);
        triggeredTodos.addAll(result.triggeredTodos);
      } else if (!allChildrenDone && parent.isDone) {
        updatedTodos.add(await uncompleteLocalFirst(parent));
      }

      parentId = parent.parentId;
    }

    return (updatedTodos: updatedTodos, triggeredTodos: triggeredTodos);
  }

  // ─── F-T9 Mark frog ───────────────────────────────────────────

  Future<Todo> markFrog(String id, DateTime date) async {
    final cached = await _db.todosDao.getTodoById(id);
    if (cached != null && _belongsToCurrentUser(cached.userId)) {
      return setTodoFrogLocalFirst(
        _todoRowToModel(cached),
        enabled: true,
        date: date,
      );
    }
    return update(id, {
      'is_frog': true,
      'frog_date': formatDateOnly(date),
      'is_important': true,
      'is_urgent': true,
    });
  }

  // ─── F-T10 Unmark frog ────────────────────────────────────────

  Future<Todo> unmarkFrog(String id) async {
    final cached = await _db.todosDao.getTodoById(id);
    if (cached != null && _belongsToCurrentUser(cached.userId)) {
      return setTodoFrogLocalFirst(_todoRowToModel(cached), enabled: false);
    }
    return update(id, const {'is_frog': false, 'frog_date': null});
  }

  // ─── F-T11 Classify Eisenhower ────────────────────────────────

  Future<Todo> classify(String id, {bool? important, bool? urgent}) async {
    final resp = await _client.post(
      '/todos/$id/classify',
      body: {'is_important': important, 'is_urgent': urgent},
    );
    final todo = _normalizeSubtask(
      Todo.fromJson(
        (resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>,
      ),
    );
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
    return todo;
  }

  // ─── F-T12 Move to day ────────────────────────────────────────

  Future<Todo> moveToDay(String id, DateTime? date) async {
    final resp = await _client.post(
      '/todos/$id/move-to-day',
      body: {'date': date == null ? null : formatDateOnly(date)},
    );
    final todo = _normalizeSubtask(
      Todo.fromJson(
        (resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>,
      ),
    );
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
    return todo;
  }

  // ─── F-T13 Subtasks ───────────────────────────────────────────

  Future<List<Todo>> getSubtasks(String id) async {
    final resp = await _client.get('/todos/$id/subtasks');
    final items = (resp as Map<String, dynamic>)['items'] as List;
    return items
        .map((e) => _normalizeSubtask(Todo.fromJson(e as Map<String, dynamic>)))
        .toList();
  }

  // ─── F-T14 Attach tag ─────────────────────────────────────────

  Future<Tag> attachTag(
    String todoId, {
    String? tagId,
    String? name,
    String? color,
  }) async {
    final body = <String, dynamic>{
      if (tagId != null) 'tagId': tagId,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
    };
    try {
      final resp = await _client.post('/todos/$todoId/tags', body: body);
      final tag = Tag.fromJson(
        (resp as Map<String, dynamic>)['tag'] as Map<String, dynamic>,
      );
      await _db.todosDao.upsertTag(tagToCompanion(tag, _userId));
      final existing = await _db.todosDao.getTagsForTodo(todoId);
      final tagIds = {...existing.map((row) => row.id), tag.id}.toList();
      await _db.todosDao.setTodoTags(todoId, tagIds);
      _notifyTodoLocalChanged();
      return tag;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final localRow = tagId == null
          ? null
          : await _db.todosDao.getTagById(tagId);
      final tag = localRow != null
          ? _tagRowToModel(localRow)
          : await TagsRepository.instance.createLocal(
              name: name ?? '',
              color: color == null ? jsonColor('#888888') : jsonColor(color),
            );
      final existing = await _db.todosDao.getTagsForTodo(todoId);
      final tags = [
        ...existing.map(_tagRowToModel).where((item) => item.id != tag.id),
        tag,
      ];
      await replaceTagsLocalFirst(todoId, tags);
      return tag;
    }
  }

  // ─── F-T15 Detach tag ─────────────────────────────────────────

  Future<void> detachTag(String todoId, String tagId) async {
    try {
      await _client.delete('/todos/$todoId/tags/$tagId');
      final existing = await _db.todosDao.getTagsForTodo(todoId);
      await _db.todosDao.setTodoTags(
        todoId,
        existing.map((row) => row.id).where((id) => id != tagId).toList(),
      );
      _notifyTodoLocalChanged();
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final existing = await _db.todosDao.getTagsForTodo(todoId);
      await replaceTagsLocalFirst(
        todoId,
        existing.map(_tagRowToModel).where((tag) => tag.id != tagId).toList(),
      );
    }
  }

  Future<List<Tag>> replaceTags(
    String todoId, {
    List<Tag> tags = const [],
    List<String> names = const [],
  }) async {
    final normalizedNames = names
        .map(TagsRepository.normalizeTagName)
        .where((name) => name.isNotEmpty)
        .toList();
    final body = <String, dynamic>{
      if (tags.isNotEmpty || normalizedNames.isEmpty)
        'tag_ids': tags.map((tag) => tag.id).toList(),
      if (normalizedNames.isNotEmpty) 'tags': normalizedNames,
    };
    try {
      final resp = await _client.put('/todos/$todoId/tags', body: body);
      final map = resp as Map<String, dynamic>;
      final resultTags = ((map['tags'] as List?) ?? const [])
          .map((e) => Tag.fromJson(e as Map<String, dynamic>))
          .toList();
      await _cacheTagsForTodo(todoId, resultTags);
      _notifyTodoLocalChanged();
      return resultTags;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final resolved = [
        ...tags,
        for (final name in names)
          await TagsRepository.instance.createLocal(
            name: name,
            color: _defaultTagColor(name),
          ),
      ];
      return replaceTagsLocalFirst(todoId, _dedupeTags(resolved));
    }
  }

  Future<List<Tag>> replaceTagsLocalFirst(String todoId, List<Tag> tags) async {
    final deduped = _dedupeTags(tags);
    await _cacheTagsForTodo(todoId, deduped, enqueueUpdate: true);
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
    return deduped;
  }

  Future<List<Todo>> listByHabitLocal(String habitId) async {
    final rows = await _db.todosDao.getTodosForHabit(habitId);
    final result = <Todo>[];
    for (final row in rows) {
      if (!_belongsToCurrentUser(row.userId)) continue;
      if (row.status == TodoStatus.archived.backendValue) continue;
      final base = _todoRowToModel(row);
      if (_isLegacyRecurrenceProjection(base)) continue;
      final tagRows = await _db.todosDao.getTagsForTodo(base.id);
      result.add(
        base.copyWith(
          tags: tagRows.map(_tagRowToModel).toList(),
          tagIds: tagRows.map((tag) => tag.id).toList(),
          tagsLoaded: true,
        ),
      );
    }
    return result;
  }

  Future<List<Todo>> listLocal({
    String? habitId,
    bool includeDone = true,
    bool includeArchived = false,
  }) async {
    final rows = await _db.todosDao.getAllNonDeletedTodos();
    final result = <Todo>[];
    for (final row in rows) {
      if (!_belongsToCurrentUser(row.userId)) continue;
      if (row.parentId != null) continue;
      if (habitId != null && row.habitId != habitId) continue;
      final todo = _todoRowToModel(row);
      if (!includeArchived && todo.status == TodoStatus.archived) continue;
      if (!includeDone && todo.isDone) continue;
      if (_isLegacyRecurrenceProjection(todo)) continue;
      final tagRows = await _db.todosDao.getTagsForTodo(todo.id);
      result.add(
        todo.copyWith(
          tags: tagRows.map(_tagRowToModel).toList(),
          tagIds: tagRows.map((tag) => tag.id).toList(),
          tagsLoaded: true,
        ),
      );
    }
    result.sort((a, b) {
      final aDate = a.scheduledDate;
      final bDate = b.scheduledDate;
      if (aDate != null && bDate != null) return aDate.compareTo(bDate);
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return result;
  }

  // ─── Drift helpers ────────────────────────────────────────────

  Future<({Todo todo, List<Todo> triggeredTodos, Todo? nextRecurringTodo})>
  _completeOffline(
    String id, {
    int? actualMinutes,
    bool celebrateFrog = true,
  }) async {
    final row = await _db.todosDao.getTodoById(id);
    if (row == null) {
      throw const ApiException(404, 'not_found', 'not_found');
    }

    final current = _todoRowToModel(row);
    final now = DateTime.now().toUtc();
    final completed = _normalizeSubtask(
      Todo(
        id: current.id,
        parentId: current.parentId,
        title: current.title,
        description: current.description,
        status: TodoStatus.done,
        position: current.position,
        isFrog: current.isFrog,
        frogDate: current.frogDate,
        isImportant: current.isImportant,
        isUrgent: current.isUrgent,
        estimatedMinutes: current.estimatedMinutes,
        actualMinutes: actualMinutes ?? current.actualMinutes,
        startAt: current.startAt,
        dueAt: current.dueAt,
        scheduledDate: current.scheduledDate,
        time: current.time,
        triggerAfterTodoId: current.triggerAfterTodoId,
        habitId: current.habitId,
        tagIds: current.tagIds,
        completedAt: now,
        createdAt: current.createdAt,
        updatedAt: now,
        recurrenceType: current.recurrenceType,
        recurrenceInterval: current.recurrenceInterval,
        recurrenceDaysOfWeek: current.recurrenceDaysOfWeek,
        recurrenceEndDate: current.recurrenceEndDate,
        recurrenceTemplateId: current.recurrenceTemplateId,
      ),
    );
    await _db.todosDao.upsertTodo(todoToCompanion(completed, _userId));
    await _enqueueTodoUpdate(completed.id);
    await _applyHabitProjectionAfterComplete(completed);
    if (celebrateFrog) {
      _celebrateFrogCompletionIfNeeded(completed, wasDone: current.isDone);
    }
    final nextRecurringTodo = current.isDone
        ? null
        : await _materializeNextRecurringOccurrence(completed);
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
    final triggeredTodos = await _localTriggeredTodos(completed.id);
    return (
      todo: completed,
      triggeredTodos: triggeredTodos,
      nextRecurringTodo: nextRecurringTodo,
    );
  }

  Future<List<Todo>> _localTriggeredTodos(String completedTodoId) async {
    final rows = await _db.todosDao.getAllNonDeletedTodos();
    final todos = rows
        .where((row) => _belongsToCurrentUser(row.userId))
        .map(_todoRowToModel)
        .where(
          (todo) =>
              todo.triggerAfterTodoId == completedTodoId &&
              todo.status != TodoStatus.done &&
              todo.status != TodoStatus.archived,
        )
        .toList();
    todos.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return todos;
  }

  void _celebrateFrogCompletionIfNeeded(Todo todo, {required bool wasDone}) {
    if (wasDone || !todo.isFrog || !todo.isDone) return;
    FrogCompletionCelebrations.instance.celebrate(todo);
  }

  Future<Todo?> _materializeNextRecurringOccurrence(
    Todo completed, {
    DateTime? minimumDate,
    bool syncCreate = true,
  }) async {
    if (completed.parentId != null) return null;
    final recurrenceSource = await _recurrenceSourceForCompleted(completed);
    final templateId =
        recurrenceSource.recurrenceTemplateId ?? recurrenceSource.id;
    // One caller at a time per series: two taps, or a subtask reconcile racing
    // the user, must not both conclude that the next occurrence is missing.
    return _withSeriesLock(
      templateId,
      () => _materializeNextRecurringOccurrenceLocked(
        completed,
        recurrenceSource,
        templateId,
        minimumDate: minimumDate,
        syncCreate: syncCreate,
      ),
    );
  }

  Future<Todo?> _materializeNextRecurringOccurrenceLocked(
    Todo completed,
    Todo recurrenceSource,
    String templateId, {
    DateTime? minimumDate,
    required bool syncCreate,
  }) async {
    final seriesRows = await _db.todosDao.getSeriesRows(
      templateId,
      userId: _userId.isEmpty ? null : _userId,
    );
    final exceptionDates = seriesRows
        .where((row) => row.deletedAt != null && row.scheduledDate != null)
        .map((row) => row.scheduledDate!)
        .toSet();
    final nextDate = RecurrenceHelper.nextDateSkippingExceptions(
      todo: recurrenceSource,
      minimumDate: minimumDate,
      exceptionDates: exceptionDates,
    );
    if (nextDate == null) return null;

    // Which row plays "the next occurrence", in order of preference:
    //  1. whatever already holds the slot (reused, never duplicated);
    //  2. an occurrence parked when a previous completion was undone, which is
    //     moved to the slot if the schedule changed in between;
    //  3. an open occurrence the user already has further ahead.
    // Only when none exists is a new row created.
    final slotRow = await _db.todosDao.getOccurrenceForSeriesDate(
      templateId,
      formatDateOnly(nextDate),
    );
    final parkedRow = slotRow == null
        ? _firstParkedOccurrence(seriesRows)
        : null;
    final existing =
        slotRow ??
        parkedRow ??
        (slotRow == null && parkedRow == null
            ? _firstOpenSuccessor(seriesRows, after: recurrenceSource)
            : null);

    final tagRows = await _db.todosDao.getTagsForTodo(completed.id);
    final tagModels = tagRows.isEmpty && completed.tagsLoaded
        ? completed.tags
        : tagRows.map(_tagRowToModel).toList();
    final tagIds = tagRows.isEmpty
        ? await _tagIdsForTodo(completed)
        : tagRows.map((row) => row.id).toList();

    final existingIsCanonical =
        existing != null && existing.recurrenceType != null;
    var occurrence = existingIsCanonical
        ? _todoRowToModel(existing)
        : RecurrenceHelper.buildNextAfterCompletion(
            source: recurrenceSource,
            scheduledDate: nextDate,
            templateId: templateId,
            overrideId: existing?.id,
            tags: tagModels,
            tagIds: tagIds,
          );
    final reviveParked =
        existingIsCanonical &&
        existing.status == TodoStatus.archived.backendValue;
    if (reviveParked) {
      final movesToSlot = existing.scheduledDate != formatDateOnly(nextDate);
      occurrence = _patchTodo(occurrence, {
        'status': TodoStatus.open.backendValue,
        'completed_at': null,
        if (movesToSlot) 'scheduled_date': nextDate,
        if (movesToSlot)
          'due_at': recurrenceSource.dueAt == null
              ? null
              : DateTime.utc(
                  nextDate.year,
                  nextDate.month,
                  nextDate.day,
                  23,
                  59,
                ),
      }, DateTime.now().toUtc());
    }

    final sourceSubtree = await _db.todosDao.getActiveSubtree(
      completed.id,
      userId: _userId,
    );
    final hasTargetChildren = existingIsCanonical
        ? await _db.todosDao.hasDirectActiveSubtasks(
            occurrence.id,
            userId: _userId,
          )
        : false;
    final sourceTags = <String, List<String>>{};
    for (final row in sourceSubtree) {
      sourceTags[row.id] = (await _db.todosDao.getTagsForTodo(
        row.id,
      )).map((tag) => tag.id).toList();
    }

    final idMap = <String, String>{completed.id: occurrence.id};
    if (!hasTargetChildren) {
      for (final row in sourceSubtree) {
        idMap[row.id] = newId();
      }
    }
    final mappedParentTrigger = occurrence.triggerAfterTodoId == null
        ? null
        : idMap[occurrence.triggerAfterTodoId!] ??
              occurrence.triggerAfterTodoId;
    occurrence = occurrence.copyWith(
      triggerAfterTodoId: mappedParentTrigger,
      tags: tagModels,
      tagIds: tagIds,
      tagsLoaded: true,
    );

    await _db.transaction(() async {
      if (!existingIsCanonical) {
        await _db.todosDao.upsertTodo(todoToCompanion(occurrence, _userId));
        await _db.todosDao.setTodoTags(occurrence.id, tagIds);
        if (syncCreate) {
          await _enqueueStoredTodoCreate(occurrence.id, tagIds);
        }
      } else if (reviveParked) {
        await _db.todosDao.upsertTodo(todoToCompanion(occurrence, _userId));
        // `syncCreate: false` is the delete flow, where the backend revives the
        // parked row itself while it creates the next occurrence.
        if (syncCreate) await _enqueueTodoUpdate(occurrence.id);
      }

      if (!hasTargetChildren) {
        for (final sourceRow in sourceSubtree) {
          final cloned = _cloneRecurringSubtask(
            source: _todoRowToModel(sourceRow),
            newIdValue: idMap[sourceRow.id]!,
            newParentId: idMap[sourceRow.parentId]!,
            remappedTriggerId: sourceRow.triggerAfterTodoId == null
                ? null
                : idMap[sourceRow.triggerAfterTodoId!] ??
                      sourceRow.triggerAfterTodoId,
          );
          final clonedTagIds = sourceTags[sourceRow.id] ?? const <String>[];
          await _db.todosDao.upsertTodo(todoToCompanion(cloned, _userId));
          await _db.todosDao.setTodoTags(cloned.id, clonedTagIds);
          if (syncCreate) {
            await _enqueueStoredTodoCreate(cloned.id, clonedTagIds);
          }
        }
      }
    });

    return occurrence.copyWith(
      tags: tagModels,
      tagIds: tagIds,
      tagsLoaded: true,
    );
  }

  Todo _cloneRecurringSubtask({
    required Todo source,
    required String newIdValue,
    required String newParentId,
    required String? remappedTriggerId,
  }) {
    final now = DateTime.now().toUtc();
    return Todo(
      id: newIdValue,
      parentId: newParentId,
      title: source.title,
      description: source.description,
      status: TodoStatus.open,
      position: source.position,
      isFrog: source.isFrog,
      frogDate: source.frogDate,
      isImportant: source.isImportant,
      isUrgent: source.isUrgent,
      estimatedMinutes: source.estimatedMinutes,
      actualMinutes: null,
      startAt: source.startAt,
      dueAt: source.dueAt,
      scheduledDate: null,
      time: null,
      triggerAfterTodoId: remappedTriggerId,
      habitId: source.habitId,
      completedAt: null,
      createdAt: now,
      updatedAt: now,
      recurrenceType: null,
      recurrenceInterval: 1,
      recurrenceDaysOfWeek: null,
      recurrenceEndDate: null,
      recurrenceTemplateId: null,
    );
  }

  Future<void> _enqueueStoredTodoCreate(
    String todoId,
    List<String> tagIds,
  ) async {
    final row = await _db.todosDao.getTodoById(todoId);
    if (row == null) return;
    await _db.syncDao.enqueueSyncOp(
      userId: _userId,
      entityType: 'todo',
      entityId: todoId,
      operation: 'create',
      payload: SyncPayload.encode(SyncPayload.fromTodo(row, tagIds)),
    );
  }

  /// Runs [action] after every earlier action on the same series has finished.
  /// Dart interleaves at each `await`, so without this two completions could
  /// both read "no next occurrence yet" and each insert one.
  Future<T> _withSeriesLock<T>(String seriesId, Future<T> Function() action) {
    final previous = _seriesLocks[seriesId] ?? Future<void>.value();
    final result = Completer<T>();
    final tail = result.future.then<void>((_) {}, onError: (Object _) {});
    _seriesLocks[seriesId] = tail;
    previous.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    tail.whenComplete(() {
      if (identical(_seriesLocks[seriesId], tail)) {
        _seriesLocks.remove(seriesId);
      }
    });
    return result.future;
  }

  Future<bool> _isStoredDone(String id) async {
    final row = await _db.todosDao.getTodoById(id);
    return row?.status == TodoStatus.done.backendValue;
  }

  bool _isLiveTopLevelOccurrence(TodoRow row) =>
      row.deletedAt == null &&
      row.parentId == null &&
      row.recurrenceType != null &&
      row.scheduledDate != null &&
      _belongsToCurrentUser(row.userId);

  /// Earliest occurrence parked by [_parkGeneratedNextOccurrence], whatever its
  /// date: the schedule may have moved since, and the next completion moves it.
  TodoRow? _firstParkedOccurrence(List<TodoRow> seriesRows) {
    final parked =
        seriesRows
            .where(
              (row) =>
                  _isLiveTopLevelOccurrence(row) &&
                  row.status == TodoStatus.archived.backendValue,
            )
            .toList()
          ..sort((a, b) => a.scheduledDate!.compareTo(b.scheduledDate!));
    return parked.isEmpty ? null : parked.first;
  }

  /// Earliest open occurrence strictly after [after], e.g. a next occurrence
  /// the user rescheduled by hand. The series already has its actionable one.
  TodoRow? _firstOpenSuccessor(
    List<TodoRow> seriesRows, {
    required Todo after,
  }) {
    final afterDate = after.scheduledDate;
    if (afterDate == null) return null;
    final afterKey = formatDateOnly(afterDate);
    final open = seriesRows.where((row) {
      if (!_isLiveTopLevelOccurrence(row) || row.id == after.id) {
        return false;
      }
      final status = TodoStatus.parse(row.status);
      return (status == TodoStatus.open || status == TodoStatus.inProgress) &&
          row.scheduledDate!.compareTo(afterKey) > 0;
    }).toList()..sort((a, b) => a.scheduledDate!.compareTo(b.scheduledDate!));
    return open.isEmpty ? null : open.first;
  }

  /// Called after a done todo is reopened. The occurrence that completion
  /// created is parked (`archived`: already hidden from every list, score and
  /// reminder) instead of deleted. A soft-deleted occurrence is a recurrence
  /// exception whose date gets skipped, so deleting it would make the next
  /// completion jump a day ahead. Completing again revives the same row.
  ///
  /// Only the occurrence directly after [reopened], and only while it is still
  /// open: a next occurrence that is done, in progress or moved elsewhere, and
  /// anything further ahead, is the user's real todo and stays untouched.
  Future<void> _parkGeneratedNextOccurrence(Todo reopened) async {
    if (reopened.parentId != null) return;
    final source = await _recurrenceSourceForCompleted(reopened);
    if (source.recurrenceType == null) return;
    final templateId = source.recurrenceTemplateId ?? source.id;

    await _withSeriesLock(templateId, () async {
      final seriesRows = await _db.todosDao.getSeriesRows(
        templateId,
        userId: _userId.isEmpty ? null : _userId,
      );
      final exceptionDates = seriesRows
          .where((row) => row.deletedAt != null && row.scheduledDate != null)
          .map((row) => row.scheduledDate!)
          .toSet();
      final nextDate = RecurrenceHelper.nextDateSkippingExceptions(
        todo: source,
        exceptionDates: exceptionDates,
      );
      if (nextDate == null) return;

      final next = await _db.todosDao.getOccurrenceForSeriesDate(
        templateId,
        formatDateOnly(nextDate),
      );
      if (next == null ||
          !_isLiveTopLevelOccurrence(next) ||
          next.status != TodoStatus.open.backendValue) {
        return;
      }
      final parked = _patchTodo(_todoRowToModel(next), {
        'status': TodoStatus.archived.backendValue,
      }, DateTime.now().toUtc());
      await _db.todosDao.upsertTodo(todoToCompanion(parked, _userId));
      await _enqueueTodoUpdate(parked.id);
    });
  }

  Future<Todo> _recurrenceSourceForCompleted(Todo completed) async {
    if (completed.recurrenceType != null) return completed;
    final templateId = completed.recurrenceTemplateId;
    if (templateId == null) return completed;
    final templateRow = await _db.todosDao.getTodoById(templateId);
    if (templateRow == null) return completed;
    final template = _todoRowToModel(templateRow);
    if (template.recurrenceType == null) return completed;
    return Todo(
      id: completed.id,
      parentId: completed.parentId,
      title: completed.title,
      description: completed.description,
      status: completed.status,
      position: completed.position,
      isFrog: completed.isFrog,
      frogDate: completed.frogDate,
      isImportant: completed.isImportant,
      isUrgent: completed.isUrgent,
      estimatedMinutes: completed.estimatedMinutes,
      actualMinutes: completed.actualMinutes,
      startAt: completed.startAt,
      dueAt: completed.dueAt,
      scheduledDate: completed.scheduledDate,
      time: completed.time,
      triggerAfterTodoId: completed.triggerAfterTodoId,
      habitId: completed.habitId,
      tags: completed.tags,
      tagIds: completed.tagIds,
      tagsLoaded: completed.tagsLoaded,
      completedAt: completed.completedAt,
      createdAt: completed.createdAt,
      updatedAt: completed.updatedAt,
      recurrenceType: template.recurrenceType,
      recurrenceInterval: template.recurrenceInterval,
      recurrenceDaysOfWeek: template.recurrenceDaysOfWeek,
      recurrenceEndDate: template.recurrenceEndDate,
      recurrenceTemplateId: templateId,
    );
  }

  Tag _tagRowToModel(TagRow row) {
    return Tag(
      id: row.id,
      userId: row.userId,
      name: row.name,
      color: jsonColor(row.color),
      createdAt: jsonDateNullable(row.createdAt),
      updatedAt: jsonDateNullable(row.updatedAt),
      deletedAt: jsonDateNullable(row.deletedAt),
    );
  }

  Todo _normalizeSubtask(Todo todo) {
    if (todo.parentId == null) return _normalizeFrogState(todo);
    return _normalizeFrogState(
      Todo(
        id: todo.id,
        parentId: todo.parentId,
        title: todo.title,
        description: todo.description,
        status: todo.status,
        position: todo.position,
        isFrog: false,
        frogDate: null,
        isImportant: todo.isImportant,
        isUrgent: todo.isUrgent,
        estimatedMinutes: todo.estimatedMinutes,
        actualMinutes: todo.actualMinutes,
        startAt: todo.startAt,
        dueAt: todo.dueAt,
        scheduledDate: null,
        time: null,
        triggerAfterTodoId: todo.triggerAfterTodoId,
        habitId: todo.habitId,
        tags: todo.tags,
        tagIds: todo.tagIds,
        tagsLoaded: todo.tagsLoaded,
        completedAt: todo.completedAt,
        createdAt: todo.createdAt,
        updatedAt: todo.updatedAt,
        recurrenceType: null,
        recurrenceInterval: 1,
        recurrenceDaysOfWeek: null,
        recurrenceEndDate: null,
        recurrenceTemplateId: null,
      ),
    );
  }

  Todo _normalizeFrogState(Todo todo) {
    if (!todo.isFrog) {
      return todo.frogDate == null ? todo : todo.copyWith(frogDate: null);
    }
    final scheduledDate = todo.scheduledDate;
    if (scheduledDate == null) {
      return todo.copyWith(isFrog: false, frogDate: null);
    }
    return todo.copyWith(
      isFrog: true,
      frogDate: todo.frogDate ?? scheduledDate,
      isImportant: true,
      isUrgent: true,
    );
  }

  bool _isLegacyRecurrenceProjection(Todo todo) {
    return todo.recurrenceTemplateId != null &&
        todo.recurrenceType == null &&
        !todo.isDone;
  }

  /// Id các todo đang có thay đổi chưa đồng bộ (sửa, hoàn thành, xóa...).
  Future<Set<String>> _pendingTodoIds() async {
    if (_userId.isEmpty) return const {};
    final rows = await _db.syncDao.getRowsForUser(userId: _userId);
    return {
      for (final row in rows)
        if (row.entityType == 'todo' && !row.isDeadLetter) row.entityId,
    };
  }

  Future<void> _cacheTodos(List<Todo> todos) async {
    if (todos.isEmpty) return;
    final userId = _userId;
    // Bản trên server có thể cũ hơn thay đổi người dùng vừa làm offline (sửa,
    // hoàn thành...): bỏ qua chúng để thay đổi đó không bị hoàn tác trên màn
    // hình trước khi kịp đồng bộ.
    final pendingIds = await _pendingTodoIds();
    final normalized = todos
        .where((todo) => !pendingIds.contains(todo.id))
        .map(_normalizeSubtask)
        .toList();
    if (normalized.isEmpty) return;
    final tags = <Tag>[];
    for (final todo in normalized) {
      tags.addAll(todo.tags);
    }
    if (tags.isNotEmpty) {
      await _db.todosDao.upsertTags(
        tags.map((tag) => tagToCompanion(tag, userId)).toList(),
      );
    }
    for (final todo in normalized) {
      await _adoptServerRecurringOccurrence(todo);
    }
    await _db.todosDao.upsertTodos(
      normalized.map((t) => todoToCompanion(t, userId)).toList(),
    );
    for (final todo in normalized) {
      await _clearOtherLocalFrogsForTodo(
        todo,
        updatedAtIso: todo.updatedAt.toUtc().toIso8601String(),
      );
    }
    for (final todo in normalized) {
      if (!todo.tagsLoaded) continue;
      await _db.todosDao.setTodoTags(todo.id, todo.tagIds);
    }
  }

  Future<void> _adoptServerRecurringOccurrence(Todo todo) async {
    final templateId = todo.recurrenceTemplateId;
    final scheduledDate = todo.scheduledDate;
    if (templateId == null || scheduledDate == null) return;
    final existing = await _db.todosDao.getOccurrenceForSeriesDate(
      templateId,
      formatDateOnly(scheduledDate),
    );
    if (existing == null || existing.id == todo.id) return;

    final removedIds = await _db.todosDao.purgeTodoSubtree(
      existing.id,
      userId: _userId,
    );
    for (final id in removedIds) {
      await _db.syncDao.removeOpsForEntity('todo', id, userId: _userId);
    }
  }

  /// Cache a single todo + its tags to Drift.  Used on REST-success paths —
  /// server already has the entity so we do NOT enqueue a sync op.
  Future<void> _cacheTodoWithTags(Todo todo, List<Tag> tags) async {
    final normalized = _normalizeSubtask(
      todo.copyWith(
        tags: tags,
        tagIds: tags.map((t) => t.id).toList(),
        tagsLoaded: true,
      ),
    );
    if (tags.isNotEmpty) {
      await _db.todosDao.upsertTags(
        tags.map((tag) => tagToCompanion(tag, _userId)).toList(),
      );
    }
    await _db.todosDao.upsertTodo(todoToCompanion(normalized, _userId));
    await _clearOtherLocalFrogsForTodo(
      normalized,
      updatedAtIso: normalized.updatedAt.toUtc().toIso8601String(),
    );
    final tagIds = tags.map((t) => t.id).toList();
    await _db.todosDao.setTodoTags(todo.id, tagIds);
  }

  Future<void> _cacheTagsForTodo(
    String todoId,
    List<Tag> tags, {
    bool enqueueUpdate = false,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final tagIds = tags.map((tag) => tag.id).toList();
    await _db.todosDao.upsertTags(
      tags.map((tag) => tagToCompanion(tag, _userId)).toList(),
    );
    await _db.todosDao.setTodoTags(todoId, tagIds);
    await _db.todosDao.touchTodo(todoId, now);
    if (enqueueUpdate) {
      await _enqueueTodoUpdate(todoId);
    }
  }

  Future<List<Tag>> _resolveTagsForLocalBody(Map<String, dynamic> body) async {
    final result = <Tag>[];
    final seen = <String>{};

    final tagIds =
        (body['tag_ids'] as List?)?.whereType<String>().toList() ?? const [];
    for (final id in tagIds) {
      final row = await _db.todosDao.getTagById(id);
      if (row == null || seen.contains(row.id)) continue;
      result.add(_tagRowToModel(row));
      seen.add(row.id);
    }

    final names =
        (body['tags'] as List?)?.whereType<String>().toList() ?? const [];
    for (final name in names) {
      final normalized = TagsRepository.normalizeTagName(name);
      if (normalized.isEmpty) continue;
      final tag = await TagsRepository.instance.createLocal(
        name: normalized,
        color: _defaultTagColor(normalized),
      );
      if (seen.contains(tag.id)) continue;
      result.add(tag);
      seen.add(tag.id);
    }
    return result;
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

  Color _defaultTagColor(String name) {
    const palette = [
      '#6366f1',
      '#22c55e',
      '#f59e0b',
      '#ef4444',
      '#ec4899',
      '#06b6d4',
      '#a855f7',
      '#64748b',
    ];
    final index =
        name.runes.fold<int>(0, (sum, rune) => sum + rune) % palette.length;
    return jsonColor(palette[index]);
  }

  Future<int> _nextSubtaskPosition(String parentId) async {
    final rows = await _db.todosDao.getSubtasks(parentId);
    if (rows.isEmpty) return 0;
    var maxPosition = rows.first.position;
    for (final row in rows.skip(1)) {
      if (row.position > maxPosition) maxPosition = row.position;
    }
    return maxPosition + 1;
  }

  /// Write todo + tags to Drift AND enqueue a sync op.
  /// Used ONLY on the offline path (no_connection) — never on REST success.
  Future<void> _upsertTodoWithSync(
    Todo todo,
    List<Tag> tags,
    String operation, {
    List<String>? tagIdsOverride,
  }) async {
    final userId = _userId;
    if (tags.isNotEmpty) {
      await _db.todosDao.upsertTags(
        tags.map((tag) => tagToCompanion(tag, userId)).toList(),
      );
    }
    await _db.todosDao.upsertTodo(todoToCompanion(todo, userId));
    final clearedFrogIds = await _clearOtherLocalFrogsForTodo(
      todo,
      updatedAtIso: todo.updatedAt.toUtc().toIso8601String(),
    );
    final tagIds = tagIdsOverride ?? tags.map((t) => t.id).toList();
    await _db.todosDao.setTodoTags(todo.id, tagIds);
    for (final id in clearedFrogIds) {
      await _enqueueTodoUpdate(id);
    }
    // Build sync payload
    final payload = SyncPayload.fromTodo(
      (await _db.todosDao.getTodoById(todo.id))!,
      tagIds,
    );
    await _db.syncDao.enqueueSyncOp(
      userId: userId,
      entityType: 'todo',
      entityId: todo.id,
      operation: operation,
      payload: SyncPayload.encode(payload),
    );
  }

  Map<String, dynamic> _normalizeTodoWriteBody(
    Map<String, dynamic> body, {
    Todo? current,
    bool requireScheduledForTime = false,
  }) {
    final normalized = Map<String, dynamic>.from(body);
    final parentId = normalized.containsKey('parent_id')
        ? normalized['parent_id'] as String?
        : current?.parentId;
    var scheduledDate = normalized.containsKey('scheduled_date')
        ? _dateOnlyStringFromBody(normalized['scheduled_date'])
        : current?.scheduledDate == null
        ? null
        : formatDateOnly(current!.scheduledDate!);
    if (normalized.containsKey('scheduled_date')) {
      normalized['scheduled_date'] = scheduledDate;
    }

    if (normalized.containsKey('time')) {
      normalized['time'] = _normalizeTodoTime(normalized['time']);
    }

    if (parentId != null) {
      if (normalized['time'] == null) {
        normalized.remove('time');
      } else {
        normalized['time'] = null;
      }
    }

    if (normalized.containsKey('scheduled_date') &&
        normalized['scheduled_date'] == null) {
      normalized['time'] = null;
      scheduledDate = null;
    }

    if (requireScheduledForTime &&
        scheduledDate == null &&
        normalized['time'] != null) {
      throw const ApiException(400, 'bad_input', 'bad_input');
    }
    _normalizeFrogWriteFields(
      normalized,
      current: current,
      parentId: parentId,
      scheduledDate: scheduledDate,
    );
    return normalized;
  }

  void _normalizeFrogWriteFields(
    Map<String, dynamic> normalized, {
    Todo? current,
    required String? parentId,
    required String? scheduledDate,
  }) {
    final explicitFrog = normalized.containsKey('is_frog')
        ? normalized['is_frog'] == true
        : null;
    if (parentId != null) {
      if (explicitFrog == true) {
        throw const ApiException(400, 'bad_input', 'bad_input');
      }
      normalized['is_frog'] = false;
      normalized['frog_date'] = null;
      return;
    }

    final clearsSchedule =
        normalized.containsKey('scheduled_date') &&
        normalized['scheduled_date'] == null;
    if (clearsSchedule && (current?.isFrog == true || explicitFrog == true)) {
      normalized['is_frog'] = false;
      normalized['frog_date'] = null;
      return;
    }

    if (explicitFrog == false) {
      normalized['frog_date'] = null;
      return;
    }

    if (current?.isFrog == true && scheduledDate == null) {
      normalized['is_frog'] = false;
      normalized['frog_date'] = null;
      return;
    }

    final shouldBeFrog =
        explicitFrog == true ||
        (current?.isFrog == true &&
            (normalized.containsKey('scheduled_date') ||
                normalized.containsKey('frog_date') ||
                !normalized.containsKey('is_frog')));
    if (!shouldBeFrog) {
      if (normalized.containsKey('is_frog') && normalized['is_frog'] != true) {
        normalized['frog_date'] = null;
      }
      return;
    }

    final frogDate =
        _dateOnlyStringFromBody(normalized['frog_date']) ?? scheduledDate;
    if (frogDate == null) {
      throw const ApiException(400, 'bad_input', 'bad_input');
    }
    normalized['is_frog'] = true;
    normalized['frog_date'] = frogDate;
    normalized['is_important'] = true;
    normalized['is_urgent'] = true;
  }

  String? _dateOnlyStringFromBody(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return formatDateOnly(value);
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  Future<List<String>> _clearOtherLocalFrogsForTodo(
    Todo todo, {
    required String updatedAtIso,
  }) async {
    if (!todo.isFrog || todo.frogDate == null) return const [];
    final rows = await _db.todosDao.clearOtherFrogsForDate(
      userId: _userId,
      dateOnly: formatDateOnly(todo.frogDate!),
      updatedAtIso: updatedAtIso,
      exceptId: todo.id,
    );
    return rows.map((row) => row.id).toList(growable: false);
  }

  String? _normalizeTodoTime(dynamic value) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
      throw const ApiException(400, 'bad_input', 'bad_input');
    }
    return value;
  }

  Future<void> _enqueueOfflineUpdate(
    String todoId,
    Map<String, dynamic> patch,
  ) async {
    final existing = await _db.todosDao.getTodoById(todoId);
    if (existing == null) return;
    final current = _todoRowToModel(existing);
    final writePatch = _normalizeTodoWriteBody(
      patch,
      current: current,
      requireScheduledForTime: true,
    );
    final safePatch = _ensureDonePatchHasCompletedAt(
      writePatch,
      DateTime.now().toUtc(),
    );
    final tagIds = existing.parentId == null
        ? (await _db.todosDao.getTagsForTodo(
            todoId,
          )).map((tag) => tag.id).toList()
        : const <String>[];
    final payload = SyncPayload.fromTodo(existing, tagIds);
    final merged = {...payload, ...safePatch};
    await _db.syncDao.enqueueSyncOp(
      userId: _userId,
      entityType: 'todo',
      entityId: todoId,
      operation: 'update',
      payload: SyncPayload.encode(merged),
    );
  }

  Map<String, dynamic> _ensureDonePatchHasCompletedAt(
    Map<String, dynamic> body,
    DateTime nowUtc,
  ) {
    final status = body['status'];
    final setsDone =
        status == TodoStatus.done.backendValue || status == TodoStatus.done;
    if (!setsDone) return body;
    DateTime? completedAt;
    try {
      completedAt = _dateTimeFromJson(body['completed_at']);
    } catch (_) {
      completedAt = null;
    }
    if (completedAt != null) return body;
    return {...body, 'completed_at': nowUtc.toIso8601String()};
  }

  Todo _patchTodo(Todo current, Map<String, dynamic> body, DateTime updatedAt) {
    final parentId = body.containsKey('parent_id')
        ? body['parent_id'] as String?
        : current.parentId;
    final scheduledDate = body.containsKey('scheduled_date')
        ? _dateOnlyFromJson(body['scheduled_date'])
        : current.scheduledDate;
    final time = parentId != null || scheduledDate == null
        ? null
        : body.containsKey('time')
        ? body['time'] as String?
        : current.time;
    return Todo(
      id: current.id,
      parentId: parentId,
      title: body.containsKey('title')
          ? body['title'] as String
          : current.title,
      description: body.containsKey('description')
          ? body['description'] as String?
          : current.description,
      status: body.containsKey('status')
          ? TodoStatus.parse(body['status'] as String? ?? 'open')
          : current.status,
      position: body.containsKey('position')
          ? (body['position'] as num?)?.toInt() ?? current.position
          : current.position,
      isFrog: body.containsKey('is_frog')
          ? body['is_frog'] as bool? ?? false
          : current.isFrog,
      frogDate: body.containsKey('frog_date')
          ? _dateOnlyFromJson(body['frog_date'])
          : current.frogDate,
      isImportant: body.containsKey('is_important')
          ? body['is_important'] as bool?
          : current.isImportant,
      isUrgent: body.containsKey('is_urgent')
          ? body['is_urgent'] as bool?
          : current.isUrgent,
      estimatedMinutes: body.containsKey('estimated_minutes')
          ? (body['estimated_minutes'] as num?)?.toInt()
          : current.estimatedMinutes,
      actualMinutes: body.containsKey('actual_minutes')
          ? (body['actual_minutes'] as num?)?.toInt()
          : current.actualMinutes,
      startAt: body.containsKey('start_at')
          ? _dateTimeFromJson(body['start_at'])
          : current.startAt,
      dueAt: body.containsKey('due_at')
          ? _dateTimeFromJson(body['due_at'])
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
      completedAt: body.containsKey('completed_at')
          ? _dateTimeFromJson(body['completed_at'])
          : current.completedAt,
      createdAt: current.createdAt,
      updatedAt: updatedAt,
      recurrenceType: body.containsKey('recurrence_type')
          ? body['recurrence_type'] as String?
          : current.recurrenceType,
      recurrenceInterval: body.containsKey('recurrence_interval')
          ? (body['recurrence_interval'] as num?)?.toInt() ?? 1
          : current.recurrenceInterval,
      recurrenceDaysOfWeek: body.containsKey('recurrence_days_of_week')
          ? body['recurrence_days_of_week'] as String?
          : current.recurrenceDaysOfWeek,
      recurrenceEndDate: body.containsKey('recurrence_end_date')
          ? body['recurrence_end_date'] as String?
          : current.recurrenceEndDate,
      recurrenceTemplateId: body.containsKey('recurrence_template_id')
          ? body['recurrence_template_id'] as String?
          : current.recurrenceTemplateId,
    );
  }

  DateTime? _dateOnlyFromJson(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    if (value is String) return jsonDateOnlyNullable(value);
    return null;
  }

  DateTime? _dateTimeFromJson(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return jsonDateNullable(value);
    return null;
  }

  bool _patchTouchesRecurrence(Map<String, dynamic> body) {
    return body.containsKey('recurrence_type') ||
        body.containsKey('recurrence_interval') ||
        body.containsKey('recurrence_days_of_week') ||
        body.containsKey('recurrence_end_date');
  }

  Future<void> _enqueueTodoUpdate(String todoId) async {
    final row = await _db.todosDao.getTodoById(todoId);
    if (row == null) return;
    final tagIds = row.parentId == null
        ? (await _db.todosDao.getTagsForTodo(
            todoId,
          )).map((tag) => tag.id).toList()
        : const <String>[];
    final payload = SyncPayload.fromTodo(row, tagIds);
    await _db.syncDao.enqueueSyncOp(
      userId: _userId,
      entityType: 'todo',
      entityId: todoId,
      operation: 'update',
      payload: SyncPayload.encode(payload),
    );
  }

  Future<void> _softDeleteFutureInstancesForLocalEdit(
    String templateId,
    String fromDateInclusive,
  ) async {
    final instances = await _db.todosDao.getInstancesForTemplate(templateId);
    final rowsToDelete = instances.where((row) {
      final scheduledDate = row.scheduledDate;
      if (scheduledDate == null) return false;
      if (scheduledDate.compareTo(fromDateInclusive) < 0) return false;
      return row.recurrenceType == null &&
          row.status != TodoStatus.done.backendValue;
    }).toList();

    if (rowsToDelete.isEmpty) return;
    for (final row in rowsToDelete) {
      await _db.todosDao.purgeLocalRecurrenceProjection(row.id);
      await _db.syncDao.removeOpsForEntity('todo', row.id, userId: _userId);
    }
  }

  // ─── Recurrence instance generation ──────────────────────────────

  /// Converts a Drift [TodoRow] to the domain [Todo] model.
  /// Used internally to bridge DAOs → RecurrenceHelper.
  Todo _todoRowToModel(TodoRow row) {
    return _normalizeSubtask(
      Todo(
        id: row.id,
        parentId: row.parentId,
        title: row.title,
        description: row.description,
        status: TodoStatus.parse(row.status),
        position: row.position,
        isFrog: row.isFrog,
        frogDate: row.frogDate != null
            ? DateTime.tryParse(row.frogDate!)
            : null,
        isImportant: row.isImportant,
        isUrgent: row.isUrgent,
        estimatedMinutes: row.estimatedMinutes,
        actualMinutes: row.actualMinutes,
        startAt: row.startAt != null ? DateTime.tryParse(row.startAt!) : null,
        dueAt: row.dueAt != null ? DateTime.tryParse(row.dueAt!) : null,
        scheduledDate: row.scheduledDate != null
            ? DateTime.tryParse(row.scheduledDate!)
            : null,
        time: row.parentId == null && row.scheduledDate != null
            ? row.time
            : null,
        triggerAfterTodoId: row.triggerAfterTodoId,
        habitId: row.habitId,
        tagIds: const [],
        completedAt: row.completedAt != null
            ? DateTime.tryParse(row.completedAt!)
            : null,
        createdAt: DateTime.parse(row.createdAt),
        updatedAt: DateTime.parse(row.updatedAt),
        recurrenceType: row.recurrenceType,
        recurrenceInterval: row.recurrenceInterval ?? 1,
        recurrenceDaysOfWeek: row.recurrenceWeekdays,
        recurrenceEndDate: row.recurrenceEndDate,
        recurrenceTemplateId: row.recurrenceTemplateId,
      ),
    );
  }

  /// Keeps a recurrence series at exactly one actionable occurrence.
  ///
  /// Older app versions expanded templates into 30 local-only projections.
  /// Those rows are removed. If a completed legacy series has no real open
  /// occurrence, one occurrence is created at the first valid date from today.
  Future<void> _ensureInstancesExist(Todo template) async {
    final changed = await _repairRecurrenceSeries(template);
    if (!changed) return;
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
  }

  Future<void> _applyHabitProjectionAfterComplete(Todo completed) async {
    final habitId = completed.habitId;
    final scheduledDate = completed.scheduledDate;
    final completedAt = completed.completedAt;
    if (habitId == null || scheduledDate == null || completedAt == null) {
      return;
    }
    await HabitsRepository.instance.applyTodoCompletionProjection(
      habitId: habitId,
      scheduledDate: scheduledDate,
    );
  }

  Future<List<String>> _tagIdsForTodo(Todo todo) async {
    if (todo.tagIds.isNotEmpty) return todo.tagIds;
    final rows = await _db.todosDao.getTagsForTodo(todo.id);
    return rows.map((row) => row.id).toList();
  }

  Future<bool> _repairRecurrenceSeries(Todo template) async {
    if (!template.isRecurrenceTemplate) return false;

    final rows = await _db.todosDao.getInstancesForTemplate(template.id);
    final instances = rows
        .where((row) => _belongsToCurrentUser(row.userId))
        .map(_todoRowToModel)
        .toList();
    final realSeriesRows = <Todo>[
      template,
      ...instances.where((todo) => todo.recurrenceType != null),
    ];
    final hasActionableOccurrence = realSeriesRows.any(
      (todo) =>
          !todo.isDone &&
          todo.status != TodoStatus.archived &&
          todo.scheduledDate != null,
    );

    Todo? repaired;
    if (!hasActionableOccurrence && template.status != TodoStatus.archived) {
      final completed =
          <Todo>[
            if (template.isDone && template.scheduledDate != null) template,
            ...instances.where(
              (todo) => todo.isDone && todo.scheduledDate != null,
            ),
          ]..sort((a, b) {
            final dateOrder = a.scheduledDate!.compareTo(b.scheduledDate!);
            if (dateOrder != 0) return dateOrder;
            return a.updatedAt.compareTo(b.updatedAt);
          });

      if (completed.isNotEmpty) {
        final now = DateTime.now();
        repaired = await _materializeNextRecurringOccurrence(
          completed.last,
          minimumDate: DateTime(now.year, now.month, now.day),
        );
      }
    }

    final removedProjections = await _cleanupLegacyRecurrenceProjections(
      instances,
      keepId: repaired?.id,
    );
    return repaired != null || removedProjections;
  }

  Future<bool> _cleanupLegacyRecurrenceProjections(
    List<Todo> instances, {
    String? keepId,
  }) async {
    final projections = instances
        .where(
          (todo) =>
              todo.id != keepId && todo.recurrenceType == null && !todo.isDone,
        )
        .toList();
    if (projections.isEmpty) return false;

    for (final projection in projections) {
      await _db.todosDao.purgeLocalRecurrenceProjection(projection.id);
      await _db.syncDao.removeOpsForEntity(
        'todo',
        projection.id,
        userId: _userId,
      );
    }
    return true;
  }

  /// Public post-pull repair for legacy recurring series.
  Future<void> ensureAllRecurrenceInstances() async {
    final templates = await _db.todosDao.getRecurrenceTemplates();
    var changed = false;
    for (final row in templates) {
      if (!_belongsToCurrentUser(row.userId)) continue;
      final template = _todoRowToModel(row);
      changed = await _repairRecurrenceSeries(template) || changed;
    }
    if (!changed) return;
    _notifyTodoLocalChanged();
    ConnectivitySync.instance.scheduleWriteSync();
  }
}
