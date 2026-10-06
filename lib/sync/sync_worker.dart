import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/api_exception.dart';
import '../data/auth_storage.dart';
import '../data/local/database.dart';
import '../data/remote/api_client_dio.dart';
import '../utils/dashboard_local_events.dart';
import '../utils/note_delta_utils.dart';
import '../utils/note_local_events.dart';
import '../utils/todo_local_events.dart';
import 'sync_payload.dart';
import 'sync_status_notifier.dart';

enum SyncRunResult { success, retry, authRequired, failed }

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
  SyncWorker._({
    AppDatabase? database,
    ApiClientDio? client,
    bool Function()? hasAuthSession,
    String Function()? currentUserId,
  }) : _db = database ?? AppDatabase.instance,
       _client = client ?? ApiClientDio.instance,
       _hasAuthSession =
           hasAuthSession ?? (() => AuthStorage.instance.currentToken != null),
       _currentUserId =
           currentUserId ??
           (() => AuthStorage.instance.currentUserJson?['id'] as String? ?? '');
  static final SyncWorker instance = SyncWorker._();

  factory SyncWorker.forTesting({
    required AppDatabase database,
    required ApiClientDio client,
    String userId = 'user-1',
  }) {
    return SyncWorker._(
      database: database,
      client: client,
      hasAuthSession: () => true,
      currentUserId: () => userId,
    );
  }

  final AppDatabase _db;
  final ApiClientDio _client;
  final bool Function() _hasAuthSession;
  final String Function() _currentUserId;

  Future<SyncRunResult>? _activeSync;

  String _requireCurrentUserId() {
    final userId = _currentUserId();
    if (userId.isEmpty) {
      throw const ApiException(
        401,
        'unauthorized',
        'Authenticated user id is required for sync',
      );
    }
    return userId;
  }

  // ── Post-pull hook ────────────────────────────────────────────
  // Registered by TodosRepository to generate recurrence instances
  // after a pull without creating a circular import chain.
  static Future<void> Function()? _postPullHook;
  static void registerPostPullHook(Future<void> Function() hook) {
    _postPullHook = hook;
  }

  // ─── Public API ───────────────────────────────────────────────────

  Future<SyncRunResult> sync() {
    final active = _activeSync;
    if (active != null) return active;
    final run = _runSync().whenComplete(() {
      _activeSync = null;
    });
    _activeSync = run;
    return run;
  }

  Future<SyncRunResult> _runSync() async {
    if (!_hasAuthSession()) {
      debugPrint('[SyncWorker] Skip sync: no auth token');
      return SyncRunResult.authRequired;
    }
    final userId = _requireCurrentUserId();
    SyncStatusNotifier.instance.beginSync();
    String? errorMsg;
    var result = SyncRunResult.success;
    try {
      await pushPending(userId: userId);
      await pullChanges(userId: userId);
    } on ApiException catch (e) {
      errorMsg =
          '[${e.code}] ${e.message}'
          '${e.requestId == null ? '' : ' request_id=${e.requestId}'}';
      debugPrint('[SyncWorker] Sync ApiException: $errorMsg');
      result = e.isAuthError
          ? SyncRunResult.authRequired
          : e.isRetryable
          ? SyncRunResult.retry
          : SyncRunResult.failed;
    } catch (e, st) {
      errorMsg = e.toString();
      debugPrint('[SyncWorker] Sync unexpected error: $e\n$st');
      result = SyncRunResult.failed;
    } finally {
      final pending = await _db.syncDao.getPendingCount(userId: userId);
      final deadLetters = await _db.syncDao.getDeadLetterCount(userId: userId);
      if (deadLetters > 0) {
        errorMsg ??= '$deadLetters thao tác đồng bộ cần kiểm tra';
      }
      SyncStatusNotifier.instance.endSync(
        pendingCount: pending,
        error: errorMsg,
      );
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────
  // M5b: PUSH
  // ─────────────────────────────────────────────────────────────────

  Future<void> pushPending({String? userId}) async {
    final ownerId = userId ?? _requireCurrentUserId();
    while (true) {
      final all = await _db.syncDao.getDueBatch(userId: ownerId, limit: 10000);
      if (all.isEmpty) return;

      final sorted = sortedByDependency<SyncQueueRow>(
        rows: all,
        getEntityType: (r) => r.entityType,
        getId: (r) => r.id,
      ).take(100).toList();

      // Drop illegal system checklist writes. Backend returns read_only for
      // these, so removing them locally disables the invalid queued action.
      final eligibleRows = <SyncQueueRow>[];
      for (final row in sorted) {
        if (await _dropGeneratedRecurrenceInstanceOp(row)) {
          continue;
        }
        if (row.entityType == 'checklist_template' &&
            (row.operation == 'update' || row.operation == 'delete')) {
          final t = await _db.checklistsDao.getTemplateById(row.entityId);
          if (t?.isSystem == true) {
            await _db.syncDao.removeSyncOp(row.id, userId: ownerId);
            continue;
          }
        }
        if (row.entityType == 'checklist_category' &&
            (row.operation == 'update' || row.operation == 'delete')) {
          final category = await _db.checklistsDao.getCategoryById(
            row.entityId,
          );
          if (category?.isSystem == true) {
            await _db.syncDao.removeSyncOp(row.id, userId: ownerId);
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
        _logSyncFailure(
          method: 'POST',
          url: '/sync/push',
          status: e.statusCode,
          responseBody: _apiErrorBody(e),
          opCount: ops.length,
          opTypes: _opTypesForLog(eligibleRows),
        );
        if (e.isAuthError) rethrow;
        final permanentHttp =
            e.statusCode >= 400 &&
            e.statusCode < 500 &&
            e.statusCode != 408 &&
            e.statusCode != 425 &&
            e.statusCode != 429;
        for (final row in eligibleRows) {
          if (permanentHttp) {
            await _db.syncDao.markPermanentFailure(
              row.id,
              userId: ownerId,
              error: 'http_${e.statusCode}:${e.code}',
            );
          } else {
            await _db.syncDao.markFailedRetryable(
              row.id,
              row.retryCount,
              userId: ownerId,
              error: 'http_${e.statusCode}:${e.code}',
            );
          }
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
            await _db.syncDao.removeSyncOp(queueRow.id, userId: ownerId);
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
                userId: ownerId,
                error: 'conflict_missing_server',
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
                ownerId,
              );
            }
            await _db.syncDao.removeSyncOp(queueRow.id, userId: ownerId);
            break;

          case 'error':
            final error = map['error'] as String? ?? 'unknown';
            if (error == 'invalid_habit' && queueRow.entityType == 'todo') {
              await _clearInvalidHabitLinkAndRetry(queueRow);
            } else if (error == 'read_only' &&
                (queueRow.entityType == 'checklist_template' ||
                    queueRow.entityType == 'checklist_category') &&
                (queueRow.operation == 'update' ||
                    queueRow.operation == 'delete')) {
              await _db.syncDao.removeSyncOp(queueRow.id, userId: ownerId);
            } else if (error == 'not_found' && queueRow.operation == 'delete') {
              await _db.syncDao.removeSyncOp(queueRow.id, userId: ownerId);
            } else if (_isPermanentSyncError(error)) {
              resultErrors.add('${queueRow.entityType}:$error');
              await _db.syncDao.markPermanentFailure(
                queueRow.id,
                userId: ownerId,
                error: error,
              );
            } else {
              resultErrors.add('${queueRow.entityType}:$error');
              await _db.syncDao.markFailedRetryable(
                queueRow.id,
                queueRow.retryCount,
                userId: ownerId,
                error: error,
              );
            }
            break;

          default:
            resultErrors.add('${queueRow.entityType}:unknown_status_$status');
            await _db.syncDao.markFailedRetryable(
              queueRow.id,
              queueRow.retryCount,
              userId: ownerId,
              error: 'unknown_status_$status',
            );
            break;
        }
      }

      for (final row in eligibleRows) {
        if (!resultIds.contains(row.entityId)) {
          resultErrors.add('${row.entityType}:missing_result');
          await _db.syncDao.markFailedRetryable(
            row.id,
            row.retryCount,
            userId: ownerId,
            error: 'missing_result',
          );
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

  static bool _isPermanentSyncError(String error) {
    return const {
      'bad_input',
      'forbidden',
      'read_only',
      'invalid_ownership',
      'validation_error',
      'payload_validation_error',
      'not_found',
    }.contains(error);
  }

  Future<void> _clearInvalidHabitLinkAndRetry(SyncQueueRow queueRow) async {
    final payload = SyncPayload.decode(queueRow.payload);
    final now = DateTime.now().toUtc().toIso8601String();
    payload['habit_id'] = null;
    payload['updated_at'] = now;

    await (_db.update(
      _db.todosTable,
    )..where((t) => t.id.equals(queueRow.entityId))).write(
      TodosTableCompanion(
        habitId: const Value<String?>(null),
        updatedAt: Value(now),
      ),
    );
    await (_db.update(
      _db.syncQueueTable,
    )..where((q) => q.id.equals(queueRow.id))).write(
      SyncQueueTableCompanion(
        payload: Value(SyncPayload.encode(payload)),
        retryCount: const Value(0),
        nextRetryAt: const Value(null),
      ),
    );
    debugPrint(
      '[SyncWorker] Cleared invalid habit link for todo ${queueRow.entityId}; retrying todo sync',
    );
  }

  Future<bool> _dropGeneratedRecurrenceInstanceOp(SyncQueueRow row) async {
    if (row.entityType != 'todo') return false;

    Map<String, dynamic> payload;
    try {
      payload = SyncPayload.decode(row.payload);
    } catch (_) {
      return false;
    }

    if (shouldDropGeneratedRecurrenceOperation(
      operation: row.operation,
      payload: payload,
      isLocalProjection: false,
    )) {
      debugPrint(
        '[SyncWorker] Drop generated recurrence projection create ${row.entityId}',
      );
      await _db.syncDao.removeSyncOp(row.id, userId: row.userId);
      return true;
    }

    if (row.operation != 'delete') return false;
    if (payload['delete_scope'] != null) return false;
    final localRow =
        await (_db.select(_db.todosTable)
              ..where((t) => t.id.equals(row.entityId))
              ..limit(1))
            .getSingleOrNull();
    final isLocalProjection =
        localRow?.recurrenceTemplateId != null &&
        localRow?.recurrenceType == null;
    if (!shouldDropGeneratedRecurrenceOperation(
      operation: row.operation,
      payload: payload,
      isLocalProjection: isLocalProjection,
    )) {
      return false;
    }

    debugPrint(
      '[SyncWorker] Drop generated recurrence projection delete ${row.entityId}',
    );
    await _db.syncDao.removeSyncOp(row.id, userId: row.userId);
    return true;
  }

  Future<void> _adoptServerRecurringOccurrence(
    Map<String, dynamic> json,
  ) async {
    final id = json['id'] as String?;
    final templateId = json['recurrence_template_id'] as String?;
    final scheduledDate = json['scheduled_date'] as String?;
    if (id == null || templateId == null || scheduledDate == null) return;

    final existing = await _db.todosDao.getOccurrenceForSeriesDate(
      templateId,
      scheduledDate,
    );
    if (existing == null || existing.id == id) return;

    final removedIds = await _db.todosDao.purgeTodoSubtree(
      existing.id,
      userId: existing.userId,
    );
    for (final removedId in removedIds) {
      await _db.syncDao.removeOpsForEntity(
        'todo',
        removedId,
        userId: existing.userId,
      );
    }
  }

  Future<void> _enforceServerFrogTruth(
    Map<String, dynamic> json, {
    required String ownerId,
  }) async {
    if (!_parseBool(json['is_frog'])) return;
    final id = json['id'] as String?;
    if (id == null) return;
    final isSubtask = json['parent_id'] != null;
    final scheduledDate = isSubtask ? null : json['scheduled_date'] as String?;
    final frogDate = json['frog_date'] as String? ?? scheduledDate;
    if (frogDate == null) return;
    final userId = (json['user_id'] as String?)?.isNotEmpty == true
        ? json['user_id'] as String
        : ownerId;
    if (userId.isEmpty) return;

    final clearedRows = await _db.todosDao.clearOtherFrogsForDate(
      userId: userId,
      dateOnly: frogDate,
      updatedAtIso:
          (json['updated_at'] as String?) ??
          DateTime.now().toUtc().toIso8601String(),
      exceptId: id,
    );
    for (final row in clearedRows) {
      final pending = await _db.syncDao.getPendingForEntity(
        'todo',
        row.id,
        userId: userId,
      );
      if (pending != null) {
        await _enqueueTodoUpdateSnapshot(row.id, userId: userId);
      }
    }
  }

  Future<void> _enqueueTodoUpdateSnapshot(
    String todoId, {
    required String userId,
  }) async {
    final row = await _db.todosDao.getTodoById(todoId);
    if (row == null) return;
    final tagIds = row.parentId == null
        ? (await _db.todosDao.getTagsForTodo(
            todoId,
          )).map((tag) => tag.id).toList()
        : const <String>[];
    await _db.syncDao.enqueueSyncOp(
      userId: userId,
      entityType: 'todo',
      entityId: todoId,
      operation: 'update',
      payload: SyncPayload.encode(SyncPayload.fromTodo(row, tagIds)),
    );
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
        await _adoptServerRecurringOccurrence(serverVersion);
        await _db.todosDao.upsertTodo(_todoCompanionFromJson(serverVersion));
        await _enforceServerFrogTruth(serverVersion, ownerId: _currentUserId());
        final tagIds =
            (serverVersion['tag_ids'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[];
        await _db.todosDao.setTodoTags(localEntityId, tagIds);
        break;

      case 'note':
        await _db.notesDao.upsertNote(_noteCompanionFromJson(serverVersion));
        await _reconcileNoteRelations(
          localEntityId,
          serverVersion,
          replaceOnlyWhenPresent: true,
        );
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
        final resolvedId = serverId ?? localEntityId;
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
        await _softDeleteDuplicateHabitLogsForPersistedLog(resolvedId);
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

      case 'checklist_template_order':
        await _db.checklistsDao.upsertTemplateOrder(
          _templateOrderCompanionFromJson(serverVersion),
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
          await _runItemCompanionFromJsonPreservingSnapshot(serverVersion),
        );
        break;
    }
  }

  Future<void> _softDeleteDuplicateHabitLogsForPersistedLog(String id) async {
    final row = await _db.habitsDao.getHabitLogById(id);
    if (row == null) return;
    await _db.habitsDao.softDeleteDuplicateHabitLogs(
      row.habitId,
      row.logDate,
      keepId: row.id,
      deletedAtIso: DateTime.now().toUtc().toIso8601String(),
    );
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
    String userId,
  ) async {
    final rows = await _db.syncDao.getRowsForUser(userId: userId);
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
    if (e.requestId != null) 'request_id': e.requestId,
    if (e.rawResponse != null) 'raw_response': e.rawResponse,
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

  Future<void> pullChanges({String? userId}) async {
    final ownerId = userId ?? _requireCurrentUserId();
    final since = await _db.syncDao.getLastSyncedAt(userId: ownerId);

    Map<String, dynamic> response;
    try {
      final resp = await _client.get(
        '/sync/changes',
        queryParameters: since != null ? {'since': since} : null,
      );
      if (resp is! Map) {
        throw ApiException(
          0,
          'response_parse_error',
          'sync changes response must be a JSON object',
          rawResponse: resp,
        );
      }
      response = Map<String, dynamic>.from(resp);
    } on ApiException catch (e) {
      _logSyncFailure(
        method: 'GET',
        url: '/sync/changes',
        status: e.statusCode,
        responseBody: _apiErrorBody(e),
      );
      rethrow;
    }

    late final String serverTime;
    late final Map<String, List<dynamic>> changes;
    late final List<dynamic> sortedTodoChanges;
    try {
      final rawServerTime = response['server_time'];
      if (rawServerTime is! String || rawServerTime.isEmpty) {
        throw StateError('sync changes response missing server_time');
      }
      parseSyncTimestamp(rawServerTime, field: 'server_time');
      final rawChanges = response['changes'];
      if (rawChanges is! Map) {
        throw StateError('sync changes response missing changes map');
      }
      serverTime = rawServerTime;
      changes = validateSyncChanges(Map<String, dynamic>.from(rawChanges));
      sortedTodoChanges = sortTodoChangesTopologically(changes['todos']!);
    } catch (error) {
      throw ApiException(
        0,
        'response_parse_error',
        'Invalid sync changes response: $error',
        rawResponse: response,
      );
    }

    try {
      await _db.transaction(() async {
        // Track tombstone IDs per entity type for self-heal
        final Map<String, List<String>> tombstoneIds = {};

        // Helper: record tombstone
        void recordTombstone(String entityType, String id) {
          tombstoneIds.putIfAbsent(entityType, () => []).add(id);
        }

        // ── Process each entity type ──────────────────────────────────

        await _processEntityList<Map<String, dynamic>>(
          changes['users']!,
          entityType: 'user',
          userId: ownerId,
          tombstoneRecord: recordTombstone,
          applyDeleted: (map) async => _upsertUserFromJson(map),
          applyUpsert: (map) async {
            final id = map['id'] as String;
            if (await _shouldSkipLww(
              'user',
              id,
              map['updated_at'] as String,
              ownerId,
            )) {
              return;
            }
            await _upsertUserFromJson(map);
            await _db.syncDao.removeOpsForEntity('user', id, userId: ownerId);
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['tags']!,
          entityType: 'tag',
          userId: ownerId,
          tombstoneRecord: recordTombstone,
          applyDeleted: (map) async => _db.todosDao.softDeleteTag(
            map['id'] as String,
            map['deleted_at'] as String,
          ),
          applyUpsert: (map) async {
            if (await _shouldSkipLww(
              'tag',
              map['id'] as String,
              map['updated_at'] as String,
              ownerId,
            )) {
              return;
            }
            await _db.todosDao.upsertTag(_tagCompanionFromJson(map));
            await _db.syncDao.removeOpsForEntity(
              'tag',
              map['id'] as String,
              userId: ownerId,
            );
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          sortedTodoChanges,
          entityType: 'todo',
          userId: ownerId,
          tombstoneRecord: recordTombstone,
          applyDeleted: (map) async {
            final deletedIds = await _db.todosDao.softDeleteTodoTree(
              map['id'] as String,
              ownerId,
              map['deleted_at'] as String,
            );
            for (final id in deletedIds) {
              await _db.syncDao.removeOpsForEntity('todo', id, userId: ownerId);
            }
          },
          applyUpsert: (map) async {
            final id = map['id'] as String;
            if (await _shouldSkipLww(
              'todo',
              id,
              map['updated_at'] as String,
              ownerId,
            )) {
              return;
            }
            await _adoptServerRecurringOccurrence(map);
            await _db.todosDao.upsertTodo(_todoCompanionFromJson(map));
            await _enforceServerFrogTruth(map, ownerId: ownerId);
            final tagIds =
                (map['tag_ids'] as List?)?.map((e) => e as String).toList() ??
                const <String>[];
            await _db.todosDao.setTodoTags(id, tagIds);
            await _db.syncDao.removeOpsForEntity('todo', id, userId: ownerId);
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['notes']!,
          entityType: 'note',
          userId: ownerId,
          tombstoneRecord: recordTombstone,
          applyDeleted: (map) async => await _db.notesDao.softDeleteNote(
            map['id'] as String,
            map['deleted_at'] as String,
          ),
          applyUpsert: (map) async {
            final id = map['id'] as String;
            if (await _shouldSkipLww(
              'note',
              id,
              map['updated_at'] as String,
              ownerId,
            )) {
              return;
            }
            await _db.notesDao.upsertNote(_noteCompanionFromJson(map));
            await _reconcileNoteRelations(
              id,
              map,
              replaceOnlyWhenPresent: true,
            );
            await _db.syncDao.removeOpsForEntity('note', id, userId: ownerId);
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['habits']!,
          entityType: 'habit',
          userId: ownerId,
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
            if (await _shouldSkipLww('habit', id, serverUpdatedAt, ownerId)) {
              return;
            }
            await _db.habitsDao.upsertHabit(_habitCompanionFromJson(map));
            await _db.syncDao.removeOpsForEntity('habit', id, userId: ownerId);
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['habit_logs']!,
          entityType: 'habit_log',
          userId: ownerId,
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
              ownerId,
            )) {
              return;
            }
            await _db.habitsDao.upsertHabitLog(_habitLogCompanionFromJson(map));
            await _softDeleteDuplicateHabitLogsForPersistedLog(id);
            await _db.syncDao.removeOpsForEntity(
              'habit_log',
              id,
              userId: ownerId,
            );
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['checklist_categories']!,
          entityType: 'checklist_category',
          userId: ownerId,
          tombstoneRecord: recordTombstone,
          applyDeleted: (map) async =>
              await _db.checklistsDao.softDeleteCategory(
                map['id'] as String,
                map['deleted_at'] as String,
              ),
          applyUpsert: (map) async {
            final id = map['id'] as String;
            if (await _shouldSkipLww(
              'checklist_category',
              id,
              map['updated_at'] as String,
              ownerId,
            )) {
              return;
            }
            await _db.checklistsDao.upsertCategory(
              _checklistCategoryCompanionFromJson(map),
            );
            await _db.syncDao.removeOpsForEntity(
              'checklist_category',
              id,
              userId: ownerId,
            );
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['checklist_templates']!,
          entityType: 'checklist_template',
          userId: ownerId,
          tombstoneRecord: recordTombstone,
          applyDeleted: (map) async =>
              await _db.checklistsDao.softDeleteTemplate(
                map['id'] as String,
                map['deleted_at'] as String,
              ),
          applyUpsert: (map) async {
            final id = map['id'] as String;
            if (await _shouldSkipLww(
              'checklist_template',
              id,
              map['updated_at'] as String,
              ownerId,
            )) {
              return;
            }
            await _db.checklistsDao.upsertTemplate(
              _templateCompanionFromJson(map),
            );
            await _db.syncDao.removeOpsForEntity(
              'checklist_template',
              id,
              userId: ownerId,
            );
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['checklist_template_orders']!,
          entityType: 'checklist_template_order',
          userId: ownerId,
          tombstoneRecord: recordTombstone,
          applyDeleted: (map) async =>
              await _db.checklistsDao.softDeleteTemplateOrder(
                map['id'] as String,
                map['deleted_at'] as String,
              ),
          applyUpsert: (map) async {
            final id = map['id'] as String;
            if (await _shouldSkipLww(
              'checklist_template_order',
              id,
              map['updated_at'] as String,
              ownerId,
            )) {
              return;
            }
            await _db.checklistsDao.upsertTemplateOrder(
              _templateOrderCompanionFromJson(map),
            );
            await _db.syncDao.removeOpsForEntity(
              'checklist_template_order',
              id,
              userId: ownerId,
            );
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['checklist_template_items']!,
          entityType: 'checklist_template_item',
          userId: ownerId,
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
              ownerId,
            )) {
              return;
            }
            await _db.checklistsDao.upsertTemplateItem(
              _templateItemCompanionFromJson(map),
            );
            await _db.syncDao.removeOpsForEntity(
              'checklist_template_item',
              id,
              userId: ownerId,
            );
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['checklist_runs']!,
          entityType: 'checklist_run',
          userId: ownerId,
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
              ownerId,
            )) {
              return;
            }
            await _db.checklistsDao.upsertRun(_runCompanionFromJson(map));
            await _db.syncDao.removeOpsForEntity(
              'checklist_run',
              id,
              userId: ownerId,
            );
          },
        );

        await _processEntityList<Map<String, dynamic>>(
          changes['checklist_run_items']!,
          entityType: 'checklist_run_item',
          userId: ownerId,
          tombstoneRecord: recordTombstone,
          applyDeleted: (map) async =>
              await _db.checklistsDao.softDeleteRunItem(
                map['id'] as String,
                map['deleted_at'] as String,
              ),
          applyUpsert: (map) async {
            final id = map['id'] as String;
            if (await _shouldSkipLww(
              'checklist_run_item',
              id,
              map['updated_at'] as String,
              ownerId,
            )) {
              return;
            }
            await _db.checklistsDao.upsertRunItem(
              await _runItemCompanionFromJsonPreservingSnapshot(map),
            );
            await _db.syncDao.removeOpsForEntity(
              'checklist_run_item',
              id,
              userId: ownerId,
            );
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

        await _db.syncDao.setLastSyncedAt(serverTime, userId: ownerId);
      });
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(
        0,
        'sync_model_parse_error',
        'Failed to decode or persist sync payload: $error',
        rawResponse: error.toString(),
      );
    }

    if (_postPullHook != null) await _postPullHook!();
    TodoLocalEvents.instance.notifyChanged();
    DashboardLocalEvents.instance.notifyChanged();
    NoteLocalEvents.instance.notifyChanged();
  }

  Future<void> _reconcileNoteRelations(
    String noteId,
    Map<String, dynamic> map, {
    required bool replaceOnlyWhenPresent,
  }) async {
    if (!replaceOnlyWhenPresent || map.containsKey('tag_ids')) {
      final tagIds =
          (map['tag_ids'] as List?)?.whereType<String>().toList() ?? const [];
      await _db.notesDao.setNoteTags(noteId, tagIds);
    }

    if (!replaceOnlyWhenPresent || map.containsKey('note_links')) {
      final noteLinks = (map['note_links'] as List?) ?? const [];
      await (_db.delete(
        _db.noteLinksTable,
      )..where((link) => link.sourceNoteId.equals(noteId))).go();
      for (final rawLink in noteLinks) {
        if (rawLink is! Map) continue;
        final link = Map<String, dynamic>.from(rawLink);
        final targetNoteId = link['target_note_id'] as String?;
        if (targetNoteId == null || targetNoteId == noteId) continue;
        final now = DateTime.now().toUtc().toIso8601String();
        await _db.notesDao.upsertNoteLink(
          NoteLinksTableCompanion(
            id: Value(link['id'] as String? ?? '$noteId->$targetNoteId'),
            sourceNoteId: Value(noteId),
            targetNoteId: Value(targetNoteId),
            label: Value(link['label'] as String?),
            createdAt: Value(link['created_at'] as String? ?? now),
            updatedAt: Value(link['updated_at'] as String? ?? now),
            deletedAt: const Value(null),
          ),
        );
      }
    }

    if (!replaceOnlyWhenPresent || map.containsKey('linked_todo_ids')) {
      final linkedTodoIds =
          (map['linked_todo_ids'] as List?)?.whereType<String>().toSet() ??
          const <String>{};
      final existing = await _db.notesDao.getTodoLinksForNote(noteId);
      for (final link in existing) {
        if (!linkedTodoIds.contains(link.todoId)) {
          await _db.notesDao.removeNoteTodoLink(noteId, link.todoId);
        }
      }
      final existingIds = existing.map((link) => link.todoId).toSet();
      for (final todoId in linkedTodoIds) {
        if (existingIds.contains(todoId)) continue;
        await _db.notesDao.upsertNoteTodoLink(
          NoteTodoLinksTableCompanion.insert(
            noteId: noteId,
            todoId: todoId,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
      }
    }
  }

  // ─── LWW (Last-Write-Wins) check ─────────────────────────────────

  /// Returns true if the local version is newer-or-equal AND has pending ops,
  /// meaning we should NOT overwrite it with server data.
  Future<bool> _shouldSkipLww(
    String entityType,
    String entityId,
    String serverUpdatedAt,
    String userId,
  ) async {
    // Check if there's a pending sync op for this entity
    final pending = await _db.syncDao.getPendingForEntity(
      entityType,
      entityId,
      userId: userId,
    );
    if (pending == null) return false;

    // Fetch local updatedAt
    final localUpdatedAt = await _getLocalUpdatedAt(entityType, entityId);
    if (localUpdatedAt == null) return false;

    // If local >= server, keep local
    final local = parseSyncTimestamp(
      localUpdatedAt,
      field: '$entityType#$entityId.local.updated_at',
    );
    final server = parseSyncTimestamp(
      serverUpdatedAt,
      field: '$entityType#$entityId.server.updated_at',
    );
    return !local.isBefore(server);
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
      case 'checklist_template_order':
        return (await _db.checklistsDao.getTemplateOrderById(
          entityId,
        ))?.updatedAt;
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
    required String userId,
    required void Function(String, String) tombstoneRecord,
    required Future<void> Function(Map<String, dynamic>) applyDeleted,
    required Future<void> Function(Map<String, dynamic>) applyUpsert,
  }) async {
    var failures = 0;
    for (final item in list) {
      Map<String, dynamic>? map;
      String id = '?';
      try {
        map = Map<String, dynamic>.from(item as Map<String, dynamic>);
        _scopeServerRecordToUser(map, entityType: entityType, userId: userId);
        id = map['id'] as String? ?? '?';
        if (map['deleted_at'] != null) {
          tombstoneRecord(entityType, id);
          await _db.syncDao.removeOpsForEntity(entityType, id, userId: userId);
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

  void _scopeServerRecordToUser(
    Map<String, dynamic> map, {
    required String entityType,
    required String userId,
  }) {
    if (entityType == 'user' ||
        entityType == 'checklist_template_item' ||
        entityType == 'checklist_run_item') {
      return;
    }
    if (entityType == 'checklist_template' && _parseBool(map['is_system'])) {
      map['user_id'] = null;
      return;
    }
    map['user_id'] = userId;
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
    final scheduledDate = isSubtask ? null : j['scheduled_date'] as String?;
    final isFrog =
        !isSubtask && scheduledDate != null && _parseBool(j['is_frog']);
    final frogDate = isFrog
        ? (j['frog_date'] as String? ?? scheduledDate)
        : null;
    return TodosTableCompanion(
      id: Value(_req(j, 'id')),
      userId: Value(j['user_id'] as String? ?? ''),
      parentId: Value(j['parent_id'] as String?),
      title: Value(_req(j, 'title')),
      description: Value(j['description'] as String?),
      status: Value(j['status'] as String? ?? 'open'),
      position: Value((j['position'] as num?)?.toInt() ?? 0),
      isFrog: Value(isFrog),
      frogDate: Value(frogDate),
      isImportant: Value(isFrog ? true : _parseBoolNullable(j['is_important'])),
      isUrgent: Value(isFrog ? true : _parseBoolNullable(j['is_urgent'])),
      estimatedMinutes: Value((j['estimated_minutes'] as num?)?.toInt()),
      actualMinutes: Value((j['actual_minutes'] as num?)?.toInt()),
      startAt: Value(j['start_at'] as String?),
      dueAt: Value(j['due_at'] as String?),
      scheduledDate: Value(scheduledDate),
      time: Value(
        isSubtask || scheduledDate == null ? null : j['time'] as String?,
      ),
      triggerAfterTodoId: Value(j['trigger_after_todo_id'] as String?),
      habitId: Value(j['habit_id'] as String?),
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
        contentFormat: Value(
          j['content_format'] == 'quill_delta_v1' ? 'quill_delta_v1' : 'plain',
        ),
        bodyDelta: Value(_jsonObjectToStorage(j['body_delta'])),
        cornellCueDelta: Value(_jsonObjectToStorage(j['cornell_cue_delta'])),
        cornellSummaryDelta: Value(
          _jsonObjectToStorage(j['cornell_summary_delta']),
        ),
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
    sortOrder: Value((j['sort_order'] as num?)?.toInt() ?? 0),
    timesUsed: Value((j['times_used'] as num?)?.toInt() ?? 0),
    lastUsedAt: Value(j['last_used_at'] as String?),
    createdAt: Value(_req(j, 'created_at')),
    updatedAt: Value(_req(j, 'updated_at')),
    deletedAt: Value(j['deleted_at'] as String?),
  );

  static ChecklistTemplateOrdersTableCompanion _templateOrderCompanionFromJson(
    Map<String, dynamic> j,
  ) => ChecklistTemplateOrdersTableCompanion(
    id: Value(_req(j, 'id')),
    userId: Value(j['user_id'] as String? ?? ''),
    templateId: Value(_req(j, 'template_id')),
    sortOrder: Value((j['sort_order'] as num?)?.toInt() ?? 0),
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
    durationMs: Value((j['duration_ms'] as num?)?.toInt()),
    // server sends 'started_at'; stored locally in the createdAt column
    createdAt: Value(
      j['started_at'] as String? ??
          j['created_at'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
    ),
    updatedAt: Value(_req(j, 'updated_at')),
    deletedAt: Value(j['deleted_at'] as String?),
  );

  Future<ChecklistRunItemsTableCompanion>
  _runItemCompanionFromJsonPreservingSnapshot(Map<String, dynamic> j) async {
    final id = _req(j, 'id');
    final templateItemId = j['template_item_id'] as String?;
    final existing = await _db.checklistsDao.getRunItemById(id);
    final templateItem = templateItemId == null
        ? null
        : await _db.checklistsDao.getTemplateItemById(templateItemId);
    final rawTitle = j['title'] as String?;
    final rawPosition =
        (j['position'] as num?)?.toInt() ?? (j['order_index'] as num?)?.toInt();

    return ChecklistRunItemsTableCompanion(
      id: Value(id),
      runId: Value(_req(j, 'run_id')),
      templateItemId: Value(templateItemId),
      title: Value(
        rawTitle == null || rawTitle.isEmpty
            ? existing?.title.isNotEmpty == true
                  ? existing!.title
                  : templateItem?.title ?? ''
            : rawTitle,
      ),
      isRequired: Value(
        j.containsKey('is_required') && j['is_required'] != null
            ? _parseBool(j['is_required'])
            : existing?.isRequired ?? templateItem?.isRequired ?? true,
      ),
      status: Value(j['status'] as String? ?? 'pending'),
      completedAt: Value(j['completed_at'] as String?),
      note: Value(j['note'] as String?),
      orderIndex: Value(
        rawPosition ?? existing?.orderIndex ?? templateItem?.orderIndex ?? 0,
      ),
      createdAt: Value(_req(j, 'created_at')),
      updatedAt: Value(_req(j, 'updated_at')),
      deletedAt: Value(j['deleted_at'] as String?),
    );
  }

  static String? _settingsToString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return jsonEncode(value);
  }

  static String? _jsonObjectToStorage(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final sanitized = sanitizeNoteDelta(value);
      return sanitized == null ? null : jsonEncode(sanitized);
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        final sanitized = decoded is Map ? sanitizeNoteDelta(decoded) : null;
        return sanitized == null ? null : jsonEncode(sanitized);
      } catch (_) {
        return null;
      }
    }
    return null;
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

const syncChangeKeys = <String>[
  'users',
  'tags',
  'todos',
  'notes',
  'habits',
  'habit_logs',
  'checklist_categories',
  'checklist_templates',
  'checklist_template_orders',
  'checklist_template_items',
  'checklist_runs',
  'checklist_run_items',
];

@visibleForTesting
Map<String, List<dynamic>> validateSyncChanges(Map<String, dynamic> changes) {
  final validated = <String, List<dynamic>>{};
  for (final key in syncChangeKeys) {
    if (!changes.containsKey(key)) {
      throw StateError('sync changes missing required list "$key"');
    }
    final value = changes[key];
    if (value is! List) {
      throw StateError('sync changes "$key" must be a List');
    }
    validated[key] = value;
  }
  return validated;
}

@visibleForTesting
List<dynamic> sortTodoChangesTopologically(List<dynamic> items) {
  final maps = items.map((item) {
    if (item is! Map<String, dynamic>) {
      throw StateError('todos sync item must be an object');
    }
    return item;
  }).toList();
  final byId = <String, Map<String, dynamic>>{};
  for (final map in maps) {
    final id = map['id'];
    if (id is! String || id.isEmpty) {
      throw StateError('todos sync item is missing id');
    }
    byId[id] = map;
  }

  final depthCache = <String, int>{};
  int depthFor(String id, Set<String> visiting) {
    final cached = depthCache[id];
    if (cached != null) return cached;
    if (!visiting.add(id)) {
      throw StateError('todos sync contains a parent cycle at $id');
    }
    final parentId = byId[id]?['parent_id'] as String?;
    final depth = parentId == null || !byId.containsKey(parentId)
        ? 0
        : depthFor(parentId, visiting) + 1;
    visiting.remove(id);
    depthCache[id] = depth;
    return depth;
  }

  maps.sort((a, b) {
    final aId = a['id'] as String;
    final bId = b['id'] as String;
    final depthOrder = depthFor(
      aId,
      <String>{},
    ).compareTo(depthFor(bId, <String>{}));
    if (depthOrder != 0) return depthOrder;
    final positionOrder = ((a['position'] as num?)?.toInt() ?? 0).compareTo(
      (b['position'] as num?)?.toInt() ?? 0,
    );
    if (positionOrder != 0) return positionOrder;
    return aId.compareTo(bId);
  });
  return maps;
}

DateTime parseSyncTimestamp(String value, {required String field}) {
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw StateError('invalid sync timestamp for $field: "$value"');
  }
}

@visibleForTesting
bool shouldDropGeneratedRecurrenceOperation({
  required String operation,
  required Map<String, dynamic> payload,
  required bool isLocalProjection,
}) {
  if (operation == 'create') {
    return payload['recurrence_template_id'] != null &&
        payload['recurrence_type'] == null;
  }
  if (operation != 'delete' || payload['delete_scope'] != null) return false;
  return isLocalProjection;
}
