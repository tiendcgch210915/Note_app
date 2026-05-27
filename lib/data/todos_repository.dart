import 'dart:convert';

import '../models/tag.dart';
import '../models/todo.dart';
import '../utils/json_utils.dart';
import '../utils/recurrence_helper.dart';
import '../utils/uuid_utils.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_storage.dart';
import 'local/database.dart';
import 'local/model_converters.dart';
import '../sync/connectivity_sync.dart';
import '../sync/sync_payload.dart';

/// Repository cho Group T — Todos.
///
/// Strategy:
///  - All reads: REST (online) – Drift used by SyncWorker pull to populate cache
///  - All writes: REST first; on success → write to Drift + enqueue sync_queue
///               On no_connection → write to Drift + enqueue (offline mode)
///  - After any write → ConnectivitySync.scheduleWriteSync()
class TodosRepository {
  TodosRepository._();
  static final TodosRepository instance = TodosRepository._();
  final ApiClient _client = ApiClient.instance;
  final AppDatabase _db = AppDatabase.instance;

  String get _userId =>
      AuthStorage.instance.currentUserJson?['id'] as String? ?? '';

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
  }) async {
    final query = <String, dynamic>{
      if (cursor != null) 'cursor': cursor,
      if (limit != null) 'limit': limit,
      if (scheduledDate != null) 'scheduled_date': formatDateOnly(scheduledDate),
      if (status != null) 'status': status.backendValue,
      if (isFrog != null) 'is_frog': isFrog,
      if (parentId != null) 'parent_id': parentId,
      if (q != null && q.isNotEmpty) 'q': q,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
    };
    final resp = await _client.get('/todos', query: query);
    final map = resp as Map<String, dynamic>;
    final items = (map['items'] as List)
        .map((e) => Todo.fromJson(e as Map<String, dynamic>))
        .toList();
    // Cache in Drift
    await _cacheTodos(items);
    return (items: items, nextCursor: map['nextCursor'] as String?);
  }

  // ─── F-T3 Day list ────────────────────────────────────────────

  Future<List<DayTopLevelTodo>> getDay(DateTime date) async {
    final resp = await _client.get('/todos/day/${formatDateOnly(date)}');
    final items = (resp as Map<String, dynamic>)['items'] as List;
    final result = items
        .map((e) => DayTopLevelTodo.fromJson(e as Map<String, dynamic>))
        .toList();
    await _cacheTodos(result.map((d) => d.todo).toList());
    return result;
  }

  // ─── F-T4 Detail ──────────────────────────────────────────────

  Future<TodoWithRelations> getDetail(String id) async {
    final resp = await _client.get('/todos/$id');
    return TodoWithRelations.fromJson(resp as Map<String, dynamic>);
  }

  // ─── F-T1 Create ──────────────────────────────────────────────

  Future<TodoWithRelations> create(Map<String, dynamic> body) async {
    try {
      final resp = await _client.post('/todos', body: body);
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
        return _createOffline(body);
      }
      rethrow;
    }
  }

  /// Creates todo locally when offline. Returns optimistic result.
  Future<TodoWithRelations> _createOffline(Map<String, dynamic> body) async {
    final now = DateTime.now().toUtc();
    final id = newId();
    final todo = Todo(
      id: id,
      title: body['title'] as String,
      description: body['description'] as String?,
      parentId: body['parent_id'] as String?,
      scheduledDate: body['scheduled_date'] != null
          ? jsonDateOnlyNullable(body['scheduled_date'] as String?)
          : null,
      status: TodoStatus.open,
      isFrog: body['is_frog'] as bool? ?? false,
      createdAt: now,
      updatedAt: now,
    );
    await _upsertTodoWithSync(todo, const [], 'create');
    ConnectivitySync.instance.scheduleWriteSync();
    return TodoWithRelations(
        todo: todo, tags: const [], subtasks: const [], linkedNotes: const []);
  }

  // ─── F-T5 Update ──────────────────────────────────────────────

  Future<Todo> update(String id, Map<String, dynamic> body) async {
    try {
      final resp = await _client.patch('/todos/$id', body: body);
      final todo =
          Todo.fromJson((resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>);
      // Server already has this — cache locally only, do NOT enqueue.
      await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
      return todo;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') {
        await _enqueueOfflineUpdate(id, body);
        throw e; // UI handles re-render
      }
      rethrow;
    }
  }

  // ─── F-T6 Delete ──────────────────────────────────────────────

  Future<void> delete(String id) async {
    final now = nowIso();
    bool isOffline = false;
    try {
      await _client.delete('/todos/$id');
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      isOffline = true;
    }
    // Soft-delete locally regardless
    await _db.todosDao.softDeleteTodo(id, now);
    // Only enqueue when offline — server already processed it when online.
    if (isOffline) {
      await _db.syncDao.enqueueSyncOp(
        entityType: 'todo',
        entityId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'deleted_at': now, 'updated_at': now}),
      );
      ConnectivitySync.instance.scheduleWriteSync();
    }
  }

  // ─── F-T7 Complete ────────────────────────────────────────────

  Future<({Todo todo, List<Todo> triggeredTodos})> complete(
    String id, {
    int? actualMinutes,
  }) async {
    final body = <String, dynamic>{
      if (actualMinutes != null) 'actual_minutes': actualMinutes,
    };
    final resp = await _client.post('/todos/$id/complete', body: body);
    final map = resp as Map<String, dynamic>;
    final triggeredList = (map['triggered_todos'] as List?) ?? const [];
    final todo = Todo.fromJson(map['todo'] as Map<String, dynamic>);
    // Write to Drift cache (no enqueue — server already has it)
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    ConnectivitySync.instance.scheduleWriteSync();
    return (
      todo: todo,
      triggeredTodos: triggeredList
          .map((e) => Todo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ─── F-T8 Uncomplete ──────────────────────────────────────────

  Future<Todo> uncomplete(String id) async {
    final resp = await _client.post('/todos/$id/uncomplete', body: const {});
    final todo =
        Todo.fromJson((resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>);
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    ConnectivitySync.instance.scheduleWriteSync();
    return todo;
  }

  // ─── F-T9 Mark frog ───────────────────────────────────────────

  Future<Todo> markFrog(String id, DateTime date) async {
    final resp = await _client.post(
      '/todos/$id/frog',
      body: {'date': formatDateOnly(date)},
    );
    final todo =
        Todo.fromJson((resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>);
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    return todo;
  }

  // ─── F-T10 Unmark frog ────────────────────────────────────────

  Future<Todo> unmarkFrog(String id) async {
    final resp = await _client.delete('/todos/$id/frog');
    final todo =
        Todo.fromJson((resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>);
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    return todo;
  }

  // ─── F-T11 Classify Eisenhower ────────────────────────────────

  Future<Todo> classify(String id, {bool? important, bool? urgent}) async {
    final resp = await _client.post(
      '/todos/$id/classify',
      body: {'is_important': important, 'is_urgent': urgent},
    );
    final todo =
        Todo.fromJson((resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>);
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    ConnectivitySync.instance.scheduleWriteSync();
    return todo;
  }

  // ─── F-T12 Move to day ────────────────────────────────────────

  Future<Todo> moveToDay(String id, DateTime? date) async {
    final resp = await _client.post(
      '/todos/$id/move-to-day',
      body: {'date': date == null ? null : formatDateOnly(date)},
    );
    final todo =
        Todo.fromJson((resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>);
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    ConnectivitySync.instance.scheduleWriteSync();
    return todo;
  }

  // ─── F-T13 Subtasks ───────────────────────────────────────────

  Future<List<Todo>> getSubtasks(String id) async {
    final resp = await _client.get('/todos/$id/subtasks');
    final items = (resp as Map<String, dynamic>)['items'] as List;
    return items.map((e) => Todo.fromJson(e as Map<String, dynamic>)).toList();
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
    final resp = await _client.post('/todos/$todoId/tags', body: body);
    return Tag.fromJson((resp as Map<String, dynamic>)['tag'] as Map<String, dynamic>);
  }

  // ─── F-T15 Detach tag ─────────────────────────────────────────

  Future<void> detachTag(String todoId, String tagId) async {
    await _client.delete('/todos/$todoId/tags/$tagId');
  }

  // ─── Drift helpers ────────────────────────────────────────────

  Future<void> _cacheTodos(List<Todo> todos) async {
    if (todos.isEmpty) return;
    final userId = _userId;
    await _db.todosDao.upsertTodos(
      todos.map((t) => todoToCompanion(t, userId)).toList(),
    );
  }

  /// Cache a single todo + its tags to Drift.  Used on REST-success paths —
  /// server already has the entity so we do NOT enqueue a sync op.
  Future<void> _cacheTodoWithTags(Todo todo, List<Tag> tags) async {
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    final tagIds = tags.map((t) => t.id).toList();
    if (tagIds.isNotEmpty) {
      await _db.todosDao.setTodoTags(todo.id, tagIds);
    }
  }

  /// Write todo + tags to Drift AND enqueue a sync op.
  /// Used ONLY on the offline path (no_connection) — never on REST success.
  Future<void> _upsertTodoWithSync(
      Todo todo, List<Tag> tags, String operation) async {
    final userId = _userId;
    await _db.todosDao.upsertTodo(todoToCompanion(todo, userId));
    final tagIds = tags.map((t) => t.id).toList();
    if (tagIds.isNotEmpty) {
      await _db.todosDao.setTodoTags(todo.id, tagIds);
    }
    // Build sync payload
    final noteLinkIds = <String>[];
    final payload = SyncPayload.fromTodo(
      (await _db.todosDao.getTodoById(todo.id))!,
      tagIds,
      noteLinkIds,
    );
    await _db.syncDao.enqueueSyncOp(
      entityType: 'todo',
      entityId: todo.id,
      operation: operation,
      payload: SyncPayload.encode(payload),
    );
  }

  Future<void> _enqueueOfflineUpdate(
      String todoId, Map<String, dynamic> patch) async {
    final existing = await _db.todosDao.getTodoById(todoId);
    if (existing == null) return;
    final payload = SyncPayload.fromTodo(existing, const [], const []);
    final merged = {...payload, ...patch};
    await _db.syncDao.enqueueSyncOp(
      entityType: 'todo',
      entityId: todoId,
      operation: 'update',
      payload: SyncPayload.encode(merged),
    );
  }

  // ─── Recurrence instance generation ──────────────────────────────

  /// Converts a Drift [TodoRow] to the domain [Todo] model.
  /// Used internally to bridge DAOs → RecurrenceHelper.
  Todo _todoRowToModel(TodoRow row) {
    return Todo(
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
      startAt:
          row.startAt != null ? DateTime.tryParse(row.startAt!) : null,
      dueAt: row.dueAt != null ? DateTime.tryParse(row.dueAt!) : null,
      scheduledDate: row.scheduledDate != null
          ? DateTime.tryParse(row.scheduledDate!)
          : null,
      triggerAfterTodoId: row.triggerAfterTodoId,
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
    );
  }

  /// Generates (idempotently) recurrence instances for [template] from
  /// today up to [horizon] (defaults to today + 30 days).
  ///
  /// Each instance is written to Drift + enqueued in sync_queue so the
  /// SyncWorker can push it to the server when online.
  Future<void> _ensureInstancesExist(
    Todo template, {
    DateTime? horizon,
  }) async {
    if (!template.isRecurrenceTemplate) return;
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final end = horizon ?? today.add(const Duration(days: 30));

    final dates = RecurrenceHelper.occurrenceDates(
      template: template,
      startDate: today,
      horizon: end.add(const Duration(days: 1)), // make inclusive
    );

    for (final date in dates) {
      final dateStr = formatDateOnly(date);
      final exists =
          await _db.todosDao.instanceExistsForDate(template.id, dateStr);
      if (exists) continue;

      final instance = RecurrenceHelper.buildInstance(
        template: template,
        date: date,
      );
      await _db.todosDao.upsertTodo(todoToCompanion(instance, _userId));
      // Build sync payload and enqueue
      final payload = SyncPayload.fromTodo(
        (await _db.todosDao.getTodoById(instance.id))!,
        const [],
        const [],
      );
      await _db.syncDao.enqueueSyncOp(
        entityType: 'todo',
        entityId: instance.id,
        operation: 'create',
        payload: SyncPayload.encode(payload),
      );
    }
    if (dates.isNotEmpty) {
      ConnectivitySync.instance.scheduleWriteSync();
    }
  }

  /// Public: called from [SyncWorker]'s post-pull hook to regenerate
  /// instances for ALL templates in the local DB after a full pull.
  Future<void> ensureAllRecurrenceInstances() async {
    final templates = await _db.todosDao.getRecurrenceTemplates();
    for (final row in templates) {
      final template = _todoRowToModel(row);
      await _ensureInstancesExist(template);
    }
  }

  // ─── Recurrence delete scopes ──────────────────────────────────────

  /// Delete "this + future" scope: soft-delete this instance, all future
  /// non-done instances, and the template itself.
  Future<void> deleteFutureAndThis(
      String instanceId, String templateId) async {
    final instanceRow = await _db.todosDao.getTodoById(instanceId);
    final now = nowIso();
    final fromDate = instanceRow?.scheduledDate ?? formatDateOnly(DateTime.now());

    // Soft-delete locally
    await _db.todosDao.softDeleteFutureInstances(templateId, fromDate, now);
    await _db.todosDao.softDeleteTodo(templateId, now);

    // Enqueue deletes
    final deletedIds = [
      instanceId,
      templateId,
    ];
    for (final id in deletedIds) {
      await _db.syncDao.enqueueSyncOp(
        entityType: 'todo',
        entityId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'deleted_at': now, 'updated_at': now}),
      );
    }
    ConnectivitySync.instance.scheduleWriteSync();
  }

  /// Delete "all recurrences" scope: soft-delete template + every instance.
  Future<void> deleteAllRecurrences(String templateId) async {
    final now = nowIso();
    await _db.todosDao.softDeleteAllInstances(templateId, now);
    await _db.todosDao.softDeleteTodo(templateId, now);

    // Enqueue one op for the template; server cascades instances.
    await _db.syncDao.enqueueSyncOp(
      entityType: 'todo',
      entityId: templateId,
      operation: 'delete',
      payload:
          jsonEncode({'id': templateId, 'deleted_at': now, 'updated_at': now}),
    );
    ConnectivitySync.instance.scheduleWriteSync();
  }
}
