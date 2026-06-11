import '../models/todo.dart';

List<Todo> filterTodoTriggerCandidates(
  List<Todo> todos, {
  String? excludeId,
  DateTime? anchor,
}) {
  final today = _dateOnly(anchor ?? DateTime.now());
  final regular = <Todo>[];
  final recurringBySeries = <String, Todo>{};

  for (final todo in todos) {
    if (todo.id == excludeId) continue;
    if (todo.status == TodoStatus.done || todo.status == TodoStatus.archived) {
      continue;
    }

    final seriesKey = _recurringSeriesKey(todo);
    if (seriesKey == null) {
      regular.add(todo);
      continue;
    }

    final current = recurringBySeries[seriesKey];
    if (current == null || _compareByNearestDate(todo, current, today) < 0) {
      recurringBySeries[seriesKey] = todo;
    }
  }

  final result = [...regular, ...recurringBySeries.values];
  result.sort((a, b) => _compareByNearestDate(a, b, today));
  return result;
}

String? _recurringSeriesKey(Todo todo) {
  if (todo.recurrenceTemplateId != null) return todo.recurrenceTemplateId;
  if (todo.isRecurrenceTemplate) return todo.id;
  return null;
}

int _compareByNearestDate(Todo a, Todo b, DateTime today) {
  final aDistance = _distanceFromToday(a, today);
  final bDistance = _distanceFromToday(b, today);
  if (aDistance != bDistance) return aDistance.compareTo(bDistance);

  final aFutureOrToday = _isFutureOrToday(a, today);
  final bFutureOrToday = _isFutureOrToday(b, today);
  if (aFutureOrToday != bFutureOrToday) {
    return aFutureOrToday ? -1 : 1;
  }

  final aDate = _scheduledDateOnly(a);
  final bDate = _scheduledDateOnly(b);
  if (aDate != null && bDate != null) {
    final byDate = aDate.compareTo(bDate);
    if (byDate != 0) return byDate;
  } else if (aDate != null) {
    return -1;
  } else if (bDate != null) {
    return 1;
  }

  return b.createdAt.compareTo(a.createdAt);
}

int _distanceFromToday(Todo todo, DateTime today) {
  final scheduledDate = _scheduledDateOnly(todo);
  if (scheduledDate == null) return 1 << 30;
  return scheduledDate.difference(today).inDays.abs();
}

bool _isFutureOrToday(Todo todo, DateTime today) {
  final scheduledDate = _scheduledDateOnly(todo);
  if (scheduledDate == null) return false;
  return !scheduledDate.isBefore(today);
}

DateTime? _scheduledDateOnly(Todo todo) {
  final scheduledDate = todo.scheduledDate;
  if (scheduledDate == null) return null;
  return _dateOnly(scheduledDate);
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
