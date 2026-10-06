import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/models/recurring_todo_delete_scope.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/sync_payload.dart';

void main() {
  const userId = 'user-1';
  const deletedAt = '2026-06-17T08:00:00.000Z';

  test('this deletes only selected occurrence and its subtasks', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedSeries(db);

    final deletedIds = await db.todosDao.softDeleteTodoTree(
      'occurrence-17',
      userId,
      deletedAt,
    );

    expect(
      deletedIds,
      containsAll(['occurrence-17', 'child-17', 'grandchild-17']),
    );
    expect(
      (await db.todosDao.getTodoByIdIncludingDeleted(
        'occurrence-17',
      ))?.deletedAt,
      deletedAt,
    );
    expect(
      (await db.todosDao.getTodoByIdIncludingDeleted('child-17'))?.deletedAt,
      deletedAt,
    );
    expect(
      (await db.todosDao.getTodoByIdIncludingDeleted(
        'grandchild-17',
      ))?.deletedAt,
      deletedAt,
    );
    expect(await db.todosDao.getTodoById('occurrence-15'), isNotNull);
    expect(await db.todosDao.getTodoById('occurrence-19'), isNotNull);

    final tombstone = await db.todosDao
        .getOccurrenceForSeriesDateIncludingDeleted(
          'series-root',
          '2026-06-17',
        );
    expect(tombstone?.deletedAt, deletedAt);
    expect(
      await db.todosDao.getOccurrenceForSeriesDate('series-root', '2026-06-17'),
      isNull,
    );
  });

  test('future deletes every status from cutoff and caps recurrence', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedSeries(db);

    final result = await db.todosDao.softDeleteSeriesFromDate(
      seriesId: 'series-root',
      userId: userId,
      fromDateInclusive: '2026-06-17',
      recurrenceEndDate: '2026-06-16',
      deletedAtIso: deletedAt,
    );

    expect(
      result.deletedIds,
      containsAll([
        'occurrence-17',
        'occurrence-19',
        'occurrence-21',
        'child-17',
        'grandchild-17',
        'child-19',
      ]),
    );
    expect(await db.todosDao.getTodoById('series-root'), isNotNull);
    expect(await db.todosDao.getTodoById('occurrence-15'), isNotNull);
    expect(await db.todosDao.getTodoById('occurrence-17'), isNull);
    expect(await db.todosDao.getTodoById('occurrence-19'), isNull);
    expect(await db.todosDao.getTodoById('occurrence-21'), isNull);
    expect(
      (await db.todosDao.getTodoById('series-root'))?.recurrenceEndDate,
      '2026-06-16',
    );
    expect(
      (await db.todosDao.getTodoById('occurrence-15'))?.recurrenceEndDate,
      '2026-06-14',
    );
    expect(result.cappedIds, ['series-root']);
    expect(await db.todosDao.getTodoById('other-series'), isNotNull);
    expect(await db.todosDao.getTodoById('other-user-occurrence'), isNotNull);
  });

  test('all deletes root, all instances and subtasks only in series', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedSeries(db);

    final deletedIds = await db.todosDao.softDeleteEntireSeries(
      seriesId: 'series-root',
      userId: userId,
      deletedAtIso: deletedAt,
    );

    expect(
      deletedIds,
      containsAll([
        'series-root',
        'occurrence-15',
        'occurrence-17',
        'occurrence-19',
        'occurrence-21',
        'child-17',
        'grandchild-17',
        'child-19',
      ]),
    );
    for (final id in deletedIds) {
      expect(await db.todosDao.getTodoById(id), isNull);
    }
    expect(await db.todosDao.getTodoById('other-series'), isNotNull);
    expect(await db.todosDao.getTodoById('other-user-occurrence'), isNotNull);
  });

  test('delete queue keeps selected id and coalesces retries', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    for (final scope in RecurringTodoDeleteScope.values) {
      final payload = SyncPayload.fromTodoDelete(
        id: 'selected-${scope.apiValue}',
        scope: scope,
        deletedAt: deletedAt,
      );
      await db.syncDao.enqueueSyncOp(
        userId: userId,
        entityType: 'todo',
        entityId: payload['id']! as String,
        operation: 'delete',
        payload: SyncPayload.encode(payload),
      );
      await db.syncDao.enqueueSyncOp(
        userId: userId,
        entityType: 'todo',
        entityId: payload['id']! as String,
        operation: 'delete',
        payload: SyncPayload.encode(payload),
      );
    }

    final rows = await db.syncDao.getDueBatch(userId: userId);
    expect(rows, hasLength(3));
    for (final row in rows) {
      final payload = SyncPayload.decode(row.payload);
      expect(row.operation, 'delete');
      expect(payload['id'], row.entityId);
      expect(payload['delete_scope'], isIn(['this', 'future', 'all']));
    }
  });

  test(
    'future delete patches older pending root update instead of adding op',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final rootPayload = {
        'id': 'series-root',
        'recurrence_end_date': null,
        'updated_at': '2026-06-16T08:00:00.000Z',
      };
      await db.syncDao.enqueueSyncOp(
        userId: userId,
        entityType: 'todo',
        entityId: 'series-root',
        operation: 'update',
        payload: SyncPayload.encode(rootPayload),
      );

      await db.syncDao.patchPendingTodoRecurrenceEndDate(
        const ['series-root'],
        userId: userId,
        recurrenceEndDate: '2026-06-16',
        updatedAt: deletedAt,
      );

      final rows = await db.syncDao.getDueBatch(userId: userId);
      expect(rows, hasLength(1));
      final payload = SyncPayload.decode(rows.single.payload);
      expect(payload['recurrence_end_date'], '2026-06-16');
      expect(payload['updated_at'], deletedAt);
    },
  );
}

