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

  test('Todo parses and clears habit_id', () {
    final todo = Todo.fromJson(const {
      'id': 'todo-habit',
      'title': 'Linked todo',
      'status': 'open',
      'habit_id': 'habit-1',
      'created_at': '2026-06-11T00:00:00.000Z',
      'updated_at': '2026-06-11T00:00:00.000Z',
    });

    expect(todo.habitId, 'habit-1');
    expect(
      todo.toUpdateJson(habitId: 'habit-2'),
      containsPair('habit_id', 'habit-2'),
    );
    expect(todo.toUpdateJson(clearHabit: true), containsPair('habit_id', null));
  });

  test('Todo parses nullable local wall-clock time', () {
    final timed = Todo.fromJson(const {
      'id': 'todo-time',
      'title': 'Deep work',
      'status': 'open',
      'scheduled_date': '2026-06-20',
      'time': '08:30',
      'created_at': '2026-06-20T00:00:00.000Z',
      'updated_at': '2026-06-20T00:00:00.000Z',
    });
    final legacy = Todo.fromJson(const {
      'id': 'todo-legacy',
      'title': 'Legacy',
      'status': 'open',
      'created_at': '2026-06-20T00:00:00.000Z',
      'updated_at': '2026-06-20T00:00:00.000Z',
    });
    final subtask = Todo.fromJson(const {
      'id': 'todo-child',
      'parent_id': 'todo-time',
      'title': 'Child',
      'status': 'open',
      'time': '08:30',
      'created_at': '2026-06-20T00:00:00.000Z',
      'updated_at': '2026-06-20T00:00:00.000Z',
    });

    expect(timed.time, '08:30');
    expect(legacy.time, isNull);
    expect(subtask.time, isNull);
    expect(timed.toUpdateJson(time: '09:00'), containsPair('time', '09:00'));
    expect(timed.toUpdateJson(clearTime: true), containsPair('time', null));
    expect(
      timed.toUpdateJson(clearScheduledDate: true),
      containsPair('time', null),
    );
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

  test(
    'Todo parses next recurring todo recurrence fields from complete response',
    () {
      final completeResponse = {
        'todo': {
          'id': 'todo-1',
          'title': 'Daily todo',
          'status': 'done',
          'scheduled_date': '2026-06-18',
          'recurrence_type': 'daily',
          'recurrence_interval': 1,
          'created_at': '2026-06-18T00:00:00.000Z',
          'updated_at': '2026-06-18T00:00:00.000Z',
        },
        'triggered_todos': const [],
        'next_recurring_todo': {
          'id': 'todo-2',
          'title': 'Daily todo',
          'status': 'open',
          'scheduled_date': '2026-06-19',
          'completed_at': null,
          'actual_minutes': null,
          'habit_id': 'habit-1',
          'recurrence_type': 'daily',
          'recurrence_interval': 1,
          'recurrence_days_of_week': null,
          'recurrence_end_date': '2026-06-30',
          'recurrence_template_id': 'todo-1',
          'created_at': '2026-06-18T00:00:00.000Z',
          'updated_at': '2026-06-18T00:00:00.000Z',
        },
      };

      final next = Todo.fromJson(
        completeResponse['next_recurring_todo']! as Map<String, dynamic>,
      );

      expect(next.id, 'todo-2');
      expect(next.status, TodoStatus.open);
      expect(next.scheduledDate, DateTime(2026, 6, 19));
      expect(next.habitId, 'habit-1');
      expect(next.recurrenceType, 'daily');
      expect(next.recurrenceTemplateId, 'todo-1');
      expect(next.completedAt, isNull);
      expect(next.actualMinutes, isNull);
    },
  );
}
