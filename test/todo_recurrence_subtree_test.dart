import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/data/todos_repository.dart';
import 'package:todonote/models/tag.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/sync/sync_payload.dart';

void main() {
  const userId = 'user-1';

  test(
    'complete local-first clones a tagged three-level subtree once',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = TodosRepository.forTesting(db, userId: userId);
      addTearDown(() async {
        ConnectivitySync.instance.cancelPending();
        await db.close();
      });

      final createdAt = DateTime.utc(2026, 6, 24);
      final parent = Todo(
        id: 'parent',
        title: 'Daily routine',
        scheduledDate: DateTime(2026, 6, 24),
        recurrenceType: 'daily',
        recurrenceInterval: 1,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final child = Todo(
        id: 'child',
        parentId: parent.id,
        title: 'Prepare',
        description: 'Keep metadata',
        position: 1,
        isImportant: true,
        estimatedMinutes: 15,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final grandchild = Todo(
        id: 'grandchild',
        parentId: child.id,
        title: 'Open notebook',
        position: 2,
        triggerAfterTodoId: child.id,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final greatGrandchild = Todo(
        id: 'great-grandchild',
        parentId: grandchild.id,
        title: 'Write first line',
        position: 3,
        triggerAfterTodoId: grandchild.id,
        status: TodoStatus.done,
        actualMinutes: 8,
        completedAt: createdAt,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final tags = [
        Tag(id: 'tag-child', name: 'Child', color: Colors.green),
        Tag(id: 'tag-grandchild', name: 'Grandchild', color: Colors.blue),
      ];

      for (final todo in [parent, child, grandchild, greatGrandchild]) {
        await db.todosDao.upsertTodo(todoToCompanion(todo, userId));
      }
      await db.todosDao.upsertTags(
        tags.map((tag) => tagToCompanion(tag, userId)).toList(),
      );
      await db.todosDao.setTodoTags(child.id, const ['tag-child']);
      await db.todosDao.setTodoTags(grandchild.id, const ['tag-grandchild']);

      final result = await repository.completeLocalFirst(parent);
      final next = result.nextRecurringTodo;
      expect(next, isNotNull);
      expect(next!.scheduledDate, DateTime.utc(2026, 6, 25));

      final cloned = await db.todosDao.getActiveSubtree(
        next.id,
        userId: userId,
      );
      expect(cloned, hasLength(3));
      final clonedChild = cloned.singleWhere((row) => row.title == 'Prepare');
      final clonedGrandchild = cloned.singleWhere(
        (row) => row.title == 'Open notebook',
      );
      final clonedGreatGrandchild = cloned.singleWhere(
        (row) => row.title == 'Write first line',
      );

      expect(clonedChild.parentId, next.id);
      expect(clonedGrandchild.parentId, clonedChild.id);
      expect(clonedGreatGrandchild.parentId, clonedGrandchild.id);
      expect(clonedGrandchild.triggerAfterTodoId, clonedChild.id);
      expect(clonedGreatGrandchild.triggerAfterTodoId, clonedGrandchild.id);
      expect(clonedChild.description, 'Keep metadata');
      expect(clonedChild.isImportant, isTrue);
      expect(clonedChild.estimatedMinutes, 15);
      expect(clonedGreatGrandchild.status, 'open');
      expect(clonedGreatGrandchild.actualMinutes, isNull);
      expect(clonedGreatGrandchild.completedAt, isNull);
      expect(clonedChild.scheduledDate, isNull);
      expect(clonedChild.time, isNull);
      expect(clonedChild.recurrenceType, isNull);
      expect(
        (await db.todosDao.getTagsForTodo(clonedChild.id)).map((tag) => tag.id),
        ['tag-child'],
      );
      expect(
        (await db.todosDao.getTagsForTodo(
          clonedGrandchild.id,
        )).map((tag) => tag.id),
        ['tag-grandchild'],
      );

      final queue = await db.syncDao.getRowsForUser(userId: userId);
      final creates = queue.where((row) => row.operation == 'create').toList();
      expect(creates, hasLength(4));
      expect(creates.first.entityId, next.id);
      expect(SyncPayload.decode(creates[1].payload)['parent_id'], next.id);
      expect(
        SyncPayload.decode(creates[2].payload)['parent_id'],
        clonedChild.id,
      );
      expect(SyncPayload.decode(creates[1].payload)['tag_ids'], ['tag-child']);

      await repository.completeLocalFirst(parent);
      final afterRetry = await db.todosDao.getActiveSubtree(
        next.id,
        userId: userId,
      );
      expect(afterRetry, hasLength(3));
      expect(
        (await db.syncDao.getRowsForUser(
          userId: userId,
        )).where((row) => row.operation == 'create'),
        hasLength(4),
      );
    },
  );

  test(
    'purging duplicate occurrence also removes descendants and tags',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final createdAt = DateTime.utc(2026, 6, 24);
      final rows = [
        Todo(
          id: 'local-parent',
          title: 'Occurrence',
          scheduledDate: DateTime(2026, 6, 25),
          recurrenceType: 'daily',
          recurrenceTemplateId: 'series',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        Todo(
          id: 'local-child',
          parentId: 'local-parent',
          title: 'Child',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        Todo(
          id: 'local-grandchild',
          parentId: 'local-child',
          title: 'Grandchild',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ];
      for (final todo in rows) {
        await db.todosDao.upsertTodo(todoToCompanion(todo, userId));
      }
      final tag = Tag(id: 'tag', name: 'Tag', color: Colors.red);
      await db.todosDao.upsertTag(tagToCompanion(tag, userId));
      await db.todosDao.setTodoTags('local-child', const ['tag']);

      final removed = await db.todosDao.purgeTodoSubtree(
        'local-parent',
        userId: userId,
      );

      expect(
        removed,
        containsAll(['local-parent', 'local-child', 'local-grandchild']),
      );
      expect(await db.todosDao.getTodoById('local-child'), isNull);
      expect(await db.todosDao.getTagsForTodo('local-child'), isEmpty);
    },
  );
}
