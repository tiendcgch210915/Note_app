import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/todo.dart';

void main() {
  test('Todo parses trigger_after_todo_id from backend JSON', () {
    final todo = Todo.fromJson(const {
      'id': 'todo-b',
      'title': 'Todo B',
      'status': 'open',
      'trigger_after_todo_id': 'todo-a',
      'created_at': '2026-06-11T00:00:00.000Z',
      'updated_at': '2026-06-11T00:00:00.000Z',
    });

    expect(todo.triggerAfterTodoId, 'todo-a');
  });

  test('Todo update JSON can clear trigger_after_todo_id', () {
    final todo = Todo(
      id: 'todo-b',
      title: 'Todo B',
      triggerAfterTodoId: 'todo-a',
      createdAt: DateTime.utc(2026, 6, 11),
      updatedAt: DateTime.utc(2026, 6, 11),
    );

    final body = todo.toUpdateJson(clearTriggerAfterTodo: true);

    expect(body, containsPair('trigger_after_todo_id', null));
  });
}
