import 'dart:ui' show Color;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todonote/data/api_client.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/data/remote/api_client_dio.dart';
import 'package:todonote/data/todos_repository.dart';
import 'package:todonote/models/recurring_todo_delete_scope.dart';
import 'package:todonote/models/tag.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/sync/sync_payload.dart';
import 'package:todonote/sync/sync_worker.dart';

/// Hai phía phối hợp qua `/sync`: Mobile đỗ / hồi sinh occurrence bằng `update`
/// thường, còn backend trả `conflict` khi `create` trùng (series, ngày).
void main() {
  const userId = 'user-1';
  const seriesId = 'template';

  late AppDatabase db;
  late TodosRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TodosRepository.forTesting(db, userId: userId);
  });

  tearDown(() async {
    ConnectivitySync.instance.cancelPending();
    await db.close();
  });

  Todo root({DateTime? dueAt, DateTime? scheduledDate}) => Todo(
    id: seriesId,
    title: 'Daily review',
    scheduledDate: scheduledDate ?? DateTime(2026, 6, 24),
    dueAt: dueAt,
    recurrenceType: 'daily',
    createdAt: DateTime.utc(2026, 6, 24),
    updatedAt: DateTime.utc(2026, 6, 24),
  );

  Future<List<TodoRow>> liveRows() async => (await db.todosDao.getSeriesRows(
    seriesId,
    userId: userId,
  )).where((row) => row.deletedAt == null).toList();

  Future<Map<String, dynamic>> opPayload(String id) async {
    final queue = await db.syncDao.getRowsForUser(userId: userId);
    return SyncPayload.decode(
      queue.singleWhere((r) => r.entityId == id).payload,
    );
  }

  SyncWorker workerFor(
    Map<String, dynamic> Function(RequestOptions) respond, {
    List<RequestOptions>? requests,
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests?.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: respond(options),
            ),
          );
        },
      ),
    );
    return SyncWorker.forTesting(
      database: db,
      client: ApiClientDio.forTesting(dio),
      userId: userId,
    );
  }

  Map<String, dynamic> pullOf(List<Map<String, dynamic>> todos) => {
    'server_time': '2026-06-30T00:00:00.000Z',
    'changes': {
      for (final key in syncChangeKeys) key: <dynamic>[],
      'todos': todos,
    },
  };

  Map<String, dynamic> serverTodo(
    String id, {
    required String status,
    required String date,
    String updatedAt = '2026-06-30T00:00:00.000Z',
    String? completedAt,
    List<String> tagIds = const [],
  }) => {
    'id': id,
    'user_id': userId,
    'parent_id': null,
    'title': 'Daily review',
    'status': status,
    'position': 0,
    'is_frog': false,
    'scheduled_date': date,
    'completed_at': completedAt,
    'recurrence_type': 'daily',
    'recurrence_interval': 1,
    'recurrence_template_id': seriesId,
    'tag_ids': tagIds,
    'created_at': '2026-06-24T00:00:00.000Z',
    'updated_at': updatedAt,
    'deleted_at': null,
  };

  // ── T4(a) Payload mang đúng trạng thái đỗ / hồi sinh ──────────────────────
  group('payload of parking and reviving', () {
    test('parking an already-synced occurrence sends a plain update', () async {
      final first = await repository.completeLocalFirst(root());
      final nextId = first.nextRecurringTodo!.id;
      // Giả lập create của B đã lên server: outbox rỗng.
      await db.syncDao.removeOpsForEntity('todo', nextId, userId: userId);

      await repository.uncompleteLocalFirst(first.todo);

      final queue = await db.syncDao.getRowsForUser(userId: userId);
      final op = queue.singleWhere((row) => row.entityId == nextId);
      expect(op.operation, 'update');
      final payload = SyncPayload.decode(op.payload);
      expect(payload['status'], 'archived');
      expect(payload['scheduled_date'], '2026-06-25');
      expect(payload['completed_at'], isNull);
      expect(payload['deleted_at'], isNull);
      expect(payload['parent_id'], isNull);
      expect(payload['recurrence_type'], 'daily');
      expect(payload['recurrence_template_id'], seriesId);
    });

    test(
      'reviving it carries open, completed_at null and the moved date',
      () async {
        final dueRoot = root(dueAt: DateTime.utc(2026, 6, 24, 23, 59));
        final first = await repository.completeLocalFirst(dueRoot);
        final nextId = first.nextRecurringTodo!.id;
        await db.syncDao.removeOpsForEntity('todo', nextId, userId: userId);
        final reopened = await repository.uncompleteLocalFirst(first.todo);
        final moved = await repository.updateLocalFirst(reopened, const {
          'scheduled_date': '2026-06-30',
        });

        final second = await repository.completeLocalFirst(moved);

        expect(second.nextRecurringTodo!.id, nextId);
        final queue = await db.syncDao.getRowsForUser(userId: userId);
        final ops = queue.where((row) => row.entityId == nextId).toList();
        expect(ops, hasLength(1), reason: 'park + revive gộp thành một update');
        expect(ops.single.operation, 'update');
        final payload = SyncPayload.decode(ops.single.payload);
        expect(payload['status'], 'open');
        expect(payload['scheduled_date'], '2026-07-01');
        expect(payload['completed_at'], isNull);
        expect(payload['due_at'], '2026-07-01T23:59:00.000Z');
      },
    );

    test(
      'while the create is still pending park/revive stay one create',
      () async {
        final first = await repository.completeLocalFirst(root());
        final nextId = first.nextRecurringTodo!.id;

        final reopened = await repository.uncompleteLocalFirst(first.todo);
        var queue = await db.syncDao.getRowsForUser(userId: userId);
        var op = queue.singleWhere((row) => row.entityId == nextId);
        expect(op.operation, 'create');
        expect(SyncPayload.decode(op.payload)['status'], 'archived');

        await repository.completeLocalFirst(reopened);
        queue = await db.syncDao.getRowsForUser(userId: userId);
        final ops = queue.where((row) => row.entityId == nextId).toList();
        expect(ops, hasLength(1));
        expect(ops.single.operation, 'create');
        expect(SyncPayload.decode(ops.single.payload)['status'], 'open');
      },
    );
  });

  // ── T4(b) Thiết bị khác đỗ / hồi sinh qua pull ─────────────────────────────
  group('pull of parked and revived occurrences', () {
    Future<void> insertSyncedPair({String bStatus = 'open'}) async {
      await db.todosDao.upsertTodo(todoToCompanion(root(), userId));
      final b = Todo(
        id: 'b',
        title: 'Daily review',
        status: TodoStatus.parse(bStatus),
        scheduledDate: DateTime(2026, 6, 25),
        recurrenceType: 'daily',
        recurrenceTemplateId: seriesId,
        createdAt: DateTime.utc(2026, 6, 24),
        updatedAt: DateTime.utc(2026, 6, 24),
      );
      await db.todosDao.upsertTodo(todoToCompanion(b, userId));
    }

    test('another device parks it: the local row becomes archived', () async {
      await insertSyncedPair();

      await workerFor(
        (_) =>
            pullOf([serverTodo('b', status: 'archived', date: '2026-06-25')]),
      ).pullChanges(userId: userId);

      final row = await db.todosDao.getTodoById('b');
      expect(row!.status, 'archived');
      expect(row.completedAt, isNull);
      expect(await liveRows(), hasLength(2));
    });

    test(
      'another device revives and moves it: the local row follows',
      () async {
        await insertSyncedPair(bStatus: 'archived');

        await workerFor(
          (_) => pullOf([serverTodo('b', status: 'open', date: '2026-07-01')]),
        ).pullChanges(userId: userId);

        final row = await db.todosDao.getTodoById('b');
        expect(row!.status, 'open');
        expect(row.scheduledDate, '2026-07-01');
        expect(row.completedAt, isNull);
        expect(await liveRows(), hasLength(2));
      },
    );

    test('a newer local change with a pending op is not overwritten', () async {
      await insertSyncedPair();
      // Người dùng vừa bỏ tick ở máy này: B đã đỗ cục bộ, op còn chờ đẩy.
      final local = Todo(
        id: 'b',
        title: 'Daily review',
        status: TodoStatus.archived,
        scheduledDate: DateTime(2026, 6, 25),
        recurrenceType: 'daily',
        recurrenceTemplateId: seriesId,
        createdAt: DateTime.utc(2026, 6, 24),
        updatedAt: DateTime.utc(2026, 6, 30, 12),
      );
      await db.todosDao.upsertTodo(todoToCompanion(local, userId));
      await db.syncDao.enqueueSyncOp(
        userId: userId,
        entityType: 'todo',
        entityId: 'b',
        operation: 'update',
        payload: SyncPayload.encode({'id': 'b', 'status': 'archived'}),
      );

      // Bản server cũ hơn (vẫn "open") không được hoàn tác việc đỗ.
      await workerFor(
        (_) => pullOf([
          serverTodo(
            'b',
            status: 'open',
            date: '2026-06-25',
            updatedAt: '2026-06-30T00:00:00.000Z',
          ),
        ]),
      ).pullChanges(userId: userId);

      expect((await db.todosDao.getTodoById('b'))!.status, 'archived');
      final queue = await db.syncDao.getRowsForUser(userId: userId);
      expect(queue.where((row) => row.entityId == 'b'), hasLength(1));
    });

    test(
      'a stale REST list does not un-park a row with a pending update',
      () async {
        await insertSyncedPair();
        final local = Todo(
          id: 'b',
          title: 'Daily review',
          status: TodoStatus.archived,
          scheduledDate: DateTime(2026, 6, 25),
          recurrenceType: 'daily',
          recurrenceTemplateId: seriesId,
          createdAt: DateTime.utc(2026, 6, 24),
          updatedAt: DateTime.utc(2026, 6, 30, 12),
        );
        await db.todosDao.upsertTodo(todoToCompanion(local, userId));
        await db.syncDao.enqueueSyncOp(
          userId: userId,
          entityType: 'todo',
          entityId: 'b',
          operation: 'update',
          payload: SyncPayload.encode({'id': 'b', 'status': 'archived'}),
        );
        final restRepository = TodosRepository.forTesting(
          db,
          userId: userId,
          client: ApiClient.forTesting(
            MockClient(
              (_) async => http.Response(
                '{"items":[${_restJson('b', 'open', '2026-06-25')}],"nextCursor":null}',
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          ),
        );

        await restRepository.list(limit: 100);

        expect((await db.todosDao.getTodoById('b'))!.status, 'archived');
      },
    );
  });

  // ── T4(c) Repair sau pull ───────────────────────────────────────────────────
  group('post-pull repair', () {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    Todo occurrence(
      String id,
      DateTime date,
      TodoStatus status, {
      bool root = false,
    }) => Todo(
      id: id,
      title: 'Daily review',
      status: status,
      scheduledDate: date,
      completedAt: status == TodoStatus.done
          ? DateTime.utc(2026, 6, 24, 8)
          : null,
      recurrenceType: 'daily',
      recurrenceTemplateId: root ? null : seriesId,
      createdAt: DateTime.utc(2026, 6, 24),
      updatedAt: DateTime.utc(2026, 6, 24),
    );

    Future<void> insertRows(List<Todo> todos) async {
      for (final todo in todos) {
        await db.todosDao.upsertTodo(todoToCompanion(todo, userId));
      }
    }

    test(
      'an open occurrence plus a parked one: nothing is created or purged',
      () async {
        await insertRows([
          occurrence(seriesId, todayDate, TodoStatus.open, root: true),
          occurrence(
            'parked',
            todayDate.add(const Duration(days: 1)),
            TodoStatus.archived,
          ),
        ]);

        await repository.ensureAllRecurrenceInstances();
        await repository.ensureAllRecurrenceInstances();

        final rows = await liveRows();
        expect(rows.map((row) => row.id).toSet(), {seriesId, 'parked'});
        expect(
          rows.singleWhere((row) => row.id == 'parked').status,
          'archived',
        );
        expect(await db.syncDao.getRowsForUser(userId: userId), isEmpty);
      },
    );

    test(
      'a done occurrence plus a parked one: the parked row is revived',
      () async {
        final tomorrow = todayDate.add(const Duration(days: 1));
        await insertRows([
          occurrence(seriesId, todayDate, TodoStatus.done, root: true),
          occurrence('parked', tomorrow, TodoStatus.archived),
        ]);

        await repository.ensureAllRecurrenceInstances();

        var rows = await liveRows();
        expect(rows, hasLength(2), reason: 'không tạo thêm row mới');
        final revived = rows.singleWhere((row) => row.id == 'parked');
        expect(revived.status, 'open');
        expect(revived.scheduledDate, iso(tomorrow));
        expect(revived.completedAt, isNull);
        final payload = await opPayload('parked');
        expect(payload['status'], 'open');

        // Idempotent: chạy lại không đổi số row sống và không enqueue thêm.
        final queueBefore = await db.syncDao.getRowsForUser(userId: userId);
        await repository.ensureAllRecurrenceInstances();
        rows = await liveRows();
        expect(rows, hasLength(2));
        expect(
          (await db.syncDao.getRowsForUser(userId: userId)).length,
          queueBefore.length,
        );
      },
    );

    test(
      'a parked row with a stale date is moved to the next valid date',
      () async {
        final old = todayDate.subtract(const Duration(days: 5));
        await insertRows([
          occurrence(seriesId, old, TodoStatus.done, root: true),
          occurrence(
            'parked',
            old.add(const Duration(days: 1)),
            TodoStatus.archived,
          ),
        ]);

        await repository.ensureAllRecurrenceInstances();

        final rows = await liveRows();
        expect(rows, hasLength(2));
        final revived = rows.singleWhere((row) => row.id == 'parked');
        expect(revived.status, 'open');
        expect(revived.scheduledDate, iso(todayDate));
      },
    );
  });

  // ── T5 `conflict` của occurrence kèm cả cây việc con ───────────────────────
  group('push conflict for an occurrence with a cloned subtree', () {
    test(
      'adopts the server row and clears every trace of the local subtree',
      () async {
        // Series: gốc + việc con + việc cháu + một việc con có trigger vào anh em.
        final tag = Tag(
          id: 'tag-1',
          name: 'Work',
          color: const Color(0xFF3366FF),
        );
        await db.todosDao.upsertTag(tagToCompanion(tag, userId));
        final a = root();
        final child = Todo(
          id: 'child',
          parentId: seriesId,
          title: 'Child',
          createdAt: DateTime.utc(2026, 6, 24),
          updatedAt: DateTime.utc(2026, 6, 24),
        );
        final grandchild = Todo(
          id: 'grandchild',
          parentId: 'child',
          title: 'Grandchild',
          createdAt: DateTime.utc(2026, 6, 24),
          updatedAt: DateTime.utc(2026, 6, 24),
        );
        final sibling = Todo(
          id: 'sibling',
          parentId: seriesId,
          title: 'Sibling',
          triggerAfterTodoId: 'child',
          position: 1,
          createdAt: DateTime.utc(2026, 6, 24),
          updatedAt: DateTime.utc(2026, 6, 24),
        );
        for (final todo in [a, child, grandchild, sibling]) {
          await db.todosDao.upsertTodo(todoToCompanion(todo, userId));
        }
        await db.todosDao.setTodoTags(seriesId, ['tag-1']);

        final done = await repository.completeLocalFirst(a);
        final bId = done.nextRecurringTodo!.id;
        final subtree = (await db.todosDao.getActiveSubtree(
          bId,
          userId: userId,
        )).map((row) => row.id).toList();
        expect(subtree, hasLength(3), reason: 'child + grandchild + sibling');
        final purgedIds = {bId, ...subtree};
        // Một ghi chú liên kết tới việc con đã nhân bản.
        await db
            .into(db.noteTodoLinksTable)
            .insert(
              NoteTodoLinksTableCompanion.insert(
                noteId: 'note-1',
                todoId: subtree.first,
                createdAt: '2026-06-24T00:00:00.000Z',
              ),
            );
        final queue = await db.syncDao.getRowsForUser(userId: userId);
        expect(
          queue.map((row) => row.entityId).toSet(),
          containsAll(purgedIds),
          reason: 'create của B và cả cây con cùng nằm trong lô',
        );

        // Server đã có occurrence chính tắc `server-b` ở đúng slot.
        final requests = <RequestOptions>[];
        final worker = workerFor((options) {
          requests.add(options);
          return {
            'results': [
              for (final row in queue)
                if (row.entityId == bId)
                  {
                    'id': row.entityId,
                    'status': 'conflict',
                    'server_version': serverTodo(
                      'server-b',
                      status: 'open',
                      date: '2026-06-25',
                      tagIds: const ['tag-1'],
                    ),
                  }
                else
                  {'id': row.entityId, 'status': 'applied'},
            ],
          };
        });

        await worker.pushPending(userId: userId);

        // Đúng 1 row sống ở (series, ngày) và là bản của server.
        final slot = (await liveRows())
            .where((row) => row.scheduledDate == '2026-06-25')
            .toList();
        expect(slot.map((row) => row.id), ['server-b']);
        expect(slot.single.status, 'open');

        // Cây cục bộ của B bị purge hoàn toàn.
        final stillThere = await (db.select(
          db.todosTable,
        )..where((t) => t.id.isIn(purgedIds.toList()))).get();
        expect(stillThere, isEmpty);

        // Junction không còn mồ côi, và row server nhận đúng tag của nó.
        final tagJunctions = await db.select(db.todoTagsTable).get();
        expect(
          tagJunctions.where((j) => purgedIds.contains(j.todoId)),
          isEmpty,
          reason: 'todo_tags của B/cây con phải bị dọn',
        );
        expect(
          tagJunctions.where((j) => j.todoId == 'server-b').map((j) => j.tagId),
          ['tag-1'],
        );
        final noteLinks = await db.select(db.noteTodoLinksTable).get();
        expect(noteLinks.where((l) => purgedIds.contains(l.todoId)), isEmpty);

        // Outbox sạch, không op mồ côi trỏ tới id đã purge; sync lần 2 im lặng.
        expect(await db.syncDao.getRowsForUser(userId: userId), isEmpty);
        final sentOnce = requests.length;
        await worker.pushPending(userId: userId);
        expect(requests.length, sentOnce);
        expect(await db.syncDao.getRowsForUser(userId: userId), isEmpty);
      },
    );

    test(
      'a parked canonical row is adopted, then repair revives that row',
      () async {
        // Máy này hoàn thành A (tạo B chờ push); nhưng trên server, thiết bị khác
        // đã đỗ occurrence chính tắc `server-b` ở đúng slot đó.
        final a = root(scheduledDate: DateTime.now());
        await db.todosDao.upsertTodo(todoToCompanion(a, userId));
        final done = await repository.completeLocalFirst(a);
        final bId = done.nextRecurringTodo!.id;
        final slot = _dateKey(done.nextRecurringTodo!.scheduledDate!);
        final queue = await db.syncDao.getRowsForUser(userId: userId);

        await workerFor(
          (_) => {
            'results': [
              for (final row in queue)
                if (row.entityId == bId)
                  {
                    'id': bId,
                    'status': 'conflict',
                    'server_version': serverTodo(
                      'server-b',
                      status: 'archived',
                      date: slot,
                    ),
                  }
                else
                  {'id': row.entityId, 'status': 'applied'},
            ],
          },
        ).pushPending(userId: userId);

        var live = await liveRows();
        expect(
          live.where((row) => row.scheduledDate == slot).map((r) => r.id),
          ['server-b'],
        );
        expect(
          live.singleWhere((row) => row.id == 'server-b').status,
          'archived',
          reason: 'A đã xong mà slot kế tiếp đang bị ẩn: chưa có việc để làm',
        );

        await repository.ensureAllRecurrenceInstances();

        live = await liveRows();
        expect(live.where((row) => row.scheduledDate == slot), hasLength(1));
        final revived = live.singleWhere((row) => row.id == 'server-b');
        expect(revived.status, 'open');
        expect((await opPayload('server-b'))['status'], 'open');
        expect(live.length, 2, reason: 'A + server-b, không row nào mới');
      },
    );
  });

  // ── T6(b) Xóa "chỉ lần này" khi occurrence kế tiếp đang đỗ ────────────────
  group('delete only this occurrence while the next one is parked', () {
    Future<({Todo reopened, String bId})> parkedNext() async {
      final a = root();
      await db.todosDao.upsertTodo(todoToCompanion(a, userId));
      final done = await repository.completeLocalFirst(a);
      final reopened = await repository.uncompleteLocalFirst(done.todo);
      return (reopened: reopened, bId: done.nextRecurringTodo!.id);
    }

    test(
      'queues one delete, revives locally and adds no extra update',
      () async {
        final parked = await parkedNext();
        // B đã có trên server: không còn op chờ của nó.
        await db.syncDao.removeOpsForEntity('todo', parked.bId, userId: userId);

        await repository.deleteTodoLocalFirst(
          parked.reopened,
          scope: RecurringTodoDeleteScope.thisOccurrence,
        );

        final queue = await db.syncDao.getRowsForUser(userId: userId);
        expect(queue, hasLength(1));
        final op = queue.single;
        expect(op.entityId, seriesId);
        expect(op.operation, 'delete');
        // Payload rút gọn đủ cho `todoDeleteScope` + `deleteTodo` của server.
        expect(SyncPayload.decode(op.payload), {
          'id': seriesId,
          'delete_scope': 'this',
          'deleted_at': isA<String>(),
          'updated_at': isA<String>(),
        });
        // Server tự hồi sinh B khi xử lý lệnh xóa, nên Mobile không gửi update.
        final b = await db.todosDao.getTodoById(parked.bId);
        expect(b!.status, 'open');
        expect(b.scheduledDate, '2026-06-25');
      },
    );

    for (final reversed in [false, true]) {
      test(
        'converges with the server when B was never synced '
        '(server handles ops ${reversed ? 'in reverse' : 'in order'})',
        () async {
          final parked = await parkedNext();
          await repository.deleteTodoLocalFirst(
            parked.reopened,
            scope: RecurringTodoDeleteScope.thisOccurrence,
          );

          // Server đã biết A (gốc) từ trước; B chỉ còn là `create` đang chờ.
          final backend = _FakeBackend(userId)
            ..seed(
              serverTodo(
                seriesId,
                status: 'open',
                date: '2026-06-24',
                updatedAt: '2026-06-24T00:00:00.000Z',
              )..['recurrence_template_id'] = null,
            );
          final worker = workerFor((options) {
            if (options.path.contains('sync/push')) {
              final ops = (options.data as Map)['operations'] as List;
              return backend.push(ops, reversed: reversed);
            }
            return backend.pull();
          });

          await worker.sync();

          // Mobile chỉ còn đúng 1 occurrence sống ở slot, đang mở và khớp server.
          final slot = (await liveRows())
              .where((row) => row.scheduledDate == '2026-06-25')
              .toList();
          expect(slot, hasLength(1));
          expect(slot.single.status, 'open');
          expect(slot.single.id, backend.liveOpenAt('2026-06-25')!['id']);
          expect(backend.liveAt('2026-06-25'), hasLength(1));
          expect(await db.syncDao.getRowsForUser(userId: userId), isEmpty);

          // Repair sau pull không phát sinh thêm gì.
          await repository.ensureAllRecurrenceInstances();
          expect(
            (await liveRows()).where((r) => r.scheduledDate == '2026-06-25'),
            hasLength(1),
          );
          expect(await db.syncDao.getRowsForUser(userId: userId), isEmpty);
        },
      );
    }
  });
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _restJson(String id, String status, String date) =>
    '{"id":"$id","title":"Daily review","status":"$status",'
    '"scheduled_date":"$date","recurrence_type":"daily",'
    '"recurrence_interval":1,"recurrence_template_id":"template",'
    '"created_at":"2026-06-24T00:00:00.000Z",'
    '"updated_at":"2026-06-30T00:00:00.000Z"}';

/// Server giả mô phỏng đúng các quy tắc phía backend cần cho test này:
///  - `create`/update-của-row-chưa-có của một occurrence trùng (series, ngày) với
///    row sống khác id → `conflict` (§3.6 trong sync.service.ts);
///  - `delete` phạm vi `this` của một todo lặp → roll forward như
///    `createNextRecurringTodo` (hồi sinh row đã đỗ ở slot, hoặc tạo mới);
///  - mọi ghi của server đều đóng dấu `updated_at` mới hơn thiết bị.
/// Chỉ hỗ trợ lặp `daily` interval 1.
class _FakeBackend {
  _FakeBackend(this.userId);

  final String userId;
  final rows = <String, Map<String, dynamic>>{};
  var _ticks = 0;

  String _stamp() => DateTime.now()
      .toUtc()
      .add(Duration(minutes: 10, seconds: _ticks++))
      .toIso8601String();

  void seed(Map<String, dynamic> row) => rows[row['id'] as String] = row;

  String _series(Map<String, dynamic> row) =>
      (row['recurrence_template_id'] ?? row['id']) as String;

  bool _isLiveOccurrence(Map<String, dynamic> row) =>
      row['deleted_at'] == null &&
      row['parent_id'] == null &&
      row['recurrence_type'] != null;

  List<Map<String, dynamic>> liveAt(String date) => rows.values
      .where((row) => _isLiveOccurrence(row) && row['scheduled_date'] == date)
      .toList();

  Map<String, dynamic>? liveOpenAt(String date) {
    final open = liveAt(date).where((row) => row['status'] == 'open');
    return open.isEmpty ? null : open.first;
  }

  Map<String, dynamic> push(List<dynamic> ops, {required bool reversed}) {
    final ordered = reversed ? ops.reversed.toList() : ops;
    return {
      'results': [for (final op in ordered) _apply(op as Map<String, dynamic>)],
    };
  }

  Map<String, dynamic> pull() => {
    'server_time': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String(),
    'changes': {
      for (final key in syncChangeKeys) key: <dynamic>[],
      'todos': [
        for (final row in rows.values) {...row, 'tag_ids': <String>[]},
      ],
    },
  };

  Map<String, dynamic> _apply(Map<String, dynamic> op) {
    if (op['type'] != 'todo') {
      return {'id': (op['payload'] as Map)['id'], 'status': 'applied'};
    }
    final payload = Map<String, dynamic>.from(op['payload'] as Map);
    final id = payload['id'] as String;

    if (op['op'] == 'delete') {
      final row = rows[id];
      if (row == null) return {'id': id, 'status': 'applied'};
      row['deleted_at'] = payload['deleted_at'];
      row['updated_at'] = _stamp();
      if (payload['delete_scope'] == 'this' && row['recurrence_type'] != null) {
        _rollForward(row);
      }
      return {'id': id, 'status': 'applied'};
    }

    final isNew = !rows.containsKey(id);
    if (isNew &&
        payload['recurrence_type'] != null &&
        payload['recurrence_template_id'] != null &&
        payload['scheduled_date'] != null &&
        payload['parent_id'] == null) {
      final canonical = rows.values.where(
        (row) =>
            _isLiveOccurrence(row) &&
            _series(row) == payload['recurrence_template_id'] &&
            row['scheduled_date'] == payload['scheduled_date'] &&
            row['id'] != id,
      );
      if (canonical.isNotEmpty) {
        return {
          'id': id,
          'status': 'conflict',
          'server_version': {...canonical.first, 'tag_ids': <String>[]},
        };
      }
    }
    rows[id] = {...?rows[id], ...payload, 'deleted_at': null};
    return {'id': id, 'status': 'applied'};
  }

  /// `createNextRecurringTodo` của backend: slot kế tiếp (bỏ qua ngày đã xóa),
  /// dùng lại row đã đỗ, rồi mới tạo mới.
  void _rollForward(Map<String, dynamic> source) {
    final series = _series(source);
    var cursor = DateTime.parse('${source['scheduled_date']}T00:00:00Z');
    String next;
    Map<String, dynamic>? holder;
    while (true) {
      cursor = cursor.add(const Duration(days: 1));
      next = _dateKey(cursor);
      final atDate = rows.values.where(
        (row) =>
            row['recurrence_type'] != null &&
            _series(row) == series &&
            row['scheduled_date'] == next,
      );
      if (atDate.isEmpty) break;
      final live = atDate.where((row) => row['deleted_at'] == null);
      if (live.isNotEmpty) {
        holder = live.first;
        break;
      }
    }
    if (holder != null) {
      if (holder['status'] == 'archived') _revive(holder);
      return;
    }
    final parked = rows.values.where(
      (row) =>
          _isLiveOccurrence(row) &&
          _series(row) == series &&
          row['status'] == 'archived',
    );
    if (parked.isNotEmpty) {
      _revive(parked.first, moveTo: next);
      return;
    }
    rows['server-new'] = {
      ...source,
      'id': 'server-new',
      'status': 'open',
      'completed_at': null,
      'scheduled_date': next,
      'recurrence_template_id': series,
      'deleted_at': null,
      'created_at': _stamp(),
      'updated_at': _stamp(),
    };
  }

  void _revive(Map<String, dynamic> row, {String? moveTo}) {
    row['status'] = 'open';
    row['completed_at'] = null;
    row['updated_at'] = _stamp();
    if (moveTo != null) row['scheduled_date'] = moveTo;
  }
}
