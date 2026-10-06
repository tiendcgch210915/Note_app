import 'dart:convert';

import 'package:drift/drift.dart';

import '../../auth_storage.dart';
import '../database.dart';
import '../tables.dart';

part 'sync_dao.g.dart';

const String kLastSyncedAtPrefix = 'last_synced_at:';

@DriftAccessor(tables: [SyncQueueTable, SyncMetaTable])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  static const int maxRetries = 10;

  String _resolveUserId([String? explicitUserId]) {
    final userId =
        explicitUserId ??
        AuthStorage.instance.currentUserJson?['id'] as String? ??
        '';
    if (userId.isEmpty) {
      throw StateError('Authenticated user id is required for sync state');
    }
    return userId;
  }

  Future<void> enqueueSyncOp({
    String? userId,
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  }) async {
    final ownerId = _resolveUserId(userId);
    final existing =
        await (select(syncQueueTable)
              ..where(
                (q) =>
                    q.userId.equals(ownerId) &
                    q.entityType.equals(entityType) &
                    q.entityId.equals(entityId),
              )
              ..orderBy([(q) => OrderingTerm.asc(q.id)])
              ..limit(1))
            .getSingleOrNull();
    final now = DateTime.now().toUtc().toIso8601String();

    if (existing == null) {
      await into(syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          userId: Value(ownerId),
          entityType: entityType,
          entityId: entityId,
          operation: operation,
          payload: payload,
          createdAt: now,
        ),
      );
      return;
    }

    // A row created and deleted before its first push never existed remotely.
    // Drop the outbox operation instead of producing a pointless delete retry.
    if (existing.operation == 'create' && operation == 'delete') {
      await (delete(
        syncQueueTable,
      )..where((row) => row.id.equals(existing.id))).go();
      return;
    }

    final mergedOperation =
        existing.operation == 'create' && operation == 'update'
        ? 'create'
        : operation;
    await (update(
      syncQueueTable,
    )..where((q) => q.id.equals(existing.id))).write(
      SyncQueueTableCompanion(
        operation: Value(mergedOperation),
        payload: Value(payload),
        retryCount: const Value(0),
        nextRetryAt: const Value(null),
        lastError: const Value(null),
        isDeadLetter: const Value(false),
      ),
    );
  }

  Future<List<SyncQueueRow>> getDueBatch({String? userId, int limit = 100}) {
    final ownerId = _resolveUserId(userId);
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    return (select(syncQueueTable)
          ..where(
            (q) =>
                q.userId.equals(ownerId) &
                q.isDeadLetter.equals(false) &
                (q.nextRetryAt.isNull() |
                    q.nextRetryAt.isSmallerOrEqualValue(nowMillis)),
          )
          ..orderBy([(q) => OrderingTerm.asc(q.id)])
          ..limit(limit))
        .get();
  }

  Future<List<SyncQueueRow>> getRowsForUser({String? userId}) {
    final ownerId = _resolveUserId(userId);
    return (select(syncQueueTable)
          ..where((q) => q.userId.equals(ownerId))
          ..orderBy([(q) => OrderingTerm.asc(q.id)]))
        .get();
  }

  Future<SyncQueueRow?> getPendingForEntity(
    String entityType,
    String entityId, {
    String? userId,
  }) {
    final ownerId = _resolveUserId(userId);
    return (select(syncQueueTable)
          ..where(
            (q) =>
                q.userId.equals(ownerId) &
                q.entityType.equals(entityType) &
                q.entityId.equals(entityId) &
                q.isDeadLetter.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> removeSyncOp(int queueId, {String? userId}) async {
    final ownerId = _resolveUserId(userId);
    await (delete(
      syncQueueTable,
    )..where((q) => q.id.equals(queueId) & q.userId.equals(ownerId))).go();
  }

  Future<void> removeOpsForEntity(
    String entityType,
    String entityId, {
    String? userId,
  }) async {
    final ownerId = _resolveUserId(userId);
    await (delete(syncQueueTable)..where(
          (q) =>
              q.userId.equals(ownerId) &
              q.entityType.equals(entityType) &
              q.entityId.equals(entityId),
        ))
        .go();
  }

  Future<void> patchPendingTodoRecurrenceEndDate(
    List<String> todoIds, {
    String? userId,
    required String recurrenceEndDate,
    required String updatedAt,
  }) async {
    if (todoIds.isEmpty) return;
    final ownerId = _resolveUserId(userId);
    final rows =
        await (select(syncQueueTable)..where(
              (q) =>
                  q.userId.equals(ownerId) &
                  q.entityType.equals('todo') &
                  q.entityId.isIn(todoIds) &
                  q.operation.isIn(const ['create', 'update']) &
                  q.isDeadLetter.equals(false),
            ))
            .get();
    for (final row in rows) {
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      payload['recurrence_end_date'] = recurrenceEndDate;
      payload['updated_at'] = updatedAt;
      await (update(syncQueueTable)..where((q) => q.id.equals(row.id))).write(
        SyncQueueTableCompanion(payload: Value(jsonEncode(payload))),
      );
    }
  }

  Future<void> remapEntityId({
    String? userId,
    required String entityType,
    required String oldEntityId,
    required String newEntityId,
  }) async {
    final ownerId = _resolveUserId(userId);
    await (update(syncQueueTable)..where(
          (q) =>
              q.userId.equals(ownerId) &
              q.entityType.equals(entityType) &
              q.entityId.equals(oldEntityId),
        ))
        .write(SyncQueueTableCompanion(entityId: Value(newEntityId)));
  }

  Future<void> markFailedRetryable(
    int queueId,
    int currentRetryCount, {
    String? userId,
    required String error,
  }) async {
    final ownerId = _resolveUserId(userId);
    final nextRetryCount = currentRetryCount + 1;
    if (nextRetryCount >= maxRetries) {
      await markPermanentFailure(
        queueId,
        userId: ownerId,
        error: 'retry_limit:$error',
      );
      return;
    }
    final nextRetryMillis = DateTime.now()
        .add(Duration(seconds: _backoffSeconds(currentRetryCount)))
        .millisecondsSinceEpoch;
    await (update(
      syncQueueTable,
    )..where((q) => q.id.equals(queueId) & q.userId.equals(ownerId))).write(
      SyncQueueTableCompanion(
        retryCount: Value(nextRetryCount),
        nextRetryAt: Value(nextRetryMillis),
        lastError: Value(error),
      ),
    );
  }

  Future<void> markPermanentFailure(
    int queueId, {
    String? userId,
    required String error,
  }) async {
    final ownerId = _resolveUserId(userId);
    await (update(
      syncQueueTable,
    )..where((q) => q.id.equals(queueId) & q.userId.equals(ownerId))).write(
      SyncQueueTableCompanion(
        isDeadLetter: const Value(true),
        nextRetryAt: const Value(null),
        lastError: Value(error),
      ),
    );
  }

  static int _backoffSeconds(int retryCount) {
    final raw = 1 << retryCount.clamp(0, 20);
    return raw.clamp(1, 300);
  }

  Future<int> getPendingCount({String? userId}) async {
    final ownerId = _resolveUserId(userId);
    final count = countAll();
    final query = selectOnly(syncQueueTable)
      ..addColumns([count])
      ..where(
        syncQueueTable.userId.equals(ownerId) &
            syncQueueTable.isDeadLetter.equals(false),
      );
    return (await query.map((row) => row.read(count) ?? 0).getSingle());
  }

  Future<int> getDeadLetterCount({String? userId}) async {
    final ownerId = _resolveUserId(userId);
    final count = countAll();
    final query = selectOnly(syncQueueTable)
      ..addColumns([count])
      ..where(
        syncQueueTable.userId.equals(ownerId) &
            syncQueueTable.isDeadLetter.equals(true),
      );
    return (await query.map((row) => row.read(count) ?? 0).getSingle());
  }

  String _cursorKey(String userId) => '$kLastSyncedAtPrefix$userId';

  Future<String?> getLastSyncedAt({String? userId}) async {
    final ownerId = _resolveUserId(userId);
    final row = await (select(
      syncMetaTable,
    )..where((m) => m.key.equals(_cursorKey(ownerId)))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setLastSyncedAt(String isoTimestamp, {String? userId}) async {
    final ownerId = _resolveUserId(userId);
    await into(syncMetaTable).insertOnConflictUpdate(
      SyncMetaTableCompanion.insert(
        key: _cursorKey(ownerId),
        value: isoTimestamp,
      ),
    );
  }

  Future<String?> getSyncMeta(String key) async {
    final row = await (select(
      syncMetaTable,
    )..where((m) => m.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSyncMeta(String key, String value) async {
    await into(syncMetaTable).insertOnConflictUpdate(
      SyncMetaTableCompanion.insert(key: key, value: value),
    );
  }
}
