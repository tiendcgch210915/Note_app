import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/screens/todos/todo_create_screen.dart';

void main() {
  testWidgets('TodoCreateScreen uses the provided initial scheduled date', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TodoCreateScreen(initialScheduledDate: DateTime(2026, 7, 12)),
      ),
    );

    expect(find.text('Việc mới'), findsOneWidget);
    expect(find.text('Ngày làm'), findsOneWidget);
    expect(find.text('12/07/2026'), findsOneWidget);
  });
}
