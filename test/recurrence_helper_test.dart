import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/tag.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/utils/recurrence_helper.dart';

void main() {
  test('nextDateAfterCompletedTodo handles daily and custom intervals', () {
    final daily = Todo(
      id: 'daily-1',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 15),
      recurrenceType: 'daily',
      recurrenceInterval: 2,
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );
    final custom = Todo(
      id: 'custom-1',
      title: 'Custom review',
      scheduledDate: DateTime(2026, 6, 15),
      recurrenceType: 'custom',
      recurrenceInterval: 3,
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(daily),
      DateTime.utc(2026, 6, 17),
    );
    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(custom),
      DateTime.utc(2026, 6, 18),
    );
  });

  test('nextDateAfterCompletedTodo handles weekly ISO weekdays', () {
    final sameWeek = Todo(
      id: 'weekly-1',
      title: 'Weekly review',
      scheduledDate: DateTime(2026, 6, 17), // Wednesday
      recurrenceType: 'weekly',
      recurrenceInterval: 1,
      recurrenceDaysOfWeek: '1,3,5',
      createdAt: DateTime.utc(2026, 6, 17),
      updatedAt: DateTime.utc(2026, 6, 17),
    );
    final nextCycle = Todo(
      id: 'weekly-2',
      title: 'Weekly review',
      scheduledDate: DateTime(2026, 6, 19), // Friday
      recurrenceType: 'weekly',
      recurrenceInterval: 2,
      recurrenceDaysOfWeek: '1,3,5',
      createdAt: DateTime.utc(2026, 6, 19),
      updatedAt: DateTime.utc(2026, 6, 19),
    );
    final fallback = Todo(
      id: 'weekly-3',
      title: 'Weekly review',
      scheduledDate: DateTime(2026, 6, 17),
      recurrenceType: 'weekly',
      recurrenceInterval: 2,
      createdAt: DateTime.utc(2026, 6, 17),
      updatedAt: DateTime.utc(2026, 6, 17),
    );

    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(sameWeek),
      DateTime.utc(2026, 6, 19),
    );
    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(nextCycle),
      DateTime.utc(2026, 6, 29),
    );
    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(fallback),
      DateTime.utc(2026, 7, 1),
    );
  });

  test('nextDateAfterCompletedTodo respects recurrence end date', () {
    final todo = Todo(
      id: 'daily-end',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 15),
      recurrenceType: 'daily',
      recurrenceInterval: 1,
      recurrenceEndDate: '2026-06-15',
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    expect(RecurrenceHelper.nextDateAfterCompletedTodo(todo), isNull);
  });

  test('nextDateOnOrAfter skips missed daily occurrences', () {
    final todo = Todo(
      id: 'legacy-daily',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 10),
      recurrenceType: 'daily',
      recurrenceInterval: 2,
      createdAt: DateTime.utc(2026, 6, 10),
      updatedAt: DateTime.utc(2026, 6, 10),
    );

    expect(
      RecurrenceHelper.nextDateOnOrAfter(
        todo: todo,
        minimumDate: DateTime(2026, 6, 17),
      ),
      DateTime.utc(2026, 6, 18),
    );
  });

  test('nextDateOnOrAfter stops when legacy series has ended', () {
    final todo = Todo(
      id: 'legacy-ended',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 10),
      recurrenceType: 'daily',
      recurrenceInterval: 1,
      recurrenceEndDate: '2026-06-15',
      createdAt: DateTime.utc(2026, 6, 10),
      updatedAt: DateTime.utc(2026, 6, 10),
    );

    expect(
      RecurrenceHelper.nextDateOnOrAfter(
        todo: todo,
        minimumDate: DateTime(2026, 6, 17),
      ),
      isNull,
    );
  });

  test('nextDateSkippingExceptions never recreates deleted occurrence', () {
    final todo = Todo(
      id: 'daily-exception',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 17),
      recurrenceType: 'daily',
      recurrenceInterval: 1,
      createdAt: DateTime.utc(2026, 6, 17),
      updatedAt: DateTime.utc(2026, 6, 17),
    );

    expect(
      RecurrenceHelper.nextDateSkippingExceptions(
        todo: todo,
        exceptionDates: const {'2026-06-18', '2026-06-19'},
      ),
      DateTime.utc(2026, 6, 20),
    );
  });

  test(
    'buildNextAfterCompletion copies recurrence data and resets completion',
    () {
      final tag = Tag(
        id: 'tag-1',
        name: 'Work',
        color: const Color(0xFF3366FF),
      );
      final source = Todo(
        id: 'todo-1',
        title: 'Daily habit todo',
        description: 'Original description',
        status: TodoStatus.done,
        scheduledDate: DateTime(2026, 6, 15),
        dueAt: DateTime.utc(2026, 6, 15, 23, 59),
        isFrog: true,
        frogDate: DateTime(2026, 6, 15),
        isImportant: true,
        isUrgent: false,
        estimatedMinutes: 15,
        actualMinutes: 12,
        habitId: 'habit-1',
        tags: [tag],
        tagIds: const ['tag-1'],
        tagsLoaded: true,
        completedAt: DateTime.utc(2026, 6, 15, 8),
        recurrenceType: 'daily',
        recurrenceInterval: 1,
        recurrenceEndDate: '2026-06-30',
        createdAt: DateTime.utc(2026, 6, 15),
        updatedAt: DateTime.utc(2026, 6, 15),
      );

      final next = RecurrenceHelper.buildNextAfterCompletion(
        source: source,
        scheduledDate: DateTime.utc(2026, 6, 16),
        templateId: source.id,
        overrideId: 'next-1',
        tags: [tag],
        tagIds: const ['tag-1'],
      );

      expect(next.id, 'next-1');
      expect(next.status, TodoStatus.open);
      expect(next.completedAt, isNull);
      expect(next.actualMinutes, isNull);
      expect(next.scheduledDate, DateTime.utc(2026, 6, 16));
      expect(next.dueAt, DateTime.utc(2026, 6, 16, 23, 59));
      expect(next.habitId, 'habit-1');
      expect(next.tagIds, ['tag-1']);
      expect(next.recurrenceType, 'daily');
      expect(next.recurrenceTemplateId, source.id);
    },
  );

  test('buildInstance sets dueAt to the same date end of day', () {
    final template = Todo(
      id: 'template-1',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 15),
      recurrenceType: 'daily',
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    final instance = RecurrenceHelper.buildInstance(
      template: template,
      date: DateTime.utc(2026, 6, 16),
      overrideId: 'instance-1',
    );

    expect(instance.scheduledDate, DateTime.utc(2026, 6, 16));
    expect(instance.dueAt, DateTime.utc(2026, 6, 16, 23, 59));
    expect(instance.recurrenceTemplateId, 'template-1');
    expect(instance.recurrenceType, isNull);
  });

  test('buildInstance copies template tags', () {
    final tag = Tag(id: 'tag-1', name: 'Work', color: const Color(0xFF3366FF));
    final template = Todo(
      id: 'template-1',
      title: 'Daily review',
      recurrenceType: 'daily',
      tags: [tag],
      tagIds: const ['tag-1'],
      tagsLoaded: true,
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    final instance = RecurrenceHelper.buildInstance(
      template: template,
      date: DateTime.utc(2026, 6, 16),
    );

    expect(instance.tags, [tag]);
    expect(instance.tagIds, ['tag-1']);
    expect(instance.tagsLoaded, isTrue);
  });

  test('buildInstance copies template habit link', () {
    final template = Todo(
      id: 'template-1',
      title: 'Daily habit todo',
      recurrenceType: 'daily',
      time: '08:30',
      habitId: 'habit-1',
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    final instance = RecurrenceHelper.buildInstance(
      template: template,
      date: DateTime.utc(2026, 6, 16),
    );

    expect(instance.habitId, 'habit-1');
    expect(instance.time, '08:30');
  });
}
