import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/sync/sync_payload.dart';

void main() {
  test('outbox and cursor are isolated by authenticated user', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.syncDao.enqueueSyncOp(
      userId: 'user-a',
      entityType: 'todo',
      entityId: 'todo-a',
      operation: 'update',
      payload: SyncPayload.encode({'id': 'todo-a'}),
    );
    await db.syncDao.enqueueSyncOp(
      userId: 'user-b',
      entityType: 'todo',
      entityId: 'todo-b',
      operation: 'update',
      payload: SyncPayload.encode({'id': 'todo-b'}),
    );
    await db.syncDao.setLastSyncedAt(
      '2026-06-24T08:00:00.000Z',
      userId: 'user-a',
    );
    await db.syncDao.setLastSyncedAt(
      '2026-06-24T09:00:00.000Z',
      userId: 'user-b',
    );

    expect(
      (await db.syncDao.getDueBatch(
        userId: 'user-a',
      )).map((row) => row.entityId),
      ['todo-a'],
    );
    expect(
      (await db.syncDao.getDueBatch(
        userId: 'user-b',
      )).map((row) => row.entityId),
      ['todo-b'],
    );
    expect(
      await db.syncDao.getLastSyncedAt(userId: 'user-a'),
      '2026-06-24T08:00:00.000Z',
    );
    expect(
      await db.syncDao.getLastSyncedAt(userId: 'user-b'),
      '2026-06-24T09:00:00.000Z',
    );

    await db.syncDao.removeOpsForEntity('todo', 'todo-a', userId: 'user-a');
    expect(await db.syncDao.getPendingCount(userId: 'user-a'), 0);
    expect(await db.syncDao.getPendingCount(userId: 'user-b'), 1);
  });

  test('retry limit retains a diagnostic dead letter', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.syncDao.enqueueSyncOp(
      userId: 'user-a',
      entityType: 'todo',
      entityId: 'todo-a',
      operation: 'update',
      payload: SyncPayload.encode({'id': 'todo-a'}),
    );
    var row = (await db.syncDao.getRowsForUser(userId: 'user-a')).single;

    for (var retry = 0; retry < 10; retry++) {
      await db.syncDao.markFailedRetryable(
        row.id,
        row.retryCount,
        userId: 'user-a',
        error: 'server_error',
      );
      row = (await db.syncDao.getRowsForUser(userId: 'user-a')).single;
    }

    expect(row.isDeadLetter, isTrue);
    expect(row.lastError, contains('retry_limit'));
    expect(await db.syncDao.getPendingCount(userId: 'user-a'), 0);
    expect(await db.syncDao.getDeadLetterCount(userId: 'user-a'), 1);
  });

  test(
    'v11 migration clears unknown-owner sync state but keeps cache',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.tagsTable)
          .insert(
            TagsTableCompanion.insert(
              id: 'tag-1',
              name: 'Kept cache',
              userId: 'user-a',
              createdAt: '2026-06-24T08:00:00.000Z',
              updatedAt: '2026-06-24T08:00:00.000Z',
            ),
          );
      await db
          .into(db.syncQueueTable)
          .insert(
            SyncQueueTableCompanion.insert(
              entityType: 'todo',
              entityId: 'legacy-todo',
              operation: 'update',
              payload: '{}',
              createdAt: '2026-06-24T08:00:00.000Z',
            ),
          );
      await db.syncDao.setSyncMeta(
        'last_synced_at',
        '2026-06-24T08:00:00.000Z',
      );

      await db.migration.onUpgrade(Migrator(db), 10, 11);

      expect(await db.select(db.syncQueueTable).get(), isEmpty);
      expect(await db.syncDao.getSyncMeta('last_synced_at'), isNull);
      expect((await db.select(db.tagsTable).getSingle()).name, 'Kept cache');
    },
  );
}
