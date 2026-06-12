import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/sync/sync_payload.dart';

void main() {
  const iso = '2026-06-05T08:00:00.000Z';

  test('pushOperation uses backend wire contract', () {
    final op = SyncPayload.pushOperation(
      op: 'create',
      type: 'todo',
      payload: {'id': 'todo-1', 'updated_at': iso},
    );
    final body = {
      'operations': [op],
    };

    expect(body['operations'], hasLength(1));
    expect(op['op'], 'create');
    expect(op['type'], 'todo');
    expect(op['payload'], containsPair('id', 'todo-1'));
    expect(op, isNot(contains('operation')));
    expect(op, isNot(contains('entity_type')));
    expect(op, isNot(contains('entity_id')));
  });

  test('habit payload omits server-only streak fields', () {
    final payload = SyncPayload.fromHabit(
      const HabitRow(
        id: 'habit-1',
        userId: 'user-1',
        title: 'Read',
        color: '#4CAF50',
        frequencyType: 'daily',
        targetPerPeriod: 1,
        startDate: '2026-06-05',
        currentStreak: 7,
        longestStreak: 10,
        isArchived: false,
        createdAt: iso,
        updatedAt: iso,
      ),
    );

    expect(payload['is_archived'], isFalse);
    expect(payload['updated_at'], endsWith('Z'));
    expect(payload, isNot(contains('current_streak')));
    expect(payload, isNot(contains('longest_streak')));
  });

  test('checklist template payload omits server-only fields', () {
    final payload = SyncPayload.fromTemplate(
      const TemplateRow(
        id: 'template-1',
        userId: 'user-1',
        title: 'Morning',
        isSystem: true,
        sortOrder: 7,
        timesUsed: 3,
        lastUsedAt: iso,
        createdAt: iso,
        updatedAt: iso,
      ),
    );

    expect(payload, isNot(contains('is_system')));
    expect(payload['sort_order'], 7);
    expect(payload, isNot(contains('times_used')));
    expect(payload, isNot(contains('last_used_at')));
  });

  test('checklist template order payload matches sync contract', () {
    final payload = SyncPayload.fromTemplateOrder(
      const TemplateOrderRow(
        id: 'order-1',
        userId: 'user-1',
        templateId: 'template-1',
        sortOrder: 2,
        createdAt: iso,
        updatedAt: iso,
      ),
    );

    expect(payload['id'], 'order-1');
    expect(payload['template_id'], 'template-1');
    expect(payload['sort_order'], 2);
    expect(payload['deleted_at'], isNull);
  });

  test('checklist run payload includes created_at and started_at', () {
    final payload = SyncPayload.fromRun(
      const RunRow(
        id: 'run-1',
        templateId: 'template-1',
        userId: 'user-1',
        status: 'in_progress',
        completedAt: null,
        durationMs: 90000,
        createdAt: iso,
        updatedAt: iso,
      ),
    );

    expect(payload['started_at'], iso);
    expect(payload['created_at'], iso);
    expect(payload['duration_ms'], 90000);
  });

  test(
    'checklist run item payload includes completed_at only as contract field',
    () {
      final payload = SyncPayload.fromRunItem(
        const RunItemRow(
          id: 'run-item-1',
          runId: 'run-1',
          templateItemId: 'template-item-1',
          title: 'Ignored snapshot',
          isRequired: true,
          status: 'done',
          completedAt: iso,
          note: 'done',
          orderIndex: 2,
          createdAt: iso,
          updatedAt: iso,
        ),
      );

      expect(payload['completed_at'], iso);
      expect(payload, isNot(contains('title')));
      expect(payload, isNot(contains('is_required')));
      expect(payload, isNot(contains('position')));
      expect(payload, isNot(contains('order_index')));
    },
  );

  test('todo payload includes nullable habit-stacking trigger field', () {
    final payload = SyncPayload.fromTodo(
      const TodoRow(
        id: 'todo-b',
        userId: 'user-1',
        title: 'Todo B',
        status: 'open',
        position: 0,
        isFrog: false,
        triggerAfterTodoId: 'todo-a',
        createdAt: iso,
        updatedAt: iso,
      ),
      const [],
      const [],
    );

    expect(payload['trigger_after_todo_id'], 'todo-a');
  });

  test('todo payload sends tag_ids as full replacement', () {
    final payload = SyncPayload.fromTodo(
      const TodoRow(
        id: 'todo-tagged',
        userId: 'user-1',
        title: 'Tagged',
        status: 'open',
        position: 0,
        isFrog: false,
        createdAt: iso,
        updatedAt: iso,
      ),
      const ['tag-1', 'tag-2'],
      const [],
    );

    expect(payload['tag_ids'], ['tag-1', 'tag-2']);
  });

  test('subtask todo payload strips parent-owned metadata', () {
    final payload = SyncPayload.fromTodo(
      const TodoRow(
        id: 'child-1',
        userId: 'user-1',
        parentId: 'parent-1',
        title: 'Child task',
        description: 'Ignored',
        status: 'done',
        position: 2,
        isFrog: true,
        frogDate: '2026-06-05',
        isImportant: true,
        isUrgent: true,
        estimatedMinutes: 45,
        actualMinutes: 30,
        startAt: iso,
        dueAt: iso,
        scheduledDate: '2026-06-05',
        triggerAfterTodoId: 'todo-a',
        completedAt: iso,
        recurrenceType: 'daily',
        recurrenceInterval: 1,
        recurrenceWeekdays: '1,2,3',
        recurrenceEndDate: '2026-07-01',
        recurrenceTemplateId: 'template-1',
        createdAt: iso,
        updatedAt: iso,
      ),
      const ['tag-1'],
      const ['note-1'],
    );

    expect(payload['parent_id'], 'parent-1');
    expect(payload['title'], 'Child task');
    expect(payload['status'], 'done');
    expect(payload['completed_at'], iso);
    expect(payload['description'], isNull);
    expect(payload['is_frog'], isFalse);
    expect(payload['frog_date'], isNull);
    expect(payload['is_important'], isNull);
    expect(payload['is_urgent'], isNull);
    expect(payload['estimated_minutes'], isNull);
    expect(payload['actual_minutes'], isNull);
    expect(payload['scheduled_date'], isNull);
    expect(payload['trigger_after_todo_id'], isNull);
    expect(payload['recurrence_type'], isNull);
    expect(payload['recurrence_interval'], isNull);
    expect(payload['tag_ids'], isEmpty);
    expect(payload['linked_note_ids'], isEmpty);
  });
}
