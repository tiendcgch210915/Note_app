import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/api_exception.dart';
import '../data/auth_storage.dart';
import '../data/local/database.dart';
import '../data/remote/api_client_dio.dart';
import 'sync_payload.dart';
import 'sync_status_notifier.dart';

/// Background sync coordinator.
///
/// Architecture:
///  push/pull never enqueue data coming FROM server — only local user writes
///  are queued.  Data from server is written directly to Drift.
///
/// Usage:
///   await SyncWorker.instance.sync();         // full cycle: push then pull
///   await SyncWorker.instance.pushPending();  // push only
///   await SyncWorker.instance.pullChanges();  // pull only
class SyncWorker {
  SyncWorker._();
  static final SyncWorker instance = SyncWorker._();

  final AppDatabase _db = AppDatabase.instance;
  final ApiClientDio _client = ApiClientDio.instance;

  bool _syncing = false;

  // ── Post-pull hook ────────────────────────────────────────────
  // Registered by TodosRepository to generate recurrence instances
  // after a pull without creating a circular import chain.
  static Future<void> Function()? _postPullHook;
  static void registerPostPullHook(Future<void> Function() hook) {
    _postPullHook = hook;
  }

  // ─── Public API ───────────────────────────────────────────────────

  Future<void> sync() async {
    if (_syncing) return;
    if (AuthStorage.instance.currentToken == null) {
      debugPrint('[SyncWorker] Skip sync: no auth token');
      return;
    }
    _syncing = true;
    SyncStatusNotifier.instance.beginSync();
    String? errorMsg;
    try {
      await pushPending();
      await pullChanges();
    } on ApiException catch (e) {
      // Network / server errors — log, surface to UI, do NOT crash
      errorMsg = '[${e.code}] ${e.message}';
      debugPrint('[SyncWorker] Sync ApiException: $errorMsg');
    } catch (e, st) {
      errorMsg = e.toString();
      debugPrint('[SyncWorker] Sync unexpected error: $e\n$st');
    } finally {
      final pending = await _db.syncDao.getPendingCount();
      SyncStatusNotifier.instance.endSync(
        pendingCount: pending,
        error: errorMsg,
      );
      _syncing = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // M5b: PUSH
  // ─────────────────────────────────────────────────────────────────

  Future<void> pushPending() async {
    while (true) {
      final all = await _db.syncDao.getDueBatch(limit: 100);
      if (all.isEmpty) return;

      final sorted = sortedByDependency<SyncQueueRow>(
        rows: all,
        getEntityType: (r) => r.entityType,
        getId: (r) => r.id,
      );

      // Drop illegal system checklist writes. Backend returns read_only for
      // these, so removing them locally disables the invalid queued action.
      final eligibleRows = <SyncQueueRow>[];
      for (final row in sorted) {
        if (row.entityType == 'checklist_template' &&
            (row.operation == 'update' || row.operation == 'delete')) {
          final t = await _db.checklistsDao.getTemplateById(row.entityId);
          if (t?.isSystem == true) {
            await _db.syncDao.removeSyncOp(row.id);
            continue;
          }
        }
        if (row.entityType == 'checklist_category' &&
            (row.operation == 'update' || row.operation == 'delete')) {
          final category = await _db.checklistsDao.getCategoryById(
            row.entityId,
          );
          if (category?.isSystem == true) {
            await _db.syncDao.removeSyncOp(row.id);
            continue;
          }
        }
        eligibleRows.add(row);
      }
      if (eligibleRows.isEmpty) continue;

      final ops = eligibleRows.map((row) {
        return SyncPayload.pushOperation(
          op: row.operation,
          type: row.entityType,
          payload: SyncPayload.decode(row.payload),
        );
      }).toList();

      debugPrint(
        '[SyncWorker] POST /sync/push op_count=${ops.length} '
        'op_types=${_opTypesForLog(eligibleRows)}',
      );

      Map<String, dynamic> response;
      try {
        final resp = await _client.post(
          '/sync/push',
          data: {'operations': ops},
        );
        response = resp as Map<String, dynamic>;
      } on ApiException catch (e) {
        if (e.code == 'no_connection') return; // try again later
        _logSyncFailure(
          method: 'POST',
          url: '/sync/push',
          status: e.statusCode,
          responseBody: _apiErrorBody(e),
          opCount: ops.length,
          opTypes: _opTypesForLog(eligibleRows),
        );
        for (final row in eligibleRows) {
          await _db.syncDao.markFailedRetryable(row.id, row.retryCount);
        }
        rethrow; // sync() catches this and shows error state in UI
      }

      final results = (response['results'] as List?) ?? const [];
      final resultIds = <String>{};
      final resultErrors = <String>[];

      // Backend results identify the local operation by payload.id.
      final rowByEntityId = {for (final r in eligibleRows) r.entityId: r};

      for (final result in results) {
        final map = result as Map<String, dynamic>;
        final entityId = map['id'] as String?;
        final status = map['status'] as String?;
        if (entityId == null || status == null) {
          resultErrors.add('malformed_result');
          continue;
        }
        resultIds.add(entityId);
        final queueRow = rowByEntityId[entityId];
        if (queueRow == null) continue;

        switch (status) {
          case 'applied':
            await _db.syncDao.removeSyncOp(queueRow.id);
            break;

          case 'conflict':
            final serverVersion =
                map['server_version'] as Map<String, dynamic>?;
            if (serverVersion == null) {
              resultErrors.add(
                '${queueRow.entityType}:conflict_missing_server',
              );
              await _db.syncDao.markFailedRetryable(
                queueRow.id,
                queueRow.retryCount,
              );
              break;
            }
            await _applyServerVersion(
              queueRow.entityType,
              entityId,
              serverVersion,
            );
            final serverId = serverVersion['id'] as String?;
            if (serverId != null && serverId != entityId) {
              await _remapPendingEntityReferences(
                queueRow.entityType,
                entityId,
                serverId,
              );
            }
            await _db.syncDao.removeSyncOp(queueRow.id);
            break;

          case 'error':
            final error = map['error'] as String? ?? 'unknown';
            if (error == 'read_only' &&
                (queueRow.entityType == 'checklist_template' ||
                    queueRow.entityType == 'checklist_category') &&
                (queueRow.operation == 'update' ||
                    queueRow.operation == 'delete')) {
              await _db.syncDao.removeSyncOp(queueRow.id);
            } else {
              resultErrors.add('${queueRow.entityType}:$error');
              await _db.syncDao.markFailedRetryable(
                queueRow.id,
                queueRow.retryCount,
              );
            }
            break;

          default:
            resultErrors.add('${queueRow.entityType}:unknown_status_$status');
            await _db.syncDao.markFailedRetryable(
              queueRow.id,
              queueRow.retryCount,
            );
            break;
        }
      }

      for (final row in eligibleRows) {
        if (!resultIds.contains(row.entityId)) {
          resultErrors.add('${row.entityType}:missing_result');
          await _db.syncDao.markFailedRetryable(row.id, row.retryCount);
        }
      }

      if (resultErrors.isNotEmpty) {
        _logSyncFailure(
          method: 'POST',
          url: '/sync/push',
          status: 0,
          responseBody: _pushResponseForLog(response),
          opCount: ops.length,
          opTypes: _opTypesForLog(eligibleRows),
          resultSummary: _resultSummary(results),
        );
        throw ApiException(
          0,
          'sync_result_error',
          resultErrors.take(5).join(', '),
        );
      }
    }
  }

  /// Apply a server_version object to the local Drift database.
  /// Handles the special id-adopt case for tags and habit_logs.
  Future<void> _applyServerVersion(
    String entityType,
    String localEntityId,
    Map<String, dynamic> serverVersion,
  ) async {
    final serverId = serverVersion['id'] as String?;
    final idChanged = serverId != null && serverId != localEntityId;

    switch (entityType) {
      case 'todo':
        await _db.todosDao.upsertTodo(_todoCompanionFromJson(serverVersion));
        break;

      case 'note':
        await _db.notesDao.upsertNote(_noteCompanionFromJson(serverVersion));
        break;

      case 'user':
        await _upsertUserFromJson(serverVersion);
        break;

      case 'tag':
        if (idChanged) {
          // ID-adopt: rewrite todo_tags and note_tags from old id → server id
          await _db.transaction(() async {
            await _db.todosDao.upsertTag(_tagCompanionFromJson(serverVersion));
            await _rewriteTagJunctions(
              oldTagId: localEntityId,
              newTagId: serverId,
            );
            // Remove old tag row if different id
            await _db.todosDao.upsertTag(
              TagsTableCompanion(
                id: Value(localEntityId),
                deletedAt: Value(DateTime.now().toUtc().toIso8601String()),
                updatedAt: Value(DateTime.now().toUtc().toIso8601String()),
                name: const Value('__deleted__'),
                color: const Value('#000000'),
                userId: const Value(''),
                createdAt: Value(DateTime.now().toUtc().toIso8601String()),
              ),
            );
          });
        } else {
          await _db.todosDao.upsertTag(_tagCompanionFromJson(serverVersion));
        }
        break;

      case 'habit':
        await _db.habitsDao.upsertHabit(_habitCompanionFromJson(serverVersion));
        break;

      case 'habit_log':
        if (idChanged) {
          // ID-adopt: update references then upsert new row
          await _db.transaction(() async {
            await _db.habitsDao.upsertHabitLog(
              _habitLogCompanionFromJson(serverVersion),
            );
            // Old row becomes tombstone
            await _db.habitsDao.softDeleteHabitLog(
              localEntityId,
              DateTime.now().toUtc().toIso8601String(),
            );
          });
        } else {
          await _db.habitsDao.upsertHabitLog(
            _habitLogCompanionFromJson(serverVersion),
          );
        }
        break;

      case 'checklist_category':
        await _db.checklistsDao.upsertCategory(
          _checklistCategoryCompanionFromJson(serverVersion),
        );
        break;

      case 'checklist_template':
        await _db.checklistsDao.upsertTemplate(
          _templateCompanionFromJson(serverVersion),
        );
        break;

      case 'checklist_template_item':
        await _db.checklistsDao.upsertTemplateItem(
          _templateItemCompanionFromJson(serverVersion),
        );
        break;

      case 'checklist_run':
        await _db.checklistsDao.upsertRun(_runCompanionFromJson(serverVersion));
        break;

      case 'checklist_run_item':
        await _db.checklistsDao.upsertRunItem(
          _runItemCompanionFromJson(serverVersion),
        );
        break;
    }
  }

  Future<void> _rewriteTagJunctions({
    required String oldTagId,
    required String newTagId,
  }) async {
    // This requires raw SQL; for now we take the safe approach of removing
    // old junctions and re-adding them with new tag id.
    // The actual todo_tags rows referencing oldTagId need to be updated.
    // Since Drift doesn't have UPDATE…WHERE across junction easily, we read
    // the affected todoIds and re-set their tags.
    final affected = await (_db.select(
      _db.todoTagsTable,
    )..where((j) => j.tagId.equals(oldTagId))).get();
    for (final j in affected) {
      await (_db.delete(_db.todoTagsTable)..where(
            (row) => row.todoId.equals(j.todoId) & row.tagId.equals(oldTagId),
          ))
          .go();
      await _db
          .into(_db.todoTagsTable)
          .insertOnConflictUpdate(
            TodoTagsTableCompanion.insert(todoId: j.todoId, tagId: newTagId),
          );
    }
    // Same for note_tags
    final affectedNotes = await (_db.select(
      _db.noteTagsTable,
    )..where((j) => j.tagId.equals(oldTagId))).get();
    for (final j in affectedNotes) {
      await (_db.delete(_db.noteTagsTable)..where(
            (row) => row.noteId.equals(j.noteId) & row.tagId.equals(oldTagId),
          ))
          .go();
      await _db
          .into(_db.noteTagsTable)
          .insertOnConflictUpdate(
            NoteTagsTableCompanion.insert(noteId: j.noteId, tagId: newTagId),
          );
    }
  }

  Future<void> _remapPendingEntityReferences(
    String entityType,
    String oldId,
    String newId,
  ) async {
    final rows = await _db.select(_db.syncQueueTable).get();
    for (final row in rows) {
      final payload = SyncPayload.decode(row.payload);
      var changed = false;

      if (row.entityType == entityType && payload['id'] == oldId) {
        payload['id'] = newId;
        changed = true;
      }

      for (final key in const [
        'user_id',
        'parent_id',
        'trigger_after_todo_id',
        'recurrence_template_id',
        'habit_id',
        'template_id',
        'run_id',
        'template_item_id',
        'category_id',
      ]) {
        changed = _replaceScalarRef(payload, key, oldId, newId) || changed;
      }

      for (final key in const [
        'tag_ids',
        'linked_note_ids',
        'linked_todo_ids',
      ]) {
        changed = _replaceListRef(payload, key, oldId, newId) || changed;
      }

      final noteLinks = payload['note_links'];
      if (noteLinks is List) {
        for (final link in noteLinks) {
          if (link is Map<String, dynamic>) {
            changed =
                _replaceScalarRef(link, 'target_note_id', oldId, newId) ||
                changed;
          }
        }
      }

      final sameEntityRow =
          row.entityType == entityType && row.entityId == oldId;
      if (!sameEntityRow && !changed) continue;

      await (_db.update(
        _db.syncQueueTable,
      )..where((q) => q.id.equals(row.id))).write(
        SyncQueueTableCompanion(
          entityId: sameEntityRow ? Value(newId) : const Value.absent(),
          payload: changed
              ? Value(SyncPayload.encode(payload))
              : const Value.absent(),
        ),
      );
    }
  }

  static bool _replaceScalarRef(
    Map<String, dynamic> payload,
    String key,
    String oldId,
    String newId,
  ) {
    if (payload[key] != oldId) return false;
    payload[key] = newId;
    return true;
  }

  static bool _replaceListRef(
    Map<String, dynamic> payload,
    String key,
    String oldId,
    String newId,
  ) {
    final value = payload[key];
    if (value is! List || !value.contains(oldId)) return false;
    payload[key] = value.map((item) => item == oldId ? newId : item).toList();
    return true;
  }

  static Map<String, dynamic> _apiErrorBody(ApiException e) => {
    'error': e.code,
    if (e.issues != null) 'issues': e.issues,
  };

  static Map<String, dynamic> _pushResponseForLog(
    Map<String, dynamic> response,
  ) {
    final results = (response['results'] as List?) ?? const [];
    return {
      if (response['server_time'] != null)
        'server_time': response['server_time'],
      'results': results.map((item) {
        if (item is! Map<String, dynamic>) return {'status': 'malformed'};
        return {
          'id': item['id'],
          'status': item['status'],
          if (item['error'] != null) 'error': item['error'],
          'has_server_version': item['server_version'] != null,
        };
      }).toList(),
    };
  }

  static String _opTypesForLog(List<SyncQueueRow> rows) {
    final counts = <String, int>{};
    for (final row in rows) {
      final key = '${row.entityType}:${row.operation}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries.map((e) => '${e.key}=${e.value}').join(',');
  }

  static String _resultSummary(List<dynamic> results) {
    final counts = <String, int>{};
    for (final item in results) {
      if (item is! Map<String, dynamic>) {
        counts['malformed'] = (counts['malformed'] ?? 0) + 1;
        continue;
      }
      final status = item['status'] as String? ?? 'unknown';
      final error = item['error'] as String?;
      final key = error == null ? status : '$status:$error';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries.map((e) => '${e.key}=${e.value}').join(',');
  }

  static void _logSyncFailure({
    required String method,
    required String url,
    required int status,
    required Object? responseBody,
    int? opCount,
    String? opTypes,
    String? resultSummary,
  }) {
    debugPrint(
      '[SyncWorker] $method $url failed '
      'status=$status '
      'response=${_jsonForLog(responseBody)}'
      '${opCount == null ? '' : ' op_count=$opCount'}'
      '${opTypes == null ? '' : ' op_types=$opTypes'}'
      '${resultSummary == null ? '' : ' result_summary=$resultSummary'}',
    );
  }

  static String _jsonForLog(Object? value) {
    String text;
    try {
      text = jsonEncode(value);
    } catch (_) {
      text = '$value';
    }
    const max = 1500;
    return text.length <= max ? text : '${text.substring(0, max)}...';
  }

  // ─────────────────────────────────────────────────────────────────
  // M5c: PULL + LWW merge
  // ─────────────────────────────────────────────────────────────────

  Future<void> pullChanges() async {
    final since = await _db.syncDao.getLastSyncedAt();

    Map<String, dynamic> response;
    try {
      final resp = await _client.get(
        '/sync/changes',
        queryParameters: since != null ? {'since': since} : null,
      );
      response = resp as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') return;
      _logSyncFailure(
        method: 'GET',
        url: '/sync/changes',
        status: e.statusCode,
        responseBody: _apiErrorBody(e),
      );
      rethrow;
    }

    final serverTime = response['server_time'] as String?;
    if (serverTime == null || serverTime.isEmpty) {
      throw const ApiException(
        0,
        'bad_input',
        'sync changes response missing server_time',
      );
    }
    final rawChanges = response['changes'];
    if (rawChanges is! Map<String, dynamic>) {
      throw const ApiException(
        0,
        'bad_input',
        'sync changes response missing changes map',
      );
    }
    final changes = rawChanges;

    // Track tombstone IDs per entity type for self-heal
    final Map<String, List<String>> tombstoneIds = {};

    // Helper: record tombstone
    void recordTombstone(String entityType, String id) {
      tombstoneIds.putIfAbsent(entityType, () => []).add(id);
    }

    // ── Process each entity type ──────────────────────────────────

    await _processEntityList<Map<String, dynamic>>(
      changes['users'] as List? ?? const [],
      entityType: 'user',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => _upsertUserFromJson(map),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        if (await _shouldSkipLww('user', id, map['updated_at'] as String)) {
          return;
        }
        await _upsertUserFromJson(map);
        await _db.syncDao.removeOpsForEntity('user', id);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['tags'] as List? ?? const [],
      entityType: 'tag',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async =>
          await _db.todosDao.upsertTag(_tagCompanionFromJson(map)),
      applyUpsert: (map) async {
        if (await _shouldSkipLww(
          'tag',
          map['id'] as String,
          map['updated_at'] as String,
        )) {
          return;
        }
        await _db.todosDao.upsertTag(_tagCompanionFromJson(map));
        await _db.syncDao.removeOpsForEntity('tag', map['id'] as String);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['todos'] as List? ?? const [],
      entityType: 'todo',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => await _db.todosDao.softDeleteTodo(
        map['id'] as String,
        map['deleted_at'] as String,
      ),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        if (await _shouldSkipLww('todo', id, map['updated_at'] as String)) {
          return;
        }
        await _db.todosDao.upsertTodo(_todoCompanionFromJson(map));
        // Reconcile tag_ids junction
        final isSubtask = map['parent_id'] != null;
        final tagIds = isSubtask
            ? const <String>[]
            : (map['tag_ids'] as List?)?.map((e) => e as String).toList() ??
                  const <String>[];
        await _db.todosDao.setTodoTags(id, tagIds);
        await _db.syncDao.removeOpsForEntity('todo', id);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['notes'] as List? ?? const [],
      entityType: 'note',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => await _db.notesDao.softDeleteNote(
        map['id'] as String,
        map['deleted_at'] as String,
      ),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        if (await _shouldSkipLww('note', id, map['updated_at'] as String)) {
          return;
        }
        await _db.notesDao.upsertNote(_noteCompanionFromJson(map));
        // Reconcile tag_ids
        final tagIds =
            (map['tag_ids'] as List?)?.map((e) => e as String).toList() ??
            const [];
        await _db.notesDao.setNoteTags(id, tagIds);
        // Reconcile note_links
        final noteLinks = (map['note_links'] as List?) ?? const [];
        await (_db.delete(
          _db.noteLinksTable,
        )..where((l) => l.sourceNoteId.equals(id))).go();
        for (final link in noteLinks) {
          final lmap = link as Map<String, dynamic>;
          final targetNoteId = lmap['target_note_id'] as String;
          final now = DateTime.now().toUtc().toIso8601String();
          await _db.notesDao.upsertNoteLink(
            NoteLinksTableCompanion(
              id: Value(lmap['id'] as String? ?? '$id->$targetNoteId'),
              sourceNoteId: Value(id),
              targetNoteId: Value(targetNoteId),
              label: Value(lmap['label'] as String?),
              createdAt: Value(lmap['created_at'] as String? ?? now),
              updatedAt: Value(lmap['updated_at'] as String? ?? now),
              deletedAt: const Value(null),
            ),
          );
        }
        // Reconcile linked_todo_ids
        final linkedTodoIds =
            (map['linked_todo_ids'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [];
        // Remove old links then insert new
        final existing = await _db.notesDao.getTodoLinksForNote(id);
        for (final e in existing) {
          if (!linkedTodoIds.contains(e.todoId)) {
            await _db.notesDao.removeNoteTodoLink(id, e.todoId);
          }
        }
        final existingIds = existing.map((e) => e.todoId).toSet();
        for (final tid in linkedTodoIds) {
          if (!existingIds.contains(tid)) {
            await _db.notesDao.upsertNoteTodoLink(
              NoteTodoLinksTableCompanion.insert(
                noteId: id,
                todoId: tid,
                createdAt: DateTime.now().toUtc().toIso8601String(),
              ),
            );
          }
        }
        await _db.syncDao.removeOpsForEntity('note', id);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['habits'] as List? ?? const [],
      entityType: 'habit',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => await _db.habitsDao.softDeleteHabit(
        map['id'] as String,
        map['deleted_at'] as String,
      ),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        final serverUpdatedAt = map['updated_at'] as String;
        // Streak from sync is cached, while UI can derive from logs when present.
        final existing = await _db.habitsDao.getHabitById(id);
        if (existing != null && existing.updatedAt != serverUpdatedAt) {
          await _db.habitsDao.adoptStreak(
            id,
            (map['current_streak'] as num?)?.toInt() ?? 0,
            (map['longest_streak'] as num?)?.toInt() ?? 0,
            serverUpdatedAt,
          );
        }
        if (await _shouldSkipLww('habit', id, serverUpdatedAt)) {
          return;
        }
        await _db.habitsDao.upsertHabit(_habitCompanionFromJson(map));
        await _db.syncDao.removeOpsForEntity('habit', id);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['habit_logs'] as List? ?? const [],
      entityType: 'habit_log',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => await _db.habitsDao.softDeleteHabitLog(
        map['id'] as String,
        map['deleted_at'] as String,
      ),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        if (await _shouldSkipLww(
          'habit_log',
          id,
          map['updated_at'] as String,
        )) {
          return;
        }
        await _db.habitsDao.upsertHabitLog(_habitLogCompanionFromJson(map));
        await _db.syncDao.removeOpsForEntity('habit_log', id);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['checklist_categories'] as List? ?? const [],
      entityType: 'checklist_category',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => await _db.checklistsDao.softDeleteCategory(
        map['id'] as String,
        map['deleted_at'] as String,
      ),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        if (await _shouldSkipLww(
          'checklist_category',
          id,
          map['updated_at'] as String,
        )) {
          return;
        }
        await _db.checklistsDao.upsertCategory(
          _checklistCategoryCompanionFromJson(map),
        );
        await _db.syncDao.removeOpsForEntity('checklist_category', id);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['checklist_templates'] as List? ?? const [],
      entityType: 'checklist_template',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => await _db.checklistsDao.softDeleteTemplate(
        map['id'] as String,
        map['deleted_at'] as String,
      ),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        if (await _shouldSkipLww(
          'checklist_template',
          id,
          map['updated_at'] as String,
        )) {
          return;
        }
        await _db.checklistsDao.upsertTemplate(_templateCompanionFromJson(map));
        await _db.syncDao.removeOpsForEntity('checklist_template', id);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['checklist_template_items'] as List? ?? const [],
      entityType: 'checklist_template_item',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async =>
          await _db.checklistsDao.softDeleteTemplateItem(
            map['id'] as String,
            map['deleted_at'] as String,
          ),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        if (await _shouldSkipLww(
          'checklist_template_item',
          id,
          map['updated_at'] as String,
        )) {
          return;
        }
        await _db.checklistsDao.upsertTemplateItem(
          _templateItemCompanionFromJson(map),
        );
        await _db.syncDao.removeOpsForEntity('checklist_template_item', id);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['checklist_runs'] as List? ?? const [],
      entityType: 'checklist_run',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => await _db.checklistsDao.softDeleteRun(
        map['id'] as String,
        map['deleted_at'] as String,
      ),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        if (await _shouldSkipLww(
          'checklist_run',
          id,
          map['updated_at'] as String,
        )) {
          return;
        }
        await _db.checklistsDao.upsertRun(_runCompanionFromJson(map));
        await _db.syncDao.removeOpsForEntity('checklist_run', id);
      },
    );

    await _processEntityList<Map<String, dynamic>>(
      changes['checklist_run_items'] as List? ?? const [],
      entityType: 'checklist_run_item',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => await _db.checklistsDao.softDeleteRunItem(
        map['id'] as String,
        map['deleted_at'] as String,
      ),
      applyUpsert: (map) async {
        final id = map['id'] as String;
        if (await _shouldSkipLww(
          'checklist_run_item',
          id,
          map['updated_at'] as String,
        )) {
          return;
        }
        await _db.checklistsDao.upsertRunItem(_runItemCompanionFromJson(map));
        await _db.syncDao.removeOpsForEntity('checklist_run_item', id);
      },
    );

    // ── Self-heal: remove junctions pointing to tombstones (scoped) ──

    final todoTombstones = tombstoneIds['todo'] ?? const [];
    if (todoTombstones.isNotEmpty) {
      await _db.todosDao.cleanJunctionsForDeletedTodos(todoTombstones);
      // Self-heal: remove note_todo_links pointing to tombstoned todos
      if (todoTombstones.isNotEmpty) {
        await (_db.delete(
          _db.noteTodoLinksTable,
        )..where((l) => l.todoId.isIn(todoTombstones))).go();
      }
    }
    final noteTombstones = tombstoneIds['note'] ?? const [];
    if (noteTombstones.isNotEmpty) {
      await _db.notesDao.cleanJunctionsForDeletedNotes(noteTombstones);
    }

    // ── Update lastSyncedAt ───────────────────────────────────────

    await _db.syncDao.setLastSyncedAt(serverTime);

    // ── Post-pull hook (e.g. generate recurrence instances) ──────
    _postPullHook?.call().ignore();
  }

  // ─── LWW (Last-Write-Wins) check ─────────────────────────────────

  /// Returns true if the local version is newer-or-equal AND has pending ops,
  /// meaning we should NOT overwrite it with server data.
  Future<bool> _shouldSkipLww(
    String entityType,
    String entityId,
    String serverUpdatedAt,
  ) async {
    // Check if there's a pending sync op for this entity
    final pending =
        await (_db.select(_db.syncQueueTable)
              ..where(
                (q) =>
                    q.entityType.equals(entityType) &
                    q.entityId.equals(entityId),
              )
              ..limit(1))
            .getSingleOrNull();
    if (pending == null) return false;

    // Fetch local updatedAt
    final localUpdatedAt = await _getLocalUpdatedAt(entityType, entityId);
    if (localUpdatedAt == null) return false;

    // If local >= server, keep local
    return localUpdatedAt.compareTo(serverUpdatedAt) >= 0;
  }

  Future<String?> _getLocalUpdatedAt(String entityType, String entityId) async {
    switch (entityType) {
      case 'user':
        return (await (_db.select(
          _db.usersTable,
        )..where((u) => u.id.equals(entityId))).getSingleOrNull())?.updatedAt;
      case 'tag':
        return (await (_db.select(
          _db.tagsTable,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull())?.updatedAt;
      case 'todo':
        return (await _db.todosDao.getTodoById(entityId))?.updatedAt;
      case 'note':
        return (await _db.notesDao.getNoteById(entityId))?.updatedAt;
      case 'habit':
        return (await _db.habitsDao.getHabitById(entityId))?.updatedAt;
      case 'habit_log':
        return (await _db.habitsDao.getHabitLogById(entityId))?.updatedAt;
      case 'checklist_category':
        return (await _db.checklistsDao.getCategoryById(entityId))?.updatedAt;
      case 'checklist_template':
        return (await _db.checklistsDao.getTemplateById(entityId))?.updatedAt;
      case 'checklist_template_item':
        return (await (_db.select(
          _db.checklistTemplateItemsTable,
        )..where((i) => i.id.equals(entityId))).getSingleOrNull())?.updatedAt;
      case 'checklist_run':
        return (await _db.checklistsDao.getRunById(entityId))?.updatedAt;
      case 'checklist_run_item':
        return (await (_db.select(
          _db.checklistRunItemsTable,
        )..where((i) => i.id.equals(entityId))).getSingleOrNull())?.updatedAt;
    }
    return null;
  }

  // ─── Entity-list processor ────────────────────────────────────────

  Future<void> _processEntityList<T>(
    List<dynamic> list, {
    required String entityType,
    required void Function(String, String) tombstoneRecord,
    required Future<void> Function(Map<String, dynamic>) applyDeleted,
    required Future<void> Function(Map<String, dynamic>) applyUpsert,
  }) async {
    var failures = 0;
    for (final item in list) {
      Map<String, dynamic>? map;
      String id = '?';
      try {
        map = item as Map<String, dynamic>;
        id = map['id'] as String? ?? '?';
        if (map['deleted_at'] != null) {
          tombstoneRecord(entityType, id);
          await applyDeleted(map);
        } else {
          await applyUpsert(map);
        }
      } catch (e, st) {
        failures++;
        debugPrint('[SyncWorker] ⚠️  Skip $entityType#$id: $e');
        debugPrint(
          '[SyncWorker]    ${st.toString().split('\n').take(6).join('\n')}',
        );
      }
    }
    if (failures > 0) {
      throw StateError('failed to apply $failures $entityType sync record(s)');
    }
  }

  // ─── JSON → Drift companion converters ───────────────────────────

  Future<void> _upsertUserFromJson(Map<String, dynamic> map) async {
    await _db
        .into(_db.usersTable)
        .insertOnConflictUpdate(_userCompanionFromJson(map));
  }

  static UsersTableCompanion _userCompanionFromJson(Map<String, dynamic> j) {
    final now = DateTime.now().toUtc().toIso8601String();
    return UsersTableCompanion(
      id: Value(_req(j, 'id')),
      email: Value(j['email'] as String? ?? ''),
      displayName: Value(j['display_name'] as String?),
      avatarUrl: Value(j['avatar_url'] as String?),
      timezone: Value(j['timezone'] as String?),
      settings: Value(_settingsToString(j['settings'])),
      createdAt: Value(j['created_at'] as String? ?? now),
      updatedAt: Value(
        j['updated_at'] as String? ?? j['deleted_at'] as String? ?? now,
      ),
      deletedAt: Value(j['deleted_at'] as String?),
    );
  }

  static TagsTableCompanion _tagCompanionFromJson(Map<String, dynamic> j) =>
      TagsTableCompanion(
        id: Value(_req(j, 'id')),
        name: Value(_req(j, 'name')),
        color: Value(j['color'] as String? ?? '#888888'),
        userId: Value(j['user_id'] as String? ?? ''),
        createdAt: Value(_req(j, 'created_at')),
        updatedAt: Value(_req(j, 'updated_at')),
        deletedAt: Value(j['deleted_at'] as String?),
      );

  static TodosTableCompanion _todoCompanionFromJson(Map<String, dynamic> j) {
    final isSubtask = j['parent_id'] != null;
    return TodosTableCompanion(
      id: Value(_req(j, 'id')),
      userId: Value(j['user_id'] as String? ?? ''),
      parentId: Value(j['parent_id'] as String?),
      title: Value(_req(j, 'title')),
      description: Value(isSubtask ? null : j['description'] as String?),
      status: Value(j['status'] as String? ?? 'open'),
      position: Value((j['position'] as num?)?.toInt() ?? 0),
      isFrog: Value(isSubtask ? false : _parseBool(j['is_frog'])),
      frogDate: Value(isSubtask ? null : j['frog_date'] as String?),
      isImportant: Value(
        isSubtask ? null : _parseBoolNullable(j['is_important']),
      ),
      isUrgent: Value(isSubtask ? null : _parseBoolNullable(j['is_urgent'])),
      estimatedMinutes: Value(
        isSubtask ? null : (j['estimated_minutes'] as num?)?.toInt(),
      ),
      actualMinutes: Value(
        isSubtask ? null : (j['actual_minutes'] as num?)?.toInt(),
      ),
      startAt: Value(isSubtask ? null : j['start_at'] as String?),
      dueAt: Value(isSubtask ? null : j['due_at'] as String?),
      scheduledDate: Value(isSubtask ? null : j['scheduled_date'] as String?),
      triggerAfterTodoId: Value(
        isSubtask ? null : j['trigger_after_todo_id'] as String?,
      ),
      completedAt: Value(j['completed_at'] as String?),
      createdAt: Value(_req(j, 'created_at')),
      updatedAt: Value(_req(j, 'updated_at')),
      deletedAt: Value(j['deleted_at'] as String?),
      recurrenceType: Value(isSubtask ? null : j['recurrence_type'] as String?),
      recurrenceInterval: Value(
        isSubtask ? null : (j['recurrence_interval'] as num?)?.toInt(),
      ),
      recurrenceWeekdays: Value(
        isSubtask ? null : j['recurrence_days_of_week'] as String?,
      ),
      recurrenceEndDate: Value(
        isSubtask ? null : j['recurrence_end_date'] as String?,
      ),
      recurrenceTemplateId: Value(
        isSubtask ? null : j['recurrence_template_id'] as String?,
      ),
    );
  }

  static NotesTableCompanion _noteCompanionFromJson(Map<String, dynamic> j) =>
      NotesTableCompanion(
        id: Value(_req(j, 'id')),
        userId: Value(j['user_id'] as String? ?? ''),
        title: Value(_req(j, 'title')),
        type: Value(j['type'] as String? ?? 'free'),
        body: Value(j['body'] as String?),
        cornellCue: Value(j['cornell_cue'] as String?),
        cornellSummary: Value(j['cornell_summary'] as String?),
        isPinned: Value(_parseBool(j['is_pinned'])),
        createdAt: Value(_req(j, 'created_at')),
        updatedAt: Value(_req(j, 'updated_at')),
        deletedAt: Value(j['deleted_at'] as String?),
      );

  static HabitsTableCompanion _habitCompanionFromJson(Map<String, dynamic> j) =>
      HabitsTableCompanion(
        id: Value(_req(j, 'id')),
        userId: Value(j['user_id'] as String? ?? ''),
        title: Value(_req(j, 'title')),
        description: Value(j['description'] as String?),
        iconName: Value(j['icon'] as String?),
        color: Value(j['color'] as String? ?? '#4CAF50'),
        frequencyType: Value(j['frequency_type'] as String? ?? 'daily'),
        targetPerPeriod: Value((j['target_per_period'] as num?)?.toInt() ?? 1),
        activeWeekdays: Value(j['active_weekdays'] as String?),
        startDate: Value(_req(j, 'start_date')),
        endDate: Value(j['end_date'] as String?),
        currentStreak: Value((j['current_streak'] as num?)?.toInt() ?? 0),
        longestStreak: Value((j['longest_streak'] as num?)?.toInt() ?? 0),
        isArchived: Value(_parseBool(j['is_archived'])),
        createdAt: Value(_req(j, 'created_at')),
        updatedAt: Value(_req(j, 'updated_at')),
        deletedAt: Value(j['deleted_at'] as String?),
      );

  static HabitLogsTableCompanion _habitLogCompanionFromJson(
    Map<String, dynamic> j,
  ) => HabitLogsTableCompanion(
    id: Value(_req(j, 'id')),
    habitId: Value(_req(j, 'habit_id')),
    userId: Value(j['user_id'] as String? ?? ''),
    logDate: Value(_req(j, 'log_date')),
    completed: Value(_parseBool(j['completed'] ?? true)),
    note: Value(j['note'] as String?),
    createdAt: Value(_req(j, 'created_at')),
    updatedAt: Value(_req(j, 'updated_at')),
    deletedAt: Value(j['deleted_at'] as String?),
  );

  static ChecklistCategoriesTableCompanion _checklistCategoryCompanionFromJson(
    Map<String, dynamic> j,
  ) => ChecklistCategoriesTableCompanion(
    id: Value(_req(j, 'id')),
    userId: Value(j['user_id'] as String? ?? ''),
    name: Value(_req(j, 'name')),
    slug: Value(j['slug'] as String? ?? ''),
    icon: Value(j['icon'] as String?),
    color: Value(j['color'] as String? ?? '#4F46E5'),
    sortOrder: Value((j['sort_order'] as num?)?.toInt() ?? 0),
    isSystem: Value(_parseBool(j['is_system'])),
    createdAt: Value(_req(j, 'created_at')),
    updatedAt: Value(_req(j, 'updated_at')),
    deletedAt: Value(j['deleted_at'] as String?),
  );

  static ChecklistTemplatesTableCompanion _templateCompanionFromJson(
    Map<String, dynamic> j,
  ) => ChecklistTemplatesTableCompanion(
    id: Value(_req(j, 'id')),
    userId: Value(j['user_id'] as String?),
    title: Value(_req(j, 'title')),
    description: Value(j['description'] as String?),
    icon: Value(j['icon'] as String?),
    category: Value(j['category'] as String?),
    categoryId: Value(j['category_id'] as String?),
    isSystem: Value(_parseBool(j['is_system'])),
    timesUsed: Value((j['times_used'] as num?)?.toInt() ?? 0),
    lastUsedAt: Value(j['last_used_at'] as String?),
    createdAt: Value(_req(j, 'created_at')),
    updatedAt: Value(_req(j, 'updated_at')),
    deletedAt: Value(j['deleted_at'] as String?),
  );

  static ChecklistTemplateItemsTableCompanion _templateItemCompanionFromJson(
    Map<String, dynamic> j,
  ) => ChecklistTemplateItemsTableCompanion(
    id: Value(_req(j, 'id')),
    templateId: Value(_req(j, 'template_id')),
    title: Value(_req(j, 'title')),
    description: Value(j['description'] as String?),
    isRequired: Value(_parseBool(j['is_required'])),
    // contract sends 'position'; stored locally in the orderIndex column
    orderIndex: Value((j['position'] as num?)?.toInt() ?? 0),
    createdAt: Value(_req(j, 'created_at')),
    updatedAt: Value(_req(j, 'updated_at')),
    deletedAt: Value(j['deleted_at'] as String?),
  );

  static ChecklistRunsTableCompanion _runCompanionFromJson(
    Map<String, dynamic> j,
  ) => ChecklistRunsTableCompanion(
    id: Value(_req(j, 'id')),
    templateId: Value(_req(j, 'template_id')),
    userId: Value(j['user_id'] as String? ?? ''),
    name: Value(j['name'] as String?),
    status: Value(j['status'] as String? ?? 'in_progress'),
    completedAt: Value(j['completed_at'] as String?),
    // server sends 'started_at'; stored locally in the createdAt column
    createdAt: Value(
      j['started_at'] as String? ??
          j['created_at'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
    ),
    updatedAt: Value(_req(j, 'updated_at')),
    deletedAt: Value(j['deleted_at'] as String?),
  );

  static ChecklistRunItemsTableCompanion _runItemCompanionFromJson(
    Map<String, dynamic> j,
  ) => ChecklistRunItemsTableCompanion(
    id: Value(_req(j, 'id')),
    runId: Value(_req(j, 'run_id')),
    templateItemId: Value(j['template_item_id'] as String?),
    title: Value(j['title'] as String? ?? ''),
    isRequired: Value(_parseBool(j['is_required'])),
    status: Value(j['status'] as String? ?? 'pending'),
    completedAt: Value(j['completed_at'] as String?),
    note: Value(j['note'] as String?),
    orderIndex: Value(
      (j['position'] as num?)?.toInt() ??
          (j['order_index'] as num?)?.toInt() ??
          0,
    ),
    createdAt: Value(_req(j, 'created_at')),
    updatedAt: Value(_req(j, 'updated_at')),
    deletedAt: Value(j['deleted_at'] as String?),
  );

  static String? _settingsToString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return jsonEncode(value);
  }

  // ─── Bool parse helpers (contract uses true/false JSON booleans) ──

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0; // fallback for legacy REST responses
    return false;
  }

  static bool? _parseBoolNullable(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is int) return v != 0;
    return null;
  }

  // ─── Null-safe field extractors ──────────────────────────────────

  /// Require a non-null String field.
  /// Throws [StateError] with a descriptive message so the per-record
  /// try/catch in [_processEntityList] can log it and skip the record.
  static String _req(Map<String, dynamic> j, String key) {
    final v = j[key];
    if (v == null) throw StateError('required field "$key" is null or absent');
    return v as String;
  }
}
