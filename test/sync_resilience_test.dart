import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/api_config.dart';
import 'package:todonote/data/api_exception.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/remote/api_client_dio.dart';
import 'package:todonote/sync/sync_payload.dart';
import 'package:todonote/sync/sync_worker.dart';

void main() {
  test('failed pull keeps cursor and pending operations unchanged', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const userId = 'user-1';
    const cursor = '2026-06-25T08:00:00.000Z';
    await db.syncDao.setLastSyncedAt(cursor, userId: userId);
    await db.syncDao.enqueueSyncOp(
      userId: userId,
      entityType: 'todo',
      entityId: 'todo-pending',
      operation: 'update',
      payload: SyncPayload.encode({'id': 'todo-pending'}),
    );
    final worker = SyncWorker.forTesting(
      database: db,
      client: _alwaysUnavailableClient(),
      userId: userId,
    );

    await expectLater(
      worker.pullChanges(userId: userId),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'sync_unavailable',
        ),
      ),
    );

    expect(await db.syncDao.getLastSyncedAt(userId: userId), cursor);
    final pending = await db.syncDao.getRowsForUser(userId: userId);
    expect(pending, hasLength(1));
    expect(pending.single.entityId, 'todo-pending');
  });

  test('initial and delta sync use no since, then valid ISO since', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const userId = 'user-1';
    final requestedUris = <Uri>[];
    var request = 0;
    final dio = Dio(BaseOptions(baseUrl: ApiConfig.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestedUris.add(options.uri);
          request++;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'server_time': request == 1
                    ? '2026-06-25T08:00:00.000Z'
                    : '2026-06-25T09:00:00.000Z',
                'changes': _emptyChanges(),
              },
            ),
          );
        },
      ),
    );
    final worker = SyncWorker.forTesting(
      database: db,
      client: ApiClientDio.forTesting(dio),
      userId: userId,
    );

    await worker.pullChanges(userId: userId);
    await worker.pullChanges(userId: userId);

    expect(requestedUris.first.queryParameters.containsKey('since'), isFalse);
    expect(
      requestedUris.last.queryParameters['since'],
      '2026-06-25T08:00:00.000Z',
    );
    expect(
      DateTime.parse(requestedUris.last.queryParameters['since']!),
      DateTime.parse('2026-06-25T08:00:00.000Z'),
    );
  });

  test('note Delta fields are decoded and retained in local storage', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const userId = 'user-1';
    final changes = _emptyChanges()
      ..['notes'] = [
        {
          'id': 'note-delta',
          'user_id': userId,
          'title': 'Delta note',
          'type': 'cornell',
          'body': 'Plain fallback',
          'cornell_cue': null,
          'cornell_summary': 'Summary fallback',
          'content_format': 'quill_delta_v1',
          'body_delta': {
            'ops': [
              {'insert': 'Hello\n'},
            ],
          },
          'cornell_cue_delta': null,
          'cornell_summary_delta': {
            'ops': [
              {'insert': 'Summary\n'},
            ],
          },
          'is_pinned': false,
          'tag_ids': <String>[],
          'note_links': <Map<String, dynamic>>[],
          'linked_todo_ids': <String>[],
          'created_at': '2026-06-25T07:00:00.000Z',
          'updated_at': '2026-06-25T08:00:00.000Z',
        },
      ];
    final worker = _workerForResponse(db, {
      'server_time': '2026-06-25T09:00:00.000Z',
      'changes': changes,
    });

    await worker.pullChanges(userId: userId);

    final row = await db.notesDao.getNoteById('note-delta');
    expect(row, isNotNull);
    expect(row!.contentFormat, 'quill_delta_v1');
    expect(jsonDecode(row.bodyDelta!), {
      'ops': [
        {'insert': 'Hello\n'},
      ],
    });
    expect(row.cornellCueDelta, isNull);
    expect(jsonDecode(row.cornellSummaryDelta!), {
      'ops': [
        {'insert': 'Summary\n'},
      ],
    });
  });

  test(
    'note relation arrays are preserved when absent from pull row',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      const userId = 'user-1';
      const createdAt = '2026-06-25T07:00:00.000Z';
      await db.notesDao.upsertNote(
        NotesTableCompanion.insert(
          id: 'note-source',
          userId: userId,
          title: 'Old',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await db.notesDao.upsertNote(
        NotesTableCompanion.insert(
          id: 'note-target',
          userId: userId,
          title: 'Target',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await db.notesDao.setNoteTags('note-source', const ['tag-1']);
      await db.notesDao.upsertNoteLink(
        NoteLinksTableCompanion.insert(
          id: 'link-1',
          sourceNoteId: 'note-source',
          targetNoteId: 'note-target',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await db.notesDao.upsertNoteTodoLink(
        NoteTodoLinksTableCompanion.insert(
          noteId: 'note-source',
          todoId: 'todo-1',
          createdAt: createdAt,
        ),
      );
      final changes = _emptyChanges()
        ..['notes'] = [
          {
            'id': 'note-source',
            'user_id': userId,
            'title': 'Updated',
            'type': 'free',
            'body': 'Body',
            'is_pinned': false,
            'created_at': createdAt,
            'updated_at': '2026-06-25T09:00:00.000Z',
          },
        ];

      await _workerForResponse(db, {
        'server_time': '2026-06-25T10:00:00.000Z',
        'changes': changes,
      }).pullChanges(userId: userId);

      expect(await db.notesDao.getTagIdsForNote('note-source'), ['tag-1']);
      expect(await db.notesDao.getOutgoingLinks('note-source'), hasLength(1));
      expect(
        await db.notesDao.getTodoLinksForNote('note-source'),
        hasLength(1),
      );
    },
  );

  test('note tombstone clears pending operation and junctions', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const userId = 'user-1';
    const createdAt = '2026-06-25T07:00:00.000Z';
    await db.notesDao.upsertNote(
      NotesTableCompanion.insert(
        id: 'note-deleted',
        userId: userId,
        title: 'Deleted',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await db.notesDao.setNoteTags('note-deleted', const ['tag-1']);
    await db.notesDao.upsertNoteTodoLink(
      NoteTodoLinksTableCompanion.insert(
        noteId: 'note-deleted',
        todoId: 'todo-1',
        createdAt: createdAt,
      ),
    );
    await db.syncDao.enqueueSyncOp(
      userId: userId,
      entityType: 'note',
      entityId: 'note-deleted',
      operation: 'update',
      payload: '{"id":"note-deleted"}',
    );
    final changes = _emptyChanges()
      ..['notes'] = [
        {
          'id': 'note-deleted',
          'updated_at': '2026-06-25T09:00:00.000Z',
          'deleted_at': '2026-06-25T09:00:00.000Z',
        },
      ];

    await _workerForResponse(db, {
      'server_time': '2026-06-25T10:00:00.000Z',
      'changes': changes,
    }).pullChanges(userId: userId);

    expect(
      await db.syncDao.getPendingForEntity(
        'note',
        'note-deleted',
        userId: userId,
      ),
      isNull,
    );
    expect(await db.notesDao.getTagIdsForNote('note-deleted'), isEmpty);
    expect(await db.notesDao.getTodoLinksForNote('note-deleted'), isEmpty);
    expect(
      (await db.notesDao.getNoteByIdIncludingDeleted(
        'note-deleted',
      ))?.deletedAt,
      isNotNull,
    );
  });

  test('concurrent sync calls share one in-flight job', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var requests = 0;
    final dio = Dio(BaseOptions(baseUrl: ApiConfig.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'server_time': '2026-06-25T09:00:00.000Z',
                'changes': _emptyChanges(),
              },
            ),
          );
        },
      ),
    );
    final worker = SyncWorker.forTesting(
      database: db,
      client: ApiClientDio.forTesting(dio),
    );

    final first = worker.sync();
    final second = worker.sync();

    expect(identical(first, second), isTrue);
    expect(await first, SyncRunResult.success);
    expect(await second, SyncRunResult.success);
    expect(requests, 1);
  });

  test(
    'exhausted transient failure returns retry for background callers',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final worker = SyncWorker.forTesting(
        database: db,
        client: _alwaysUnavailableClient(),
      );

      expect(await worker.sync(), SyncRunResult.retry);
      expect(await db.syncDao.getLastSyncedAt(userId: 'user-1'), isNull);
    },
  );
}

ApiClientDio _alwaysUnavailableClient() {
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.apiBaseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              statusCode: 503,
              data: {'error': 'sync_unavailable', 'request_id': 'pull-failed'},
            ),
          ),
        );
      },
    ),
  );
  return ApiClientDio.forTesting(
    dio,
    sleeper: (_) async {},
    randomDouble: () => 0,
  );
}

SyncWorker _workerForResponse(AppDatabase db, Map<String, dynamic> response) {
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.apiBaseUrl));
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
