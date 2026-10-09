import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/data/todos_repository.dart';
import 'package:todonote/models/recurring_todo_delete_scope.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/sync/sync_payload.dart';

/// Completing a recurring todo creates its next occurrence. Undoing the
/// completion and completing again (or rescheduling in between, or tapping
/// twice) must never leave two live occurrences for the same slot.
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

  Future<Todo> insertSeries({
    String title = 'Daily review',
    int interval = 1,
    String? endDate,
  }) async {
    final root = Todo(
      id: seriesId,
      title: title,
      scheduledDate: DateTime(2026, 6, 24),
      recurrenceType: 'daily',
      recurrenceInterval: interval,
      recurrenceEndDate: endDate,
      createdAt: DateTime.utc(2026, 6, 24),
      updatedAt: DateTime.utc(2026, 6, 24),
    );
    await db.todosDao.upsertTodo(todoToCompanion(root, userId));
    return root;
  }

  Future<List<TodoRow>> liveRows() async {
    final rows = await db.todosDao.getSeriesRows(seriesId, userId: userId);
    return rows.where((row) => row.deletedAt == null).toList();
  }

  Future<List<TodoRow>> rowsOn(String date) async =>
      (await liveRows()).where((row) => row.scheduledDate == date).toList();

  test(
    'complete, undo, complete again reuses the same next occurrence',
    () async {
      final root = await insertSeries();

      final first = await repository.completeLocalFirst(root);
      final next = first.nextRecurringTodo;
      expect(next, isNotNull);
      expect(await liveRows(), hasLength(2));

      final reopened = await repository.uncompleteLocalFirst(first.todo);
      expect(reopened.status, TodoStatus.open);
      final parked = await db.todosDao.getTodoById(next!.id);
      expect(parked!.status, TodoStatus.archived.backendValue);
      expect(parked.deletedAt, isNull);
      expect(await liveRows(), hasLength(2));

      final second = await repository.completeLocalFirst(reopened);
      expect(second.nextRecurringTodo!.id, next.id);
      expect(second.nextRecurringTodo!.status, TodoStatus.open);
      expect(await liveRows(), hasLength(2));
      expect(await rowsOn('2026-06-25'), hasLength(1));

      // The undo/redo cycle can go on without ever adding a row.
      final again = await repository.uncompleteLocalFirst(second.todo);
      await repository.completeLocalFirst(again);
      expect(await liveRows(), hasLength(2));
      expect((await db.todosDao.getTodoById(next.id))!.status, 'open');
    },
  );

  test(
    'the undo hides the generated occurrence and is not a deletion',
    () async {
      final root = await insertSeries();
      final first = await repository.completeLocalFirst(root);

      await repository.uncompleteLocalFirst(first.todo);

      final openRows = (await liveRows())
          .where((row) => row.status == TodoStatus.open.backendValue)
          .toList();
      expect(openRows.map((row) => row.id), [seriesId]);

      // Nothing is deleted. The parked state travels as a plain update; the
      // outbox merges it into the occurrence's still-pending create.
      final queue = await db.syncDao.getRowsForUser(userId: userId);
      expect(queue.where((row) => row.operation == 'delete'), isEmpty);
      final nextOp = queue.singleWhere(
        (row) => row.entityId == first.nextRecurringTodo!.id,
      );
      expect(SyncPayload.decode(nextOp.payload)['status'], 'archived');
    },
  );

  test('rescheduling the reopened todo moves the parked occurrence', () async {
    final root = await insertSeries();
    final first = await repository.completeLocalFirst(root);
    final nextId = first.nextRecurringTodo!.id;
    final reopened = await repository.uncompleteLocalFirst(first.todo);

    // Later than the parked occurrence's own date (2026-06-25).
    final moved = await repository.updateLocalFirst(reopened, const {
      'scheduled_date': '2026-06-30',
    });
    final second = await repository.completeLocalFirst(moved);

    expect(second.nextRecurringTodo!.id, nextId);
    expect(await liveRows(), hasLength(2));
    expect(await rowsOn('2026-06-25'), isEmpty);
    final revived = await db.todosDao.getTodoById(nextId);
    expect(revived!.scheduledDate, '2026-07-01');
    expect(revived.status, 'open');
  });

  test('a next occurrence the user moved is kept and reused', () async {
    final root = await insertSeries();
    final first = await repository.completeLocalFirst(root);
    final next = first.nextRecurringTodo!;
    await repository.updateLocalFirst(next, const {
      'scheduled_date': '2026-06-27',
    });

    final reopened = await repository.uncompleteLocalFirst(first.todo);
    expect((await db.todosDao.getTodoById(next.id))!.status, 'open');

    final second = await repository.completeLocalFirst(reopened);
    expect(second.nextRecurringTodo!.id, next.id);
    expect(await liveRows(), hasLength(2));
  });

  test('undoing an old completion leaves later occurrences alone', () async {
    final root = await insertSeries();
    final first = await repository.completeLocalFirst(root);
    final second = await repository.completeLocalFirst(
      first.nextRecurringTodo!,
    );
    final third = second.nextRecurringTodo!;
    expect(await liveRows(), hasLength(3));

    await repository.uncompleteLocalFirst(first.todo);

    expect(
      (await db.todosDao.getTodoById(first.nextRecurringTodo!.id))!.status,
      'done',
    );
    expect((await db.todosDao.getTodoById(third.id))!.status, 'open');
    expect(await liveRows(), hasLength(3));
  });

  test('tapping twice creates a single next occurrence', () async {
    final root = await insertSeries();

    final results = await Future.wait([
      repository.completeLocalFirst(root),
      repository.completeLocalFirst(root),
    ]);

    expect(await liveRows(), hasLength(2));
    expect(await rowsOn('2026-06-25'), hasLength(1));
    final ids = results
        .map((result) => result.nextRecurringTodo?.id)
        .whereType<String>()
        .toSet();
    expect(ids, hasLength(1));
  });

  test('completing a todo that is already done adds nothing', () async {
    final root = await insertSeries();
    final first = await repository.completeLocalFirst(root);
    expect(await liveRows(), hasLength(2));

    // A stale screen still holds the open copy.
    final stale = await repository.completeLocalFirst(root);

    expect(stale.nextRecurringTodo, isNull);
    expect(await liveRows(), hasLength(2));
    expect(first.nextRecurringTodo, isNotNull);
  });

  test(
    'deleting the reopened occurrence revives the parked one without skipping its date',
    () async {
      final root = await insertSeries();
      final first = await repository.completeLocalFirst(root);
      final nextId = first.nextRecurringTodo!.id;
      final reopened = await repository.uncompleteLocalFirst(first.todo);

      await repository.deleteTodoLocalFirst(
        reopened,
        scope: RecurringTodoDeleteScope.thisOccurrence,
      );

      final live = await liveRows();
      expect(live.map((row) => row.id), [nextId]);
      expect(live.single.status, 'open');
      expect(live.single.scheduledDate, '2026-06-25');
    },
  );

  test(
    'the whole cycle queues exactly one create for the next occurrence',
    () async {
      final root = await insertSeries();
      final first = await repository.completeLocalFirst(root);
      final reopened = await repository.uncompleteLocalFirst(first.todo);
      await repository.completeLocalFirst(reopened);

      final queue = await db.syncDao.getRowsForUser(userId: userId);
      final creates = queue.where((row) => row.operation == 'create').toList();
      expect(creates, hasLength(1));
      expect(creates.single.entityId, first.nextRecurringTodo!.id);
      // After the redo the pending create carries the live (open) state again.
      expect(SyncPayload.decode(creates.single.payload)['status'], 'open');
    },
  );

  test('a series without a next date never parks anything', () async {
    final root = await insertSeries(endDate: '2026-06-24');
    final first = await repository.completeLocalFirst(root);
    expect(first.nextRecurringTodo, isNull);

    final reopened = await repository.uncompleteLocalFirst(first.todo);
    final again = await repository.completeLocalFirst(reopened);

    expect(again.nextRecurringTodo, isNull);
    expect(await liveRows(), hasLength(1));
  });
}
