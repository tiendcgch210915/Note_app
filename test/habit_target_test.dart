import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/habit.dart';
import 'package:todonote/models/habit_log.dart';
import 'package:todonote/utils/habit_streak_utils.dart';

void main() {
  test('habit create target defaults to 7 without an end date', () {
    final target = Habit.createTargetPerPeriod(
      frequencyType: FrequencyType.daily,
      startDate: DateTime(2026, 6, 1),
    );

    expect(target, 7);
  });

  test('daily habit target is capped by short date range', () {
    final target = Habit.createTargetPerPeriod(
      frequencyType: FrequencyType.daily,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 5),
    );

    expect(target, 5);
  });

  test('daily habit target is capped at 7 for long date range', () {
    final target = Habit.createTargetPerPeriod(
      frequencyType: FrequencyType.daily,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 30),
    );

    expect(target, 7);
  });

  test('weekly habit target uses number of available weeks up to 7', () {
    final target = Habit.createTargetPerPeriod(
      frequencyType: FrequencyType.weekly,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 28),
    );

    expect(target, 4);
  });

  test('custom habit target counts selected weekdays in range', () {
    final target = Habit.createTargetPerPeriod(
      frequencyType: FrequencyType.custom,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 5),
      activeWeekdays: const [1, 3, 5],
    );

    expect(target, 3);
  });

  test('habit create body calculates target automatically', () {
    final body = Habit.createBody(
      title: 'Read',
      frequencyType: FrequencyType.daily,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 5),
    );

    expect(body['target_per_period'], 5);
  });

  test('habit streak includes today and yesterday completions', () {
    final today = DateTime(2026, 6, 11);
    final streak = deriveHabitStreakFromLogs(
      logs: [
        HabitLog(
          id: 'log-yesterday',
          habitId: 'habit-1',
          logDate: DateTime(2026, 6, 10),
          completed: true,
        ),
        HabitLog(
          id: 'log-today',
          habitId: 'habit-1',
          logDate: today,
          completed: true,
        ),
      ],
      today: today,
      startDate: DateTime(2026, 6, 1),
    );

    expect(streak.current, 2);
    expect(streak.longest, 2);
  });

  test('habit streak derives longest run from visible completed logs', () {
    final today = DateTime(2026, 6, 11);
    final streak = deriveHabitStreakFromCompletionMap(
      completedByDate: {
        DateTime(2026, 6, 7): true,
        DateTime(2026, 6, 8): false,
        DateTime(2026, 6, 9): true,
        DateTime(2026, 6, 10): true,
        DateTime(2026, 6, 11): true,
      },
      today: today,
      startDate: DateTime(2026, 6, 1),
    );

    expect(streak.current, 3);
    expect(streak.longest, 3);
  });

  test('habit streak uses yesterday when today has not been logged', () {
    final today = DateTime(2026, 6, 11);
    final streak = deriveHabitStreakFromCompletionMap(
      completedByDate: {
        DateTime(2026, 6, 8): false,
        DateTime(2026, 6, 9): true,
        DateTime(2026, 6, 10): true,
      },
      today: today,
      startDate: DateTime(2026, 6, 1),
    );

    expect(streak.current, 2);
    expect(streak.longest, 2);
  });

  test('habit streak is zero when today and yesterday are both unlogged', () {
    final today = DateTime(2026, 6, 11);
    final streak = deriveHabitStreakFromCompletionMap(
      completedByDate: {DateTime(2026, 6, 9): true},
      today: today,
      startDate: DateTime(2026, 6, 1),
    );

    expect(streak.current, 0);
    expect(streak.longest, 1);
  });

  test('habit streak resets current when today is marked incomplete', () {
    final today = DateTime(2026, 6, 11);
    final streak = deriveHabitStreakFromCompletionMap(
      completedByDate: {
        DateTime(2026, 6, 9): true,
        DateTime(2026, 6, 10): true,
        DateTime(2026, 6, 11): false,
      },
      today: today,
      startDate: DateTime(2026, 6, 1),
      fallbackCurrent: 3,
      fallbackLongest: 3,
    );

    expect(streak.current, 0);
    expect(streak.longest, 3);
  });
}