Future<void> _seedSeries(AppDatabase db) async {
  final rows = [
    _todo(id: 'series-root', date: '2026-06-13', recurrenceTemplateId: null),
    _todo(
      id: 'occurrence-15',
      date: '2026-06-15',
      status: TodoStatus.done,
      recurrenceEndDate: '2026-06-14',
    ),
    _todo(id: 'occurrence-17', date: '2026-06-17'),
    _todo(id: 'occurrence-19', date: '2026-06-19', status: TodoStatus.done),
    _todo(id: 'occurrence-21', date: '2026-06-21'),
    _todo(
      id: 'child-17',
      date: null,
      parentId: 'occurrence-17',
      recurrenceType: null,
      recurrenceTemplateId: null,
    ),
    _todo(
      id: 'child-19',
      date: null,
      parentId: 'occurrence-19',
      recurrenceType: null,
      recurrenceTemplateId: null,
    ),
    _todo(
      id: 'grandchild-17',
      date: null,
      parentId: 'child-17',
      recurrenceType: null,
      recurrenceTemplateId: null,
    ),
    _todo(id: 'other-series', date: '2026-06-17', recurrenceTemplateId: null),
  ];
  for (final todo in rows) {
    await db.todosDao.upsertTodo(todoToCompanion(todo, 'user-1'));
  }
  await db.todosDao.upsertTodo(
    todoToCompanion(
      _todo(id: 'other-user-occurrence', date: '2026-06-19'),
      'user-2',
    ),
  );
}

Todo _todo({
  required String id,
  required String? date,
  String? parentId,
  TodoStatus status = TodoStatus.open,
  String? recurrenceType = 'daily',
  String? recurrenceTemplateId = 'series-root',
  String? recurrenceEndDate,
}) {
  final timestamp = DateTime.utc(2026, 6, 1);
  return Todo(
    id: id,
    parentId: parentId,
    title: id,
    status: status,
    scheduledDate: date == null ? null : DateTime.parse(date),
    recurrenceType: recurrenceType,
    recurrenceInterval: 2,
    recurrenceTemplateId: recurrenceTemplateId,
    recurrenceEndDate: recurrenceEndDate,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
