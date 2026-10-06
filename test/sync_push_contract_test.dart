import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/api_exception.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/remote/api_client_dio.dart';
import 'package:todonote/sync/sync_payload.dart';
import 'package:todonote/sync/sync_worker.dart';

void main() {
  test('permanent push error becomes a diagnostic dead letter', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const userId = 'user-1';
    await db.syncDao.enqueueSyncOp(
      userId: userId,
      entityType: 'todo',
      entityId: 'todo-1',
      operation: 'update',
      payload: SyncPayload.encode({'id': 'todo-1'}),
    );
    final worker = _workerForPushResponse(db, {
      'results': [
        {'id': 'todo-1', 'status': 'error', 'error': 'bad_input'},
      ],
    });

    await expectLater(
      worker.pushPending(userId: userId),
      throwsA(isA<ApiException>()),
    );

    final row = (await db.syncDao.getRowsForUser(userId: userId)).single;
    expect(row.isDeadLetter, isTrue);
    expect(row.lastError, 'bad_input');
  });

  test('delete not_found is treated as idempotent success', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const userId = 'user-1';
    await db.syncDao.enqueueSyncOp(
      userId: userId,
      entityType: 'todo',
      entityId: 'todo-1',
      operation: 'delete',
      payload: SyncPayload.encode({'id': 'todo-1', 'delete_scope': 'this'}),
    );
    final worker = _workerForPushResponse(db, {
      'results': [
        {'id': 'todo-1', 'status': 'error', 'error': 'not_found'},
      ],
    });

    await worker.pushPending(userId: userId);

    expect(await db.syncDao.getRowsForUser(userId: userId), isEmpty);
  });

  test('dependency sorting remains stable beyond one hundred rows', () {
    final rows = <({int id, String type})>[
      for (var i = 0; i < 120; i++) (id: i, type: i < 60 ? 'todo' : 'tag'),
    ];
    final sorted = sortedByDependency(
      rows: rows,
      getEntityType: (row) => row.type,
      getId: (row) => row.id,
    );

    expect(sorted.take(60).every((row) => row.type == 'tag'), isTrue);
    expect(
      sorted.where((row) => row.type == 'tag').map((row) => row.id),
      orderedEquals(List.generate(60, (index) => index + 60)),
    );
    expect(
      sorted.where((row) => row.type == 'todo').map((row) => row.id),
      orderedEquals(List.generate(60, (index) => index)),
    );
  });
}

SyncWorker _workerForPushResponse(
  AppDatabase db,
  Map<String, dynamic> response,
) {
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
