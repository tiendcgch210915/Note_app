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

  test('Todo parses tags and tag_ids with old-response fallback', () {
    final tagged = Todo.fromJson(const {
      'id': 'todo-tagged',
      'title': 'Tagged todo',
      'status': 'open',
      'tags': [
        {
          'id': 'tag-1',
          'user_id': 'user-1',
          'name': 'Work',
          'color': '#3366ff',
          'created_at': '2026-06-11T00:00:00.000Z',
          'updated_at': '2026-06-11T00:00:00.000Z',
          'deleted_at': null,
        },
      ],
      'tag_ids': ['tag-1'],
      'created_at': '2026-06-11T00:00:00.000Z',
      'updated_at': '2026-06-11T00:00:00.000Z',
    });
    final legacy = Todo.fromJson(const {
      'id': 'todo-legacy',
      'title': 'Legacy todo',
      'status': 'open',
      'created_at': '2026-06-11T00:00:00.000Z',
      'updated_at': '2026-06-11T00:00:00.000Z',
    });

    expect(tagged.tags.single.name, 'Work');
    expect(tagged.tagIds, ['tag-1']);
    expect(tagged.tagsLoaded, isTrue);
    expect(legacy.tags, isEmpty);
    expect(legacy.tagIds, isEmpty);
    expect(legacy.tagsLoaded, isFalse);
  });
}
