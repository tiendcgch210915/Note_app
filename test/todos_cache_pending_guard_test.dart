import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todonote/data/api_client.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/data/todos_repository.dart';
import 'package:todonote/models/recurring_todo_delete_scope.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/connectivity_sync.dart';

const _userId = 'user-1';
final _t0 = DateTime.utc(2026, 7);

Todo _todo(String id, String title, {TodoStatus status = TodoStatus.open}) =>
    Todo(id: id, title: title, status: status, createdAt: _t0, updatedAt: _t0);

Map<String, dynamic> _todoJson(String id, String title) => {
  'id': id,
  'title': title,
  'status': 'open',
  'created_at': _t0.toIso8601String(),
  'updated_at': _t0.toIso8601String(),
};

void main() {
  late AppDatabase db;
  late TodosRepository repo;
  late List<Map<String, dynamic>> serverTodos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serverTodos = [];
    repo = TodosRepository.forTesting(
      db,
      userId: _userId,
      client: ApiClient.forTesting(
        MockClient(
          (request) async => http.Response(
            jsonEncode({'items': serverTodos}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );
  });

  tearDown(() async {
    ConnectivitySync.instance.cancelPending();
    await db.close();
  });

  test('server list does not overwrite a todo with unsynced changes', () async {
    await db.todosDao.upsertTodo(
      todoToCompanion(_todo('a', 'Edited offline'), _userId),
    );
    await db.syncDao.enqueueSyncOp(
      userId: _userId,
      entityType: 'todo',
      entityId: 'a',
      operation: 'update',
      payload: '{}',
    );
    serverTodos = [_todoJson('a', 'Old server title'), _todoJson('b', 'New')];

    await repo.list(limit: 100);

    final local = {for (final todo in await repo.listLocal()) todo.id: todo};
    expect(local['a']!.title, 'Edited offline');
    expect(local['b']!.title, 'New');
  });

  test(
    'a todo deleted offline is not resurrected by the server list',
    () async {
      await db.todosDao.upsertTodo(
        todoToCompanion(_todo('a', 'Gone'), _userId),
      );
      await repo.deleteTodoLocalFirst(
        _todo('a', 'Gone'),
        scope: RecurringTodoDeleteScope.thisOccurrence,
      );
      serverTodos = [_todoJson('a', 'Gone')];

      await repo.list(limit: 100);

      expect(
        (await repo.listLocal()).map((todo) => todo.id),
        isNot(contains('a')),
      );
    },
  );

  test('server list still refreshes todos without pending changes', () async {
    await db.todosDao.upsertTodo(todoToCompanion(_todo('a', 'Old'), _userId));
    serverTodos = [_todoJson('a', 'Fresh')];

    await repo.list(limit: 100);

    expect((await repo.listLocal()).single.title, 'Fresh');
  });
}
