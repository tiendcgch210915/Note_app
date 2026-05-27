import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/api_exception.dart';
import '../data/local/dao/sync_dao.dart';
import '../data/local/database.dart';
import '../data/local/tables.dart';
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
    // Sorted batch, at most 100 ops per call
    final all = await _db.syncDao.getDueBatch(limit: 100);
    if (all.isEmpty) return;

    final sorted = sortedByDependency<SyncQueueRow>(
      rows: all,
      getEntityType: (r) => r.entityType,
      getId: (r) => r.id,
    );

    // Drop any queued ops for system templates — server rejects them
    final eligibleRows = <SyncQueueRow>[];
    for (final row in sorted) {
      if (row.entityType == 'checklist_template') {
        final t = await _db.checklistsDao.getTemplateById(row.entityId);
        if (t?.isSystem == true) {
          await _db.syncDao.removeSyncOp(row.id);
          continue;
        }
      }
      eligibleRows.add(row);
    }
    if (eligibleRows.isEmpty) return;

    // Build ops list for the push endpoint
    final ops = eligibleRows.map((row) {
      return {
        'entity_type': row.entityType,
        'entity_id': row.entityId,
        'operation': row.operation,
        'payload': SyncPayload.decode(row.payload),
      };
    }).toList();

    // Debug: log what we're pushing so bad_input can be diagnosed in logcat
    debugPrint('[SyncWorker] Pushing ${ops.length} op(s): '
        '${eligibleRows.map((r) => "${r.entityType}:${r.operation}:${r.entityId}").join(", ")}');

    Map<String, dynamic> response;
    try {
      final resp = await _client.post('/sync/push', data: {'operations': ops});
      response = resp as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') return; // try again later
      // Server rejected our payload (4xx/5xx) — log payload for diagnosis,
      // apply exponential back-off so retries don't hammer the server, then
      // propagate so sync() can surface the error to the UI.
      debugPrint('[SyncWorker] Push rejected ${e.code}: ${e.message}');
      debugPrint('[SyncWorker] Rejected payload: ${jsonEncode({'operations': ops})}');
      for (final row in eligibleRows) {
        await _db.syncDao.incrementRetry(row.id, row.retryCount);
      }
      rethrow; // sync() catches this and shows error state in UI
    }

    final results = (response['results'] as List?) ?? const [];

    // Map entityId → queue row for fast lookup
    final rowByEntityId = {for (final r in eligibleRows) r.entityId: r};

    for (final result in results) {
      final map = result as Map<String, dynamic>;
      final entityId = map['entity_id'] as String;
      final status = map['status'] as String; // 'applied' | 'conflict' | 'error'
      final queueRow = rowByEntityId[entityId];
      if (queueRow == null) continue;

      switch (status) {
        case 'applied':
          await _db.syncDao.removeSyncOp(queueRow.id);
          break;

        case 'conflict':
          final serverVersion = map['server_version'] as Map<String, dynamic>?;
          if (serverVersion != null) {
            await _applyServerVersion(
              queueRow.entityType,
              entityId,
              serverVersion,
            );
          }
          await _db.syncDao.removeSyncOp(queueRow.id);
          break;

        case 'error':
          await _db.syncDao.incrementRetry(queueRow.id, queueRow.retryCount);
          break;
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

      case 'tag':
        if (idChanged) {
          // ID-adopt: rewrite todo_tags and note_tags from old id → server id
          await _db.transaction(() async {
            await _db.todosDao.upsertTag(_tagCompanionFromJson(serverVersion));
            await _rewriteTagJunctions(
                oldTagId: localEntityId, newTagId: serverId!);
            // Remove old tag row if different id
            await _db.todosDao.upsertTag(TagsTableCompanion(
              id: Value(localEntityId),
              deletedAt: Value(DateTime.now().toUtc().toIso8601String()),
              updatedAt: Value(DateTime.now().toUtc().toIso8601String()),
              name: const Value('__deleted__'),
              color: const Value('#000000'),
              userId: const Value(''),
              createdAt: Value(DateTime.now().toUtc().toIso8601String()),
            ));
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
            await _db.habitsDao
                .upsertHabitLog(_habitLogCompanionFromJson(serverVersion));
            // Old row becomes tombstone
            await _db.habitsDao.softDeleteHabitLog(
              localEntityId,
              DateTime.now().toUtc().toIso8601String(),
            );
          });
        } else {
          await _db.habitsDao
              .upsertHabitLog(_habitLogCompanionFromJson(serverVersion));
        }
        break;

      case 'checklist_template':
        await _db.checklistsDao
            .upsertTemplate(_templateCompanionFromJson(serverVersion));
        break;

      case 'checklist_template_item':
        await _db.checklistsDao
            .upsertTemplateItem(_templateItemCompanionFromJson(serverVersion));
        break;

      case 'checklist_run':
        await _db.checklistsDao
            .upsertRun(_runCompanionFromJson(serverVersion));
        break;

      case 'checklist_run_item':
        await _db.checklistsDao
            .upsertRunItem(_runItemCompanionFromJson(serverVersion));
        break;
    }
  }

  Future<void> _rewriteTagJunctions(
      {required String oldTagId, required String newTagId}) async {
    // This requires raw SQL; for now we take the safe approach of removing
    // old junctions and re-adding them with new tag id.
    // The actual todo_tags rows referencing oldTagId need to be updated.
    // Since Drift doesn't have UPDATE…WHERE across junction easily, we read
    // the affected todoIds and re-set their tags.
    final affected = await (_db.select(_db.todoTagsTable)
          ..where((j) => j.tagId.equals(oldTagId)))
        .get();
    for (final j in affected) {
      await (_db.delete(_db.todoTagsTable)
            ..where((row) =>
                row.todoId.equals(j.todoId) & row.tagId.equals(oldTagId)))
          .go();
      await _db.into(_db.todoTagsTable).insertOnConflictUpdate(
            TodoTagsTableCompanion.insert(todoId: j.todoId, tagId: newTagId),
          );
    }
    // Same for note_tags
    final affectedNotes = await (_db.select(_db.noteTagsTable)
          ..where((j) => j.tagId.equals(oldTagId)))
        .get();
    for (final j in affectedNotes) {
      await (_db.delete(_db.noteTagsTable)
            ..where((row) =>
                row.noteId.equals(j.noteId) & row.tagId.equals(oldTagId)))
          .go();
      await _db.into(_db.noteTagsTable).insertOnConflictUpdate(
            NoteTagsTableCompanion.insert(noteId: j.noteId, tagId: newTagId),
          );
    }
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
      rethrow;
    }

    final serverTime =
        response['server_time'] as String? ?? DateTime.now().toUtc().toIso8601String();
    final changes = response['changes'] as Map<String, dynamic>? ?? {};

    // Track tombstone IDs per entity type for self-heal
    final Map<String, List<String>> tombstoneIds = {};

    // Helper: record tombstone
    void recordTombstone(String entityType, String id) {
      tombstoneIds.putIfAbsent(entityType, () => []).add(id);
    }

    // ── Process each entity type ──────────────────────────────────

    await _processEntityList<Map<String, dynamic>>(
      changes['tags'] as List? ?? const [],
      entityType: 'tag',
      tombstoneRecord: recordTombstone,
      applyDeleted: (map) async => await _db.todosDao.upsertTag(
        _tagCompanionFromJson(map),
      ),
      applyUpsert: (map) async {
        if (await _shouldSkipLww('tag', map['id'] as String,
            map['updated_at'] as String)) return;
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
        if (await _shouldSkipLww('todo', id, map['updated_at'] as String)) return;
        await _db.todosDao.upsertTodo(_todoCompanionFromJson(map));
        // Reconcile tag_ids junction
        final tagIds = (map['tag_ids'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [];
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
        if (await _shouldSkipLww('note', id, map['updated_at'] as String)) return;
        await _db.notesDao.upsertNote(_noteCompanionFromJson(map));
        // Reconcile tag_ids
        final tagIds = (map['tag_ids'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [];
        await _db.notesDao.setNoteTags(id, tagIds);
        // Reconcile note_links
        final noteLinks = (map['note_links'] as List?) ?? const [];
        for (final link in noteLinks) {
          final lmap = link as Map<String, dynamic>;
          final now = DateTime.now().toUtc().toIso8601String();
          await _db.notesDao.upsertNoteLink(NoteLinksTableCompanion(
            id: Value(lmap['id'] as String? ?? ''),
            sourceNoteId: Value(id),
            targetNoteId: Value(lmap['target_note_id'] as String),
            label: Value(lmap['label'] as String?),
            createdAt: Value(lmap['created_at'] as String? ?? now),
            updatedAt: Value(lmap['updated_at'] as String? ?? now),
            deletedAt: const Value(null),
          ));
        }
        // Reconcile linked_todo_ids
        final linkedTodoIds = (map['linked_todo_ids'] as List?)
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
        // Streak: always adopt from server (server is authoritative)
        final existing = await _db.habitsDao.getHabitById(id);
        if (existing != null &&
            existing.updatedAt != serverUpdatedAt) {
          await _db.habitsDao.adoptStreak(
            id,
            (map['current_streak'] as num?)?.toInt() ?? 0,
            (map['longest_streak'] as num?)?.toInt() ?? 0,
            serverUpdatedAt,
          );
        }
        if (await _shouldSkipLww('habit', id, serverUpdatedAt)) return;
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
        if (await _shouldSkipLww('habit_log', id, map['updated_at'] as String)) return;
        await _db.habitsDao.upsertHabitLog(_habitLogCompanionFromJson(map));
        await _db.syncDao.removeOpsForEntity('habit_log', id);
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
        if (await _shouldSkipLww('checklist_template', id, map['updated_at'] as String)) return;
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
        if (await _shouldSkipLww('checklist_template_item', id, map['updated_at'] as String)) return;
        await _db.checklistsDao
            .upsertTemplateItem(_templateItemCompanionFromJson(map));
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
        if (await _shouldSkipLww('checklist_run', id, map['updated_at'] as String)) return;
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
        if (await _shouldSkipLww('checklist_run_item', id, map['updated_at'] as String)) return;
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
        await (_db.delete(_db.noteTodoLinksTable)
              ..where((l) => l.todoId.isIn(todoTombstones)))
            .go();
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
      String entityType, String entityId, String serverUpdatedAt) async {
    // Check if there's a pending sync op for this entity
    final pending = await (_db.select(_db.syncQueueTable)
          ..where((q) =>
              q.entityType.equals(entityType) &
              q.entityId.equals(entityId))
          ..limit(1))
        .getSingleOrNull();
    if (pending == null) return false;

    // Fetch local updatedAt
    final localUpdatedAt = await _getLocalUpdatedAt(entityType, entityId);
    if (localUpdatedAt == null) return false;

    // If local >= server, keep local
    return localUpdatedAt.compareTo(serverUpdatedAt) >= 0;
  }

  Future<String?> _getLocalUpdatedAt(
      String entityType, String entityId) async {
    switch (entityType) {
      case 'todo':
        return (await _db.todosDao.getTodoById(entityId))?.updatedAt;
      case 'note':
        return (await _db.notesDao.getNoteById(entityId))?.updatedAt;
      case 'habit':
        return (await _db.habitsDao.getHabitById(entityId))?.updatedAt;
      case 'habit_log':
        return (await _db.habitsDao.getHabitLogById(entityId))?.updatedAt;
      case 'checklist_template':
        return (await _db.checklistsDao.getTemplateById(entityId))?.updatedAt;
      case 'checklist_run':
        return (await _db.checklistsDao.getRunById(entityId))?.updatedAt;
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
        // One malformed record must not abort the entire pull.
        // Log clearly so the issue is diagnosable, then continue.
        debugPrint('[SyncWorker] ⚠️  Skip $entityType#$id: $e');
        debugPrint('[SyncWorker]    ${st.toString().split('\n').take(6).join('\n')}');
      }
    }
  }

  // ─── JSON → Drift companion converters ───────────────────────────

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

  static TodosTableCompanion _todoCompanionFromJson(Map<String, dynamic> j) =>
      TodosTableCompanion(
        id: Value(_req(j, 'id')),
        userId: Value(j['user_id'] as String? ?? ''),
        parentId: Value(j['parent_id'] as String?),
        title: Value(_req(j, 'title')),
        description: Value(j['description'] as String?),
        status: Value(j['status'] as String? ?? 'open'),
        position: Value((j['position'] as num?)?.toInt() ?? 0),
        isFrog: Value(_parseBool(j['is_frog'])),
        frogDate: Value(j['frog_date'] as String?),
        isImportant: Value(_parseBoolNullable(j['is_important'])),
        isUrgent: Value(_parseBoolNullable(j['is_urgent'])),
        estimatedMinutes:
            Value((j['estimated_minutes'] as num?)?.toInt()),
        actualMinutes: Value((j['actual_minutes'] as num?)?.toInt()),
        startAt: Value(j['start_at'] as String?),
        dueAt: Value(j['due_at'] as String?),
        scheduledDate: Value(j['scheduled_date'] as String?),
        triggerAfterTodoId: Value(j['trigger_after_todo_id'] as String?),
        completedAt: Value(j['completed_at'] as String?),
        createdAt: Value(_req(j, 'created_at')),
        updatedAt: Value(_req(j, 'updated_at')),
        deletedAt: Value(j['deleted_at'] as String?),
        recurrenceType: Value(j['recurrence_type'] as String?),
        recurrenceInterval:
            Value((j['recurrence_interval'] as num?)?.toInt()),
        recurrenceWeekdays: Value(j['recurrence_days_of_week'] as String?),
        recurrenceEndDate: Value(j['recurrence_end_date'] as String?),
        recurrenceTemplateId: Value(j['recurrence_template_id'] as String?),
      );

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
        targetPerPeriod:
            Value((j['target_per_period'] as num?)?.toInt() ?? 1),
        activeWeekdays: Value(j['active_weekdays'] as String?),
        startDate: Value(_req(j, 'start_date')),
        endDate: Value(j['end_date'] as String?),
        currentStreak:
            Value((j['current_streak'] as num?)?.toInt() ?? 0),
        longestStreak:
            Value((j['longest_streak'] as num?)?.toInt() ?? 0),
        isArchived: Value(_parseBool(j['is_archived'])),
        createdAt: Value(_req(j, 'created_at')),
        updatedAt: Value(_req(j, 'updated_at')),
        deletedAt: Value(j['deleted_at'] as String?),
      );

  static HabitLogsTableCompanion _habitLogCompanionFromJson(
          Map<String, dynamic> j) =>
      HabitLogsTableCompanion(
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

  static ChecklistTemplatesTableCompanion _templateCompanionFromJson(
          Map<String, dynamic> j) =>
      ChecklistTemplatesTableCompanion(
        id: Value(_req(j, 'id')),
        userId: Value(j['user_id'] as String?),
        title: Value(_req(j, 'title')),
        description: Value(j['description'] as String?),
        icon: Value(j['icon'] as String?),
        category: Value(j['category'] as String?),
        isSystem: Value(_parseBool(j['is_system'])),
        timesUsed: Value((j['times_used'] as num?)?.toInt() ?? 0),
        lastUsedAt: Value(j['last_used_at'] as String?),
        createdAt: Value(_req(j, 'created_at')),
        updatedAt: Value(_req(j, 'updated_at')),
        deletedAt: Value(j['deleted_at'] as String?),
      );

  static ChecklistTemplateItemsTableCompanion _templateItemCompanionFromJson(
          Map<String, dynamic> j) =>
      ChecklistTemplateItemsTableCompanion(
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
          Map<String, dynamic> j) =>
      ChecklistRunsTableCompanion(
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
          Map<String, dynamic> j) =>
      ChecklistRunItemsTableCompanion(
        id: Value(_req(j, 'id')),
        runId: Value(_req(j, 'run_id')),
        templateItemId: Value(j['template_item_id'] as String?),
        title: Value(_req(j, 'title')),
        isRequired: Value(_parseBool(j['is_required'])),
        status: Value(j['status'] as String? ?? 'pending'),
        note: Value(j['note'] as String?),
        orderIndex: Value((j['order_index'] as num?)?.toInt() ?? 0),
        createdAt: Value(_req(j, 'created_at')),
        updatedAt: Value(_req(j, 'updated_at')),
        deletedAt: Value(j['deleted_at'] as String?),
      );

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
