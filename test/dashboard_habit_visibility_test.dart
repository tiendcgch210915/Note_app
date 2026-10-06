import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/habit.dart';
import 'package:todonote/utils/dashboard_habit_visibility.dart';

void main() {
  test('remaining dashboard habits excludes any habit with a log today', () {
    final today = DateTime(2026, 7, 1);
    final habits = [_habit('habit-1'), _habit('habit-2'), _habit('habit-3')];

    final remaining = remainingDashboardHabitsForDate(
      habits: habits,
      habitLogsByDate: {
        today: {'habit-1': true, 'habit-2': false},
      },
      date: today,
    );

    expect(remaining.map((habit) => habit.id), ['habit-3']);
  });

  test('remaining dashboard habits matches logs by date only', () {
    final habits = [_habit('habit-1'), _habit('habit-2')];

    final remaining = remainingDashboardHabitsForDate(
      habits: habits,
      habitLogsByDate: {
        DateTime(2026, 7, 1, 8, 30): {'habit-1': false},
        DateTime(2026, 6, 30): {'habit-2': true},
      },
      date: DateTime(2026, 7, 1),
    );

    expect(remaining.map((habit) => habit.id), ['habit-2']);
  });
}

Habit _habit(String id) {
  return Habit(
    id: id,
    title: id,
    color: Colors.green,
    startDate: DateTime(2026, 7, 1),
  );
}
