import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database.dart';
import '../tables.dart';

part 'sync_dao.g.dart';

/// Key used in SyncMetaTable for the last-synced timestamp.
const String kLastSyncedAt = 'last_synced_at';

@DriftAccessor(tables: [SyncQueueTable, SyncMetaTable])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  // ─── Sync queue ───────────────────────────────────────────────────

  /// Enqueue a sync operation, coalescing with any existing op for the same
  /// entity. Rules:
  ///  - If existing op is 'create' and new op is 'update' → keep 'create',
  ///    replace payload with merged data (server needs full row on create).
  ///  - If existing op is 'create'/'update' and new op is 'delete' → replace op with 'delete'.
  ///  - If no existing op → insert new row.
  Future<void> enqueueSyncOp({
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  }) async {
    final existing =
        await (select(db.syncQueueTable)
              ..where(
                (q) =>
                    q.entityType.equals(entityType) &
                    q.entityId.equals(entityId),
              )
              ..orderBy([(q) => OrderingTerm.asc(q.id)])
              ..limit(1))
            .getSingleOrNull();

    final now = DateTime.now().toUtc().toIso8601String();

    if (existing == null) {
      await into(db.syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          entityType: entityType,
          entityId: entityId,
          operation: operation,
          payload: payload,
          createdAt: now,
        ),
      );
    } else {
      // Coalesce: determine merged operation
      final String mergedOp;
      if (existing.operation == 'create' && operation == 'update') {
        mergedOp = 'create'; // keep create, update payload
      } else if (operation == 'delete') {
        mergedOp = 'delete'; // delete wins
      } else {
        mergedOp = operation; // update overwrites update
      }
      await (update(
        db.syncQueueTable,
      )..where((q) => q.id.equals(existing.id))).write(
        SyncQueueTableCompanion(
          operation: Value(mergedOp),
          payload: Value(payload),
          retryCount: const Value(0),
          nextRetryAt: const Value(null),
        ),
      );
    }
  }

  /// Returns a batch of ready-to-send operations (nextRetryAt is null or past).
  Future<List<SyncQueueRow>> getDueBatch({int limit = 100}) {
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    return (select(db.syncQueueTable)
          ..where(
            (q) =>
                q.nextRetryAt.isNull() |
                q.nextRetryAt.isSmallerOrEqualValue(nowMillis),
          )
          ..orderBy([(q) => OrderingTerm.asc(q.id)])
          ..limit(limit))
        .get();
  }

  Future<void> removeSyncOp(int queueId) async {
    await (delete(db.syncQueueTable)..where((q) => q.id.equals(queueId))).go();
  }

  Future<void> removeOpsForEntity(String entityType, String entityId) async {
    await (delete(db.syncQueueTable)..where(
          (q) => q.entityType.equals(entityType) & q.entityId.equals(entityId),
        ))
        .go();
  }

  Future<void> remapEntityId({
    required String entityType,
    required String oldEntityId,
    required String newEntityId,
  }) async {
    await (update(db.syncQueueTable)..where(
          (q) =>
              q.entityType.equals(entityType) & q.entityId.equals(oldEntityId),
        ))
        .write(SyncQueueTableCompanion(entityId: Value(newEntityId)));
  }

  /// Maximum attempts before an op is dropped automatically.
  static const int _maxRetries = 10;

  /// Increment retry count and set next retry time with exponential backoff.
  /// After [_maxRetries] failures the op is removed — prevents stale ops from
  /// blocking the queue indefinitely (e.g. entity already exists on server).
  /// backoff = min(2^retryCount seconds, 300 seconds)
  Future<void> incrementRetry(int queueId, int currentRetryCount) async {
    if (currentRetryCount >= _maxRetries) {
      debugPrint('[SyncDao] Op $queueId exceeded max retries — dropping');
      await removeSyncOp(queueId);
      return;
    }
    final backoffSecs = _backoffSeconds(currentRetryCount);
    final nextRetryMillis = DateTime.now()
        .add(Duration(seconds: backoffSecs))
        .millisecondsSinceEpoch;
    await (update(db.syncQueueTable)..where((q) => q.id.equals(queueId))).write(
      SyncQueueTableCompanion(
        retryCount: Value(currentRetryCount + 1),
        nextRetryAt: Value(nextRetryMillis),
      ),
    );
  }

  Future<void> markFailedRetryable(int queueId, int currentRetryCount) async {
    final backoffSecs = _backoffSeconds(currentRetryCount);
    final nextRetryMillis = DateTime.now()
        .add(Duration(seconds: backoffSecs))
        .millisecondsSinceEpoch;
    await (update(db.syncQueueTable)..where((q) => q.id.equals(queueId))).write(
      SyncQueueTableCompanion(
        retryCount: Value(currentRetryCount + 1),
        nextRetryAt: Value(nextRetryMillis),
      ),
    );
  }

  static int _backoffSeconds(int retryCount) {
    final raw = 1 << retryCount; // 1, 2, 4, 8, 16, 32 ...
    return raw.clamp(1, 300);
  }

  Future<int> getPendingCount() async {
    final rows = await select(db.syncQueueTable).get();
    return rows.length;
  }

  // ─── Sync metadata ────────────────────────────────────────────────

  Future<String?> getLastSyncedAt() async {
    final row = await (select(
      db.syncMetaTable,
    )..where((m) => m.key.equals(kLastSyncedAt))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setLastSyncedAt(String isoTimestamp) async {
    await into(db.syncMetaTable).insertOnConflictUpdate(
      SyncMetaTableCompanion.insert(key: kLastSyncedAt, value: isoTimestamp),
    );
  }

  // ─── Generic key-value meta ────────────────────────────────────────

  Future<String?> getSyncMeta(String key) async {
    final row = await (select(
      db.syncMetaTable,
    )..where((m) => m.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSyncMeta(String key, String value) async {
    await into(db.syncMetaTable).insertOnConflictUpdate(
      SyncMetaTableCompanion.insert(key: key, value: value),
    );
  }
}
