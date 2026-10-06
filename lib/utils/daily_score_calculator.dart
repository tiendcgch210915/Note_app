import '../models/todo.dart';
import 'date_utils.dart';

class DailyScoreResult {
  final int score;
  final int totalTodos;
  final int validCompletedTodos;
  final int todoScore;
  final int frogBonus;
  final int habitScore;

  const DailyScoreResult({
    required this.score,
    required this.totalTodos,
    required this.validCompletedTodos,
    required this.todoScore,
    required this.frogBonus,
    required this.habitScore,
  });

  bool get passedMinimumGate =>
      totalTodos >= DailyScoreCalculator.minimumTodos &&
      validCompletedTodos >= DailyScoreCalculator.minimumCompletedTodos;
}

class DailyScoreCalculator {
  static const int minimumTodos = 3;
  static const int minimumCompletedTodos = 3;

  static DailyScoreResult calculate({
    required Iterable<Todo> todos,
    required DateTime date,
    int habitsTotal = 0,
    int habitsCompleted = 0,
  }) {
    final scoreDate = AppDateUtils.dateOnly(date);
    final dayTodos = todos
        .where((todo) => isTodoOnDate(todo, scoreDate))
        .where((todo) => todo.status != TodoStatus.archived)
        .toList(growable: false);
    final validCompleted = dayTodos
        .where((todo) => isTodoCompletedForScore(todo, scoreDate))
        .length;

    if (dayTodos.length < minimumTodos ||
        validCompleted < minimumCompletedTodos) {
      return DailyScoreResult(
        score: 0,
        totalTodos: dayTodos.length,
        validCompletedTodos: validCompleted,
        todoScore: 0,
        frogBonus: 0,
        habitScore: 0,
      );
    }

    final weightedTodos = dayTodos
        .where((todo) => todoWeight(todo, scoreDate) > 0)
        .toList(growable: false);
    final totalWeight = weightedTodos.fold<int>(
      0,
      (sum, todo) => sum + todoWeight(todo, scoreDate),
    );
    var todoScoreValue = 0.0;
    if (totalWeight > 0) {
      for (final todo in weightedTodos) {
        if (!isTodoCompletedForScore(todo, scoreDate)) continue;
        todoScoreValue += 80 * (todoWeight(todo, scoreDate) / totalWeight);
      }
    }

    final frogBonus =
        dayTodos.any(
          (todo) =>
              isFrogForDate(todo, scoreDate) &&
              isTodoCompletedForScore(todo, scoreDate),
        )
        ? 10
        : 0;
    final habitScore = habitsTotal <= 0
        ? 0
        : (30 * (habitsCompleted.clamp(0, habitsTotal) / habitsTotal)).round();
    final todoScore = todoScoreValue.round();

    return DailyScoreResult(
      score: todoScore + frogBonus + habitScore,
      totalTodos: dayTodos.length,
      validCompletedTodos: validCompleted,
      todoScore: todoScore,
      frogBonus: frogBonus,
      habitScore: habitScore,
    );
  }

  static bool isTodoOnDate(Todo todo, DateTime date) {
    final scheduledDate = todo.scheduledDate;
    if (todo.parentId != null || scheduledDate == null) return false;
    return AppDateUtils.isSameDay(scheduledDate, date);
  }

  static bool isTodoCompletedForScore(Todo todo, DateTime scoreDate) {
    return isCompletionValidForScore(
      isDone: todo.isDone,
      completedAt: todo.completedAt,
      scoreDate: scoreDate,
      scheduledDate: todo.scheduledDate,
    );
  }

  static bool isCompletionValidForScore({
    required bool isDone,
    required DateTime? completedAt,
    required DateTime scoreDate,
    DateTime? scheduledDate,
  }) {
    if (!isDone || completedAt == null) return false;
    final workDate = AppDateUtils.dateOnly(scheduledDate ?? scoreDate);
    return !vietnamDateOnly(completedAt).isAfter(workDate);
  }

  static int todoWeight(Todo todo, DateTime date) {
    if (isFrogForDate(todo, date)) return 2;
    final important = todo.isImportant == true;
    final urgent = todo.isUrgent == true;
    if (important && urgent) return 2;
    if (important || urgent) return 1;
    return 0;
  }

  static bool isFrogForDate(Todo todo, DateTime date) {
    if (!todo.isFrog) return false;
    final frogDate = todo.frogDate;
    return frogDate == null || AppDateUtils.isSameDay(frogDate, date);
  }

  static DateTime vietnamDateOnly(DateTime instant) {
    final vietnamTime = instant.toUtc().add(const Duration(hours: 7));
    return DateTime(vietnamTime.year, vietnamTime.month, vietnamTime.day);
  }
}
