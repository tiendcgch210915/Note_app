import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/data/todos_repository.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/sync/sync_payload.dart';

void main() {
  const userId = 'user-1';

  test(
    'reorders direct subtasks local-first and queues sync payloads',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = TodosRepository.forTesting(db, userId: userId);
      addTearDown(() async {
        ConnectivitySync.instance.cancelPending();
        await db.close();
      });

      final createdAt = DateTime.utc(2026, 7);
      for (final todo in [
        _todo('parent', 'Parent', createdAt),
        _todo('a', 'A', createdAt, parentId: 'parent', position: 0),
        _todo('b', 'B', createdAt, parentId: 'parent', position: 1),
        _todo('c', 'C', createdAt, parentId: 'parent', position: 2),
      ]) {
        await db.todosDao.upsertTodo(todoToCompanion(todo, userId));
      }

      await repository.reorderSubtasksLocalFirst(
        parentId: 'parent',
        orderedIds: const ['c', 'a', 'b'],
      );

      final rows = await db.todosDao.getSubtasks('parent');
      expect(rows.map((row) => row.id), ['c', 'a', 'b']);
      expect(rows.map((row) => row.position), [0, 1, 2]);

      final queue = await db.syncDao.getRowsForUser(userId: userId);
      expect(queue, hasLength(3));
      final queuedPositions = {
        for (final row in queue)
          row.entityId: SyncPayload.decode(row.payload)['position'],
      };
      expect(queuedPositions, {'c': 0, 'a': 1, 'b': 2});
    },
  );

  test('completing the last child auto-completes its subtask parent', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TodosRepository.forTesting(db, userId: userId);
    addTearDown(() async {
      ConnectivitySync.instance.cancelPending();
      await db.close();
    });

    final createdAt = DateTime.utc(2026, 7);
    final rows = [
      _todo('root', 'Root', createdAt),
      _todo('group', 'Group', createdAt, parentId: 'root'),
      _todo(
        'done-child',
        'Done child',
        createdAt,
        parentId: 'group',
        status: TodoStatus.done,
        completedAt: createdAt,
      ),
      _todo('open-child', 'Open child', createdAt, parentId: 'group'),
    ];
    for (final todo in rows) {
      await db.todosDao.upsertTodo(todoToCompanion(todo, userId));
    }

    final completed = await repository.completeLocalFirst(rows.last);
    await repository.reconcileSubtaskAncestorsLocalFirst(completed.todo);

    final group = await db.todosDao.getTodoById('group');
    final root = await db.todosDao.getTodoById('root');
    expect(group!.status, TodoStatus.done.backendValue);
    expect(root!.status, TodoStatus.open.backendValue);
  });

  test('uncompleting a child reopens its completed subtask parent', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TodosRepository.forTesting(db, userId: userId);
    addTearDown(() async {
      ConnectivitySync.instance.cancelPending();
      await db.close();
    });

    final createdAt = DateTime.utc(2026, 7);
    final rows = [
      _todo('root', 'Root', createdAt),
      _todo(
        'group',
        'Group',
        createdAt,
        parentId: 'root',
        status: TodoStatus.done,
        completedAt: createdAt,
      ),
      _todo(
        'child-1',
        'Child 1',
        createdAt,
        parentId: 'group',
        status: TodoStatus.done,
        completedAt: createdAt,
      ),
      _todo(
        'child-2',
        'Child 2',
        createdAt,
        parentId: 'group',
        status: TodoStatus.done,
        completedAt: createdAt,
      ),
    ];
    for (final todo in rows) {
      await db.todosDao.upsertTodo(todoToCompanion(todo, userId));
    }

    final reopened = await repository.uncompleteLocalFirst(rows.last);
    await repository.reconcileSubtaskAncestorsLocalFirst(reopened);

    final group = await db.todosDao.getTodoById('group');
    expect(group!.status, TodoStatus.open.backendValue);
  });

  test(
    'local-first done update queues a valid completed_at timestamp',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = TodosRepository.forTesting(db, userId: userId);
      addTearDown(() async {
        ConnectivitySync.instance.cancelPending();
        await db.close();
      });

      final createdAt = DateTime.utc(2026, 7);
      final todo = _todo('todo', 'Todo', createdAt);
      await db.todosDao.upsertTodo(todoToCompanion(todo, userId));

      final updated = await repository.updateLocalFirst(todo, {
        'status': TodoStatus.done.backendValue,
      });

      expect(updated.status, TodoStatus.done);
      expect(updated.completedAt, isNotNull);

      final queue = await db.syncDao.getRowsForUser(userId: userId);
      expect(queue, hasLength(1));
      final payload = SyncPayload.decode(queue.single.payload);
      expect(payload['status'], TodoStatus.done.backendValue);
      expect(payload['completed_at'], isA<String>());
      expect(DateTime.tryParse(payload['completed_at'] as String), isNotNull);
    },
  );
}

Todo _todo(
  String id,
  String title,
  DateTime createdAt, {
  String? parentId,
  int position = 0,
  TodoStatus status = TodoStatus.open,
  DateTime? completedAt,
}) {
  return Todo(
    id: id,
    parentId: parentId,
    title: title,
    position: position,
    status: status,
    completedAt: completedAt,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
