import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/utils/daily_score_calculator.dart';

void main() {
  final date = DateTime(2026, 7, 7);
  final createdAt = DateTime.utc(2026, 7, 7);
  final completedOnTime = DateTime.utc(2026, 7, 7, 8);
  final completedLate = DateTime.utc(2026, 7, 7, 18);

  test('2 todos done and all habits done still score zero', () {
    final result = DailyScoreCalculator.calculate(
      date: date,
      habitsTotal: 2,
      habitsCompleted: 2,
      todos: [
        _todo(
          'a',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          important: true,
        ),
        _todo(
          'b',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          urgent: true,
        ),
      ],
    );

    expect(result.totalTodos, 2);
    expect(result.validCompletedTodos, 2);
    expect(result.passedMinimumGate, isFalse);
    expect(result.score, 0);
    expect(result.habitScore, 0);
  });

  test('3 planned but only 2 valid completions still score zero', () {
    final result = DailyScoreCalculator.calculate(
      date: date,
      habitsTotal: 3,
      habitsCompleted: 3,
      todos: [
        _todo(
          'a',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          important: true,
        ),
        _todo(
          'b',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          urgent: true,
        ),
        _todo('c', createdAt, date: date, important: true, urgent: true),
      ],
    );

    expect(result.totalTodos, 3);
    expect(result.validCompletedTodos, 2);
    expect(result.score, 0);
    expect(result.habitScore, 0);
  });

  test('3 valid completed todos unlock weighted todo score', () {
    final result = DailyScoreCalculator.calculate(
      date: date,
      todos: [
        _todo(
          'important',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          important: true,
        ),
        _todo(
          'urgent',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          urgent: true,
        ),
        _todo(
          'both',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          important: true,
          urgent: true,
        ),
      ],
    );

    expect(result.passedMinimumGate, isTrue);
    expect(result.todoScore, 80);
    expect(result.score, 80);
  });

  test('habits only contribute after the todo gate passes', () {
    final result = DailyScoreCalculator.calculate(
      date: date,
      habitsTotal: 2,
      habitsCompleted: 2,
      todos: [
        _todo(
          'a',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          important: true,
        ),
        _todo(
          'b',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          urgent: true,
        ),
        _todo(
          'c',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          important: true,
          urgent: true,
        ),
      ],
    );

    expect(result.todoScore, 80);
    expect(result.habitScore, 30);
    expect(result.score, 110);
  });

  test('frog bonus is blocked by the minimum completed todo gate', () {
    final result = DailyScoreCalculator.calculate(
      date: date,
      todos: [
        _todo(
          'frog',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          frog: true,
        ),
        _todo(
          'done',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          important: true,
        ),
        _todo('open', createdAt, date: date, urgent: true),
      ],
    );

    expect(result.validCompletedTodos, 2);
    expect(result.frogBonus, 0);
    expect(result.score, 0);
  });

  test('frog bonus and habits can lift a valid day to 120', () {
    final result = DailyScoreCalculator.calculate(
      date: date,
      habitsTotal: 3,
      habitsCompleted: 3,
      todos: [
        _todo(
          'frog',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          frog: true,
        ),
        _todo(
          'important',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          important: true,
        ),
        _todo(
          'urgent',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          urgent: true,
        ),
      ],
    );

    expect(result.todoScore, 80);
    expect(result.frogBonus, 10);
    expect(result.habitScore, 30);
    expect(result.score, 120);
  });

  test('late completion after Vietnam work date is not valid for score', () {
    final result = DailyScoreCalculator.calculate(
      date: date,
      habitsTotal: 1,
      habitsCompleted: 1,
      todos: [
        _todo(
          'a',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          important: true,
        ),
        _todo(
          'b',
          createdAt,
          date: date,
          completedAt: completedOnTime,
          urgent: true,
        ),
        _todo(
          'late',
          createdAt,
          date: date,
          completedAt: completedLate,
          important: true,
          urgent: true,
        ),
      ],
    );

    expect(result.totalTodos, 3);
    expect(result.validCompletedTodos, 2);
    expect(result.score, 0);
  });
}

Todo _todo(
  String id,
  DateTime createdAt, {
  required DateTime date,
  DateTime? completedAt,
  bool important = false,
  bool urgent = false,
  bool frog = false,
}) {
  return Todo(
    id: id,
    title: id,
    status: completedAt == null ? TodoStatus.open : TodoStatus.done,
    scheduledDate: date,
    completedAt: completedAt,
    isImportant: frog ? true : important,
    isUrgent: frog ? true : urgent,
    isFrog: frog,
    frogDate: frog ? date : null,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
