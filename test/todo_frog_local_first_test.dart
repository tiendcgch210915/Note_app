import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/api_exception.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/data/todos_repository.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/sync/sync_payload.dart';

void main() {
  const userId = 'user-1';
  final createdAt = DateTime.utc(2026, 7, 1, 8);

  Future<({AppDatabase db, TodosRepository repository})> setup() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      ConnectivitySync.instance.cancelPending();
      await db.close();
    });
    return (db: db, repository: TodosRepository.forTesting(db, userId: userId));
  }

  test(
    'setting frog local-first enforces important urgent and clears old frog',
    () async {
      final env = await setup();
      final date = DateTime(2026, 7, 7);
      final oldFrog = _todo(
        'a',
        'Old frog',
        createdAt,
        scheduledDate: date,
        isFrog: true,
        frogDate: date,
        isImportant: true,
        isUrgent: true,
      );
      final nextFrog = _todo(
        'b',
        'Next frog',
        createdAt,
        scheduledDate: date,
        isImportant: false,
        isUrgent: false,
      );
      await env.db.todosDao.upsertTodo(todoToCompanion(oldFrog, userId));
      await env.db.todosDao.upsertTodo(todoToCompanion(nextFrog, userId));

      final updated = await env.repository.setTodoFrogLocalFirst(
        nextFrog,
        enabled: true,
      );

      expect(updated.isFrog, isTrue);
      expect(updated.frogDate, date);
      expect(updated.isImportant, isTrue);
      expect(updated.isUrgent, isTrue);
      final oldRow = await env.db.todosDao.getTodoById(oldFrog.id);
      final newRow = await env.db.todosDao.getTodoById(nextFrog.id);
      expect(oldRow!.isFrog, isFalse);
      expect(oldRow.frogDate, isNull);
      expect(newRow!.isFrog, isTrue);
      expect(newRow.frogDate, '2026-07-07');
      expect(newRow.isImportant, isTrue);
      expect(newRow.isUrgent, isTrue);

      final queue = await env.db.syncDao.getRowsForUser(userId: userId);
      final payloads = {
        for (final row in queue) row.entityId: SyncPayload.decode(row.payload),
      };
      expect(payloads['a']!['is_frog'], isFalse);
      expect(payloads['a']!['frog_date'], isNull);
      expect(payloads['b']!['is_frog'], isTrue);
      expect(payloads['b']!['frog_date'], '2026-07-07');
      expect(payloads['b']!['is_important'], isTrue);
      expect(payloads['b']!['is_urgent'], isTrue);
    },
  );

  test('turning frog off keeps important and urgent editable values', () async {
    final env = await setup();
    final date = DateTime(2026, 7, 7);
    final frog = _todo(
      'frog',
      'Frog',
      createdAt,
      scheduledDate: date,
      isFrog: true,
      frogDate: date,
      isImportant: true,
      isUrgent: true,
    );
    await env.db.todosDao.upsertTodo(todoToCompanion(frog, userId));

    final updated = await env.repository.setTodoFrogLocalFirst(
      frog,
      enabled: false,
    );

    expect(updated.isFrog, isFalse);
    expect(updated.frogDate, isNull);
    expect(updated.isImportant, isTrue);
    expect(updated.isUrgent, isTrue);
    final row = await env.db.todosDao.getTodoById(frog.id);
    expect(row!.isFrog, isFalse);
    expect(row.frogDate, isNull);
    expect(row.isImportant, isTrue);
    expect(row.isUrgent, isTrue);
  });

  test('frog cannot be enabled without scheduled date', () async {
    final env = await setup();
    final floating = _todo('floating', 'Floating', createdAt);
    await env.db.todosDao.upsertTodo(todoToCompanion(floating, userId));

    await expectLater(
      env.repository.setTodoFrogLocalFirst(floating, enabled: true),
      throwsA(isA<ApiException>()),
    );
    final row = await env.db.todosDao.getTodoById(floating.id);
    expect(row!.isFrog, isFalse);
    expect(row.frogDate, isNull);
  });

  test(
    'moving a frog updates frog date and clears frog on the new day',
    () async {
      final env = await setup();
      final oldDate = DateTime(2026, 7, 7);
      final newDate = DateTime(2026, 7, 8);
      final moving = _todo(
        'moving',
        'Moving frog',
        createdAt,
        scheduledDate: oldDate,
        isFrog: true,
        frogDate: oldDate,
        isImportant: true,
        isUrgent: true,
      );
      final conflict = _todo(
        'conflict',
        'Conflict frog',
        createdAt,
        scheduledDate: newDate,
        isFrog: true,
        frogDate: newDate,
        isImportant: true,
        isUrgent: true,
      );
      await env.db.todosDao.upsertTodo(todoToCompanion(moving, userId));
      await env.db.todosDao.upsertTodo(todoToCompanion(conflict, userId));

      final updated = await env.repository.updateLocalFirst(moving, const {
        'scheduled_date': '2026-07-08',
      });

      expect(updated.isFrog, isTrue);
      expect(updated.frogDate, newDate);
      expect(updated.isImportant, isTrue);
      expect(updated.isUrgent, isTrue);
      final conflictRow = await env.db.todosDao.getTodoById(conflict.id);
      expect(conflictRow!.isFrog, isFalse);
      expect(conflictRow.frogDate, isNull);
    },
  );

  test('clearing scheduled date clears frog and time', () async {
    final env = await setup();
    final date = DateTime(2026, 7, 7);
    final frog = _todo(
      'frog',
      'Frog',
      createdAt,
      scheduledDate: date,
      time: '09:00',
      isFrog: true,
      frogDate: date,
      isImportant: true,
      isUrgent: true,
    );
    await env.db.todosDao.upsertTodo(todoToCompanion(frog, userId));

    final updated = await env.repository.updateLocalFirst(frog, const {
      'scheduled_date': null,
    });

    expect(updated.scheduledDate, isNull);
    expect(updated.time, isNull);
    expect(updated.isFrog, isFalse);
    expect(updated.frogDate, isNull);
    final row = await env.db.todosDao.getTodoById(frog.id);
    expect(row!.scheduledDate, isNull);
    expect(row.time, isNull);
    expect(row.isFrog, isFalse);
    expect(row.frogDate, isNull);
  });
}

Todo _todo(
  String id,
  String title,
  DateTime createdAt, {
  DateTime? scheduledDate,
  String? time,
  bool isFrog = false,
  DateTime? frogDate,
  bool? isImportant,
  bool? isUrgent,
}) {
  return Todo(
    id: id,
    title: title,
    scheduledDate: scheduledDate,
    time: time,
    isFrog: isFrog,
    frogDate: frogDate,
    isImportant: isImportant,
    isUrgent: isUrgent,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
