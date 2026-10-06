import '../models/habit.dart';
import 'date_utils.dart';

List<Habit> remainingDashboardHabitsForDate({
  required List<Habit> habits,
  required Map<DateTime, Map<String, bool>> habitLogsByDate,
  required DateTime date,
}) {
  final day = AppDateUtils.dateOnly(date);
  final loggedHabitIds = <String>{};
  for (final entry in habitLogsByDate.entries) {
    if (!AppDateUtils.isSameDay(entry.key, day)) continue;
    loggedHabitIds.addAll(entry.value.keys);
  }
  return habits
      .where((habit) => !loggedHabitIds.contains(habit.id))
      .toList(growable: false);
}
