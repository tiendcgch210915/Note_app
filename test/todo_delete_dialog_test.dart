import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/recurring_todo_delete_scope.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/utils/todo_delete_dialog.dart';

void main() {
  testWidgets('recurring delete choices map to typed future scope', (
    tester,
  ) async {
    RecurringTodoDeleteScope? selected;
    final todo = Todo(
      id: 'todo-1',
      title: 'Recurring',
      scheduledDate: DateTime(2026, 6, 17),
      recurrenceType: 'daily',
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showTodoDeleteScopeDialog(context, todo);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Lần này thôi'), findsOneWidget);
    expect(find.text('Lần này và sau'), findsOneWidget);
    expect(find.text('Tất cả'), findsOneWidget);

    await tester.tap(find.text('Lần này và sau'));
    await tester.pumpAndSettle();
    expect(selected, RecurringTodoDeleteScope.thisAndFuture);
    expect(selected?.apiValue, 'future');
  });

  testWidgets('cancel returns no delete scope', (tester) async {
    RecurringTodoDeleteScope? selected = RecurringTodoDeleteScope.all;
    final todo = Todo(
      id: 'todo-1',
      title: 'Single',
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showTodoDeleteScopeDialog(context, todo);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });
}
