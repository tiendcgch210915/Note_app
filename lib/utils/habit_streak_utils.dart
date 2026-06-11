import '../models/habit_log.dart';
import 'date_utils.dart';

typedef HabitStreak = ({int current, int longest});

HabitStreak deriveHabitStreakFromLogs({
  required Iterable<HabitLog> logs,
  required DateTime today,
  required DateTime startDate,
  int fallbackCurrent = 0,
  int fallbackLongest = 0,
}) {
  return deriveHabitStreakFromCompletionMap(
    completedByDate: {
      for (final log in logs) AppDateUtils.dateOnly(log.logDate): log.completed,
    },
    today: today,
    startDate: startDate,
    fallbackCurrent: fallbackCurrent,
    fallbackLongest: fallbackLongest,
  );
}

HabitStreak deriveHabitStreakFromCompletionMap({
  required Map<DateTime, bool> completedByDate,
  required DateTime today,
  required DateTime startDate,
  int fallbackCurrent = 0,
  int fallbackLongest = 0,
}) {
  if (completedByDate.isEmpty) {
    return (current: fallbackCurrent, longest: fallbackLongest);
  }

  final normalized = {
    for (final entry in completedByDate.entries)
      AppDateUtils.dateOnly(entry.key): entry.value,
  };
  final todayOnly = AppDateUtils.dateOnly(today);
  final habitStart = AppDateUtils.dateOnly(startDate);
  var firstObserved = todayOnly;
  for (final date in normalized.keys) {
    if (date.isBefore(firstObserved)) firstObserved = date;
  }
  final from = firstObserved.isAfter(habitStart) ? firstObserved : habitStart;

  var current = 0;
  var cursor = todayOnly;
  while (!cursor.isBefore(from) && normalized[cursor] == true) {
    current++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  final observedWindowDays = todayOnly.isBefore(from)
      ? 0
      : todayOnly.difference(from).inDays + 1;
  if (observedWindowDays > 0 &&
      current >= observedWindowDays &&
      fallbackCurrent > current) {
    current = fallbackCurrent;
  }

  var longest = 0;
  var run = 0;
  if (!todayOnly.isBefore(from)) {
    final totalDays = todayOnly.difference(from).inDays;
    for (var i = 0; i <= totalDays; i++) {
      final date = from.add(Duration(days: i));
      if (normalized[date] == true) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
    }
  }
  if (fallbackLongest > longest) longest = fallbackLongest;

  return (current: current, longest: longest);
}
