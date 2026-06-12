import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../models/todo.dart';
import '../utils/json_utils.dart';
import '../utils/recurrence_helper.dart';
import '../utils/todo_trigger_candidates.dart';
import '../utils/uuid_utils.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_storage.dart';
import 'local/database.dart';
import 'local/model_converters.dart';
import 'tags_repository.dart';
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
    String? tagId,
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
    };
    final resp = await _client.get('/todos', query: query);
    final map = resp as Map<String, dynamic>;
    final items = (map['items'] as List)
        .map((e) => _normalizeSubtask(Todo.fromJson(e as Map<String, dynamic>)))
        .toList();
    // Cache in Drift
    await _cacheTodos(items);
    return (items: items, nextCursor: map['nextCursor'] as String?);
  }

  Future<List<Todo>> listTriggerCandidates({String? excludeId}) async {
    try {
      final resp = await list(limit: 100);
      return filterTodoTriggerCandidates(resp.items, excludeId: excludeId);
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final rows = await _db.todosDao.getAllNonDeletedTodos();
      return filterTodoTriggerCandidates(
        rows.map(_todoRowToModel).toList(),
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
    return result;
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
    return result;
  }

  Future<TodoWithRelations?> getLocalDetail(String id) async {
    final row = await _db.todosDao.getTodoById(id);
    if (row == null) return null;
    final baseTodo = _todoRowToModel(row);
    final subtasks = await _db.todosDao.getSubtasks(id);
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

  Future<TodoWithRelations> createLocalFirst(Map<String, dynamic> body) async {
    return _createOffline(body);
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
      triggerAfterTodoId: body['trigger_after_todo_id'] as String?,
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
    try {
      final resp = await _client.patch('/todos/$id', body: body);
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
      return todo;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') {
        await _enqueueOfflineUpdate(id, body);
        rethrow; // UI handles re-render
      }
      rethrow;
    }
  }

  Future<Todo> updateLocalFirst(Todo current, Map<String, dynamic> body) async {
    final localNow = DateTime.now();
    final nowUtc = localNow.toUtc();
    final updated = _normalizeSubtask(_patchTodo(current, body, nowUtc));
    final recurrenceChanged = _patchTouchesRecurrence(body);

    await _db.todosDao.upsertTodo(todoToCompanion(updated, _userId));

    if (current.isRecurrenceTemplate && recurrenceChanged) {
      final tomorrow = DateTime(
        localNow.year,
        localNow.month,
        localNow.day,
      ).add(const Duration(days: 1));
      await _softDeleteFutureInstancesForLocalEdit(
        current.id,
        formatDateOnly(tomorrow),
        nowUtc.toIso8601String(),
      );
    }

    await _enqueueTodoUpdate(updated.id);

    if (updated.isRecurrenceTemplate && recurrenceChanged) {
      await _ensureInstancesExist(updated);
    }

    ConnectivitySync.instance.scheduleWriteSync();
    return updated;
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
    try {
      final resp = await _client.post('/todos/$id/complete', body: body);
      final map = resp as Map<String, dynamic>;
      final triggeredList = (map['triggered_todos'] as List?) ?? const [];
      final todo = _normalizeSubtask(
        Todo.fromJson(map['todo'] as Map<String, dynamic>),
      );
      final triggeredTodos = triggeredList
          .map(
            (e) => _normalizeSubtask(Todo.fromJson(e as Map<String, dynamic>)),
          )
          .toList();
      // Write to Drift cache (no enqueue — server already has it).
      await _cacheTodos([todo, ...triggeredTodos]);
      ConnectivitySync.instance.scheduleWriteSync();
      return (todo: todo, triggeredTodos: triggeredTodos);
    } on ApiException catch (e) {
      if (e.code == 'no_connection') {
        return _completeOffline(id, actualMinutes: actualMinutes);
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
    ConnectivitySync.instance.scheduleWriteSync();
    return todo;
  }

  Future<({Todo todo, List<Todo> triggeredTodos})> completeLocalFirst(
    Todo current, {
    int? actualMinutes,
  }) async {
    final now = DateTime.now().toUtc();
    final body = <String, dynamic>{
      'status': TodoStatus.done.backendValue,
      'completed_at': now,
      'actual_minutes': actualMinutes ?? current.actualMinutes,
    };
    final completed = _normalizeSubtask(_patchTodo(current, body, now));
    await _db.todosDao.upsertTodo(todoToCompanion(completed, _userId));
    await _enqueueTodoUpdate(completed.id);
    ConnectivitySync.instance.scheduleWriteSync();
    final triggeredTodos = await _localTriggeredTodos(completed.id);
    return (todo: completed, triggeredTodos: triggeredTodos);
  }

  Future<Todo> uncompleteLocalFirst(Todo current) async {
    final now = DateTime.now().toUtc();
    final reopened = _normalizeSubtask(
      _patchTodo(current, {
        'status': TodoStatus.open.backendValue,
        'completed_at': null,
      }, now),
    );
    await _db.todosDao.upsertTodo(todoToCompanion(reopened, _userId));
    await _enqueueTodoUpdate(reopened.id);
    ConnectivitySync.instance.scheduleWriteSync();
    return reopened;
  }

  // ─── F-T9 Mark frog ───────────────────────────────────────────

  Future<Todo> markFrog(String id, DateTime date) async {
    final resp = await _client.post(
      '/todos/$id/frog',
      body: {'date': formatDateOnly(date)},
    );
    final todo = _normalizeSubtask(
      Todo.fromJson(
        (resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>,
      ),
    );
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    return todo;
  }

  // ─── F-T10 Unmark frog ────────────────────────────────────────

  Future<Todo> unmarkFrog(String id) async {
    final resp = await _client.delete('/todos/$id/frog');
    final todo = _normalizeSubtask(
      Todo.fromJson(
        (resp as Map<String, dynamic>)['todo'] as Map<String, dynamic>,
      ),
    );
    await _db.todosDao.upsertTodo(todoToCompanion(todo, _userId));
    return todo;
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
    ConnectivitySync.instance.scheduleWriteSync();
    return deduped;
  }

  // ─── Drift helpers ────────────────────────────────────────────

  Future<({Todo todo, List<Todo> triggeredTodos})> _completeOffline(
    String id, {
    int? actualMinutes,
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
        triggerAfterTodoId: current.triggerAfterTodoId,
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
    ConnectivitySync.instance.scheduleWriteSync();
    final triggeredTodos = await _localTriggeredTodos(completed.id);
    return (todo: completed, triggeredTodos: triggeredTodos);
  }

  Future<List<Todo>> _localTriggeredTodos(String completedTodoId) async {
    final rows = await _db.todosDao.getAllNonDeletedTodos();
    final todos = rows
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
    if (todo.parentId == null) return todo;
    return Todo(
      id: todo.id,
      parentId: todo.parentId,
      title: todo.title,
      status: todo.status,
      position: todo.position,
      tags: const [],
      tagIds: const [],
      tagsLoaded: true,
      completedAt: todo.completedAt,
      createdAt: todo.createdAt,
      updatedAt: todo.updatedAt,
    );
  }

  Future<void> _cacheTodos(List<Todo> todos) async {
    if (todos.isEmpty) return;
    final userId = _userId;
    final normalized = todos.map(_normalizeSubtask).toList();
    final tags = <Tag>[];
    for (final todo in normalized) {
      tags.addAll(todo.tags);
    }
    if (tags.isNotEmpty) {
      await _db.todosDao.upsertTags(
        tags.map((tag) => tagToCompanion(tag, userId)).toList(),
      );
    }
    await _db.todosDao.upsertTodos(
      normalized.map((t) => todoToCompanion(t, userId)).toList(),
    );
    for (final todo in normalized) {
      if (todo.parentId != null || !todo.tagsLoaded) continue;
      await _db.todosDao.setTodoTags(todo.id, todo.tagIds);
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
    final tagIds = todo.parentId == null
        ? tags.map((t) => t.id).toList()
        : const <String>[];
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
    String operation,
  ) async {
    final userId = _userId;
    if (tags.isNotEmpty) {
      await _db.todosDao.upsertTags(
        tags.map((tag) => tagToCompanion(tag, userId)).toList(),
      );
    }
    await _db.todosDao.upsertTodo(todoToCompanion(todo, userId));
    final tagIds = tags.map((t) => t.id).toList();
    await _db.todosDao.setTodoTags(todo.id, tagIds);
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
    String todoId,
    Map<String, dynamic> patch,
  ) async {
    final existing = await _db.todosDao.getTodoById(todoId);
    if (existing == null) return;
    final tagIds = existing.parentId == null
        ? (await _db.todosDao.getTagsForTodo(
            todoId,
          )).map((tag) => tag.id).toList()
        : const <String>[];
    final payload = SyncPayload.fromTodo(existing, tagIds, const []);
    final merged = {...payload, ...patch};
    await _db.syncDao.enqueueSyncOp(
      entityType: 'todo',
      entityId: todoId,
      operation: 'update',
      payload: SyncPayload.encode(merged),
    );
  }

  Todo _patchTodo(Todo current, Map<String, dynamic> body, DateTime updatedAt) {
    return Todo(
      id: current.id,
      parentId: body.containsKey('parent_id')
          ? body['parent_id'] as String?
          : current.parentId,
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
      scheduledDate: body.containsKey('scheduled_date')
          ? _dateOnlyFromJson(body['scheduled_date'])
          : current.scheduledDate,
      triggerAfterTodoId: body.containsKey('trigger_after_todo_id')
          ? body['trigger_after_todo_id'] as String?
          : current.triggerAfterTodoId,
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
    final payload = SyncPayload.fromTodo(row, tagIds, const []);
    await _db.syncDao.enqueueSyncOp(
      entityType: 'todo',
      entityId: todoId,
      operation: 'update',
      payload: SyncPayload.encode(payload),
    );
  }

  Future<void> _softDeleteFutureInstancesForLocalEdit(
    String templateId,
    String fromDateInclusive,
    String deletedAtIso,
  ) async {
    final instances = await _db.todosDao.getInstancesForTemplate(templateId);
    final rowsToDelete = instances.where((row) {
      final scheduledDate = row.scheduledDate;
      if (scheduledDate == null) return false;
      if (scheduledDate.compareTo(fromDateInclusive) < 0) return false;
      return row.status != TodoStatus.done.backendValue;
    }).toList();

    if (rowsToDelete.isEmpty) return;
    await _db.todosDao.softDeleteFutureInstances(
      templateId,
      fromDateInclusive,
      deletedAtIso,
    );
    for (final row in rowsToDelete) {
      await _db.syncDao.enqueueSyncOp(
        entityType: 'todo',
        entityId: row.id,
        operation: 'delete',
        payload: jsonEncode({
          'id': row.id,
          'deleted_at': deletedAtIso,
          'updated_at': deletedAtIso,
        }),
      );
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
      ),
    );
  }

  /// Generates (idempotently) recurrence instances for [template] from
  /// today up to [horizon] (defaults to today + 30 days).
  ///
  /// Each instance is written to Drift + enqueued in sync_queue so the
  /// SyncWorker can push it to the server when online.
  Future<void> _ensureInstancesExist(Todo template, {DateTime? horizon}) async {
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
      final exists = await _db.todosDao.instanceExistsForDate(
        template.id,
        dateStr,
      );
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
  Future<void> deleteFutureAndThis(String instanceId, String templateId) async {
    final instanceRow = await _db.todosDao.getTodoById(instanceId);
    final now = nowIso();
    final fromDate =
        instanceRow?.scheduledDate ?? formatDateOnly(DateTime.now());

    // Soft-delete locally
    await _db.todosDao.softDeleteFutureInstances(templateId, fromDate, now);
    await _db.todosDao.softDeleteTodo(templateId, now);

    // Enqueue deletes
    final deletedIds = [instanceId, templateId];
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
      payload: jsonEncode({
        'id': templateId,
        'deleted_at': now,
        'updated_at': now,
      }),
    );
    ConnectivitySync.instance.scheduleWriteSync();
  }
}
