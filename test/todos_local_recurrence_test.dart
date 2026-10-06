import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/models/todo.dart';

void main() {
  test(
    'local DB finds an existing occurrence by recurrence series and date',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final template = Todo(
        id: 'template-1',
        title: 'Daily review',
        scheduledDate: DateTime(2026, 6, 18),
        recurrenceType: 'daily',
        recurrenceInterval: 1,
        createdAt: DateTime.utc(2026, 6, 18),
        updatedAt: DateTime.utc(2026, 6, 18),
      );
      final occurrence = Todo(
        id: 'occurrence-1',
        title: 'Daily review',
        scheduledDate: DateTime(2026, 6, 19),
        recurrenceType: 'daily',
        recurrenceInterval: 1,
        recurrenceTemplateId: 'template-1',
        createdAt: DateTime.utc(2026, 6, 18),
        updatedAt: DateTime.utc(2026, 6, 18),
      );

      await db.todosDao.upsertTodo(todoToCompanion(template, 'user-1'));
      await db.todosDao.upsertTodo(todoToCompanion(occurrence, 'user-1'));

      final sameDate = await db.todosDao.getOccurrenceForSeriesDate(
        'template-1',
        '2026-06-19',
      );
      final templateDate = await db.todosDao.getOccurrenceForSeriesDate(
        'template-1',
        '2026-06-18',
      );

      expect(sameDate?.id, 'occurrence-1');
      expect(templateDate?.id, 'template-1');
    },
  );
}
