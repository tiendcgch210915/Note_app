import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/widgets/todo_tile.dart';

void main() {
  Todo build({String? type, String? days, String? templateId}) {
    final now = DateTime(2026, 6, 26);
    return Todo(
      id: 'todo',
      title: 'Ôn bài',
      scheduledDate: now,
      recurrenceType: type,
      recurrenceInterval: 1,
      recurrenceDaysOfWeek: days,
      recurrenceTemplateId: templateId,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> pumpTile(WidgetTester tester, Todo todo) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TodoTile(todo: todo)),
      ),
    );
  }

  testWidgets('the next occurrence shows the original repeat rule', (
    tester,
  ) async {
    await pumpTile(tester, build(type: 'daily', templateId: 'template'));

    expect(find.text('Mỗi ngày'), findsOneWidget);
    expect(find.text('Lặp lại'), findsNothing);
  });

  testWidgets('a weekday rule is shown on the next occurrence too', (
    tester,
  ) async {
    await pumpTile(
      tester,
      build(type: 'weekly', days: '2', templateId: 'template'),
    );

    expect(find.text('T3'), findsOneWidget);
  });

  testWidgets(
    'a legacy projection without its own rule keeps the generic chip',
    (tester) async {
      await pumpTile(tester, build(templateId: 'template'));

      expect(find.text('Lặp lại'), findsOneWidget);
    },
  );
}
