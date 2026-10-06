import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/widgets/todo_tile.dart';

void main() {
  testWidgets('TodoTile shows time before the title', (tester) async {
    final now = DateTime(2026, 6, 26);
    final todo = Todo(
      id: 'todo-time',
      title: 'Đi tập GYM',
      scheduledDate: now,
      time: '09:00',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TodoTile(todo: todo)),
      ),
    );

    expect(find.text('[09:00] Đi tập GYM', findRichText: true), findsOneWidget);
    expect(find.text('09:00'), findsNothing);
  });
}
