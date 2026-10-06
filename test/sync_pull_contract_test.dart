import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/data/remote/api_client_dio.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/sync_payload.dart';
import 'package:todonote/sync/sync_worker.dart';

void main() {
  test('sync changes requires all twelve arrays', () {
    final changes = _emptyChanges()..remove('todos');
    expect(() => validateSyncChanges(changes), throwsA(isA<StateError>()));
  });

  test('todo changes are sorted parent-before-child and by depth', () {
    final sorted = sortTodoChangesTopologically([
      {'id': 'grandchild', 'parent_id': 'child', 'position': 0},
      {'id': 'child', 'parent_id': 'parent', 'position': 2},
      {'id': 'parent', 'parent_id': null, 'position': 3},
      {'id': 'child-first', 'parent_id': 'parent', 'position': 1},
    ]);
    expect(sorted.map((item) => (item as Map<String, dynamic>)['id']), [
      'parent',
      'child-first',
      'child',
      'grandchild',
    ]);
  });

  test(
    'LWW timestamp parsing compares real instants and rejects invalid data',
    () {
      expect(
        parseSyncTimestamp('2026-06-24T15:00:00+07:00', field: 'local'),
        parseSyncTimestamp('2026-06-24T08:00:00.000Z', field: 'server'),
      );
      expect(
        () => parseSyncTimestamp('not-a-date', field: 'updated_at'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'pull rolls back all rows and cursor when one record is invalid',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final response = {
        'server_time': '2026-06-24T10:00:00.000Z',
        'changes': _emptyChanges()
          ..['tags'] = [
            {
              'id': 'tag-1',
              'user_id': 'user-1',
              'name': 'Work',
              'color': '#112233',
              'created_at': '2026-06-24T08:00:00.000Z',
              'updated_at': '2026-06-24T08:00:00.000Z',
            },
          ]
          ..['todos'] = [
            {
              'id': 'bad-todo',
              'user_id': 'user-1',
              'created_at': '2026-06-24T08:00:00.000Z',
              'updated_at': '2026-06-24T08:00:00.000Z',
            },
          ],
      };
      final worker = _workerForResponse(db, response);

      await expectLater(
        worker.pullChanges(userId: 'user-1'),
        throwsA(anything),
      );

      expect(await db.todosDao.getTagById('tag-1'), isNull);
      expect(await db.syncDao.getLastSyncedAt(userId: 'user-1'), isNull);
    },
  );

  test(
    'pull applies child-first response canonically and tombstone wins',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      const userId = 'user-1';
      final old = Todo(
        id: 'deleted-todo',
        title: 'Pending local',
        createdAt: DateTime.utc(2026, 6, 24),
        updatedAt: DateTime.utc(2026, 6, 24),
      );
      await db.todosDao.upsertTodo(todoToCompanion(old, userId));
      final oldChild = Todo(
        id: 'deleted-child',
        parentId: old.id,
        title: 'Pending child',
        createdAt: DateTime.utc(2026, 6, 24),
        updatedAt: DateTime.utc(2026, 6, 24),
      );
      await db.todosDao.upsertTodo(todoToCompanion(oldChild, userId));
      await db.syncDao.enqueueSyncOp(
        userId: userId,
        entityType: 'todo',
        entityId: old.id,
        operation: 'update',
        payload: SyncPayload.encode({'id': old.id}),
      );
      await db.syncDao.enqueueSyncOp(
        userId: userId,
        entityType: 'todo',
        entityId: oldChild.id,
        operation: 'update',
        payload: SyncPayload.encode({'id': oldChild.id}),
      );
      final response = {
        'server_time': '2026-06-24T10:00:00.000Z',
        'changes': _emptyChanges()
          ..['todos'] = [
            {
              'id': 'child',
              'user_id': userId,
              'parent_id': 'parent',
              'title': 'Child',
              'description': 'Preserved',
              'tag_ids': ['tag-1'],
              'created_at': '2026-06-24T09:00:00.000Z',
              'updated_at': '2026-06-24T09:00:00.000Z',
            },
            {
              'id': 'parent',
              'user_id': userId,
              'parent_id': null,
              'title': 'Parent',
              'tag_ids': const <String>[],
              'created_at': '2026-06-24T09:00:00.000Z',
              'updated_at': '2026-06-24T09:00:00.000Z',
            },
            {
              'id': old.id,
              'updated_at': '2026-06-24T09:30:00.000Z',
              'deleted_at': '2026-06-24T09:30:00.000Z',
            },
          ],
      };
      final worker = _workerForResponse(db, response);

      await worker.pullChanges(userId: userId);

      expect((await db.todosDao.getTodoById('child'))?.parentId, 'parent');
      expect(
        (await db.todosDao.getTodoById('child'))?.description,
        'Preserved',
      );
      expect(await db.todosDao.getTodoById(old.id), isNull);
      expect(await db.todosDao.getTodoById(oldChild.id), isNull);
      expect(await db.syncDao.getPendingCount(userId: userId), 0);
      expect(
        await db.syncDao.getLastSyncedAt(userId: userId),
        '2026-06-24T10:00:00.000Z',
      );
    },
  );

  test(
    'canonical recurring occurrence purges the local generated subtree',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      const userId = 'user-1';
      final createdAt = DateTime.utc(2026, 6, 24);
      final localParent = Todo(
        id: 'local-parent',
        title: 'Recurring',
        scheduledDate: DateTime(2026, 6, 25),
        recurrenceType: 'daily',
        recurrenceTemplateId: 'series-root',
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final localChild = Todo(
        id: 'local-child',
        parentId: localParent.id,
        title: 'Local child',
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      for (final todo in [localParent, localChild]) {
        await db.todosDao.upsertTodo(todoToCompanion(todo, userId));
        await db.syncDao.enqueueSyncOp(
          userId: userId,
          entityType: 'todo',
          entityId: todo.id,
          operation: 'create',
          payload: SyncPayload.encode({'id': todo.id}),
        );
      }
      final response = {
        'server_time': '2026-06-24T10:00:00.000Z',
        'changes': _emptyChanges()
          ..['todos'] = [
            {
              'id': 'server-child',
              'user_id': userId,
              'parent_id': 'server-parent',
              'title': 'Server child',
              'tag_ids': const <String>[],
              'created_at': '2026-06-24T09:00:00.000Z',
              'updated_at': '2026-06-24T09:00:00.000Z',
            },
            {
              'id': 'server-parent',
              'user_id': userId,
              'title': 'Recurring',
              'scheduled_date': '2026-06-25',
              'recurrence_type': 'daily',
              'recurrence_interval': 1,
              'recurrence_template_id': 'series-root',
              'tag_ids': const <String>[],
              'created_at': '2026-06-24T09:00:00.000Z',
              'updated_at': '2026-06-24T09:00:00.000Z',
            },
          ],
      };

      await _workerForResponse(db, response).pullChanges(userId: userId);

      expect(await db.todosDao.getTodoById(localParent.id), isNull);
      expect(await db.todosDao.getTodoById(localChild.id), isNull);
      expect(await db.todosDao.getTodoById('server-parent'), isNotNull);
      expect(
        (await db.todosDao.getTodoById('server-child'))?.parentId,
        'server-parent',
      );
      expect(await db.syncDao.getPendingCount(userId: userId), 0);
      expect(
        (await db.todosDao.getOccurrenceForSeriesDate(
          'series-root',
          '2026-06-25',
        ))?.id,
        'server-parent',
      );
    },
  );

  test(
    'pulling a server frog clears local pending frog for the same day',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      const userId = 'user-1';
      final createdAt = DateTime.utc(2026, 7, 7, 8);
      final localFrog = Todo(
        id: 'local-frog',
        title: 'Local frog',
        scheduledDate: DateTime(2026, 7, 7),
        isFrog: true,
        frogDate: DateTime(2026, 7, 7),
        isImportant: true,
        isUrgent: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      await db.todosDao.upsertTodo(todoToCompanion(localFrog, userId));
      await db.syncDao.enqueueSyncOp(
        userId: userId,
        entityType: 'todo',
        entityId: localFrog.id,
        operation: 'update',
        payload: SyncPayload.encode(
          SyncPayload.fromTodo(
            (await db.todosDao.getTodoById(localFrog.id))!,
            const [],
          ),
        ),
      );
      final response = {
        'server_time': '2026-07-07T10:00:00.000Z',
        'changes': _emptyChanges()
          ..['todos'] = [
            {
              'id': 'server-frog',
              'user_id': userId,
              'title': 'Server frog',
              'scheduled_date': '2026-07-07',
              'is_frog': true,
              'frog_date': '2026-07-07',
              'is_important': false,
              'is_urgent': false,
              'tag_ids': const <String>[],
              'created_at': '2026-07-07T09:00:00.000Z',
              'updated_at': '2026-07-07T09:00:00.000Z',
            },
          ],
      };

      await _workerForResponse(db, response).pullChanges(userId: userId);

      final local = await db.todosDao.getTodoById(localFrog.id);
      final server = await db.todosDao.getTodoById('server-frog');
      expect(local!.isFrog, isFalse);
      expect(local.frogDate, isNull);
      expect(server!.isFrog, isTrue);
      expect(server.frogDate, '2026-07-07');
      expect(server.isImportant, isTrue);
      expect(server.isUrgent, isTrue);

      final queue = await db.syncDao.getRowsForUser(userId: userId);
      expect(queue, hasLength(1));
      final payload = SyncPayload.decode(queue.single.payload);
      expect(payload['id'], localFrog.id);
      expect(payload['is_frog'], isFalse);
      expect(payload['frog_date'], isNull);
    },
  );
}

SyncWorker _workerForResponse(AppDatabase db, Map<String, dynamic> response) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: response),
        );
      },
    ),
  );
  return SyncWorker.forTesting(
    database: db,
    client: ApiClientDio.forTesting(dio),
  );
}

Map<String, dynamic> _emptyChanges() => {
  for (final key in syncChangeKeys) key: <dynamic>[],
};
