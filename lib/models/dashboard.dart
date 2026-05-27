import '../utils/json_utils.dart';
import 'todo.dart';

/// Tóm tắt todo đại diện cho Frog trên Dashboard.
class FrogTodo {
  final String id;
  final String title;
  final String status;

  const FrogTodo({required this.id, required this.title, required this.status});

  factory FrogTodo.fromJson(Map<String, dynamic> json) {
    return FrogTodo(
      id: json['id'] as String,
      title: json['title'] as String,
      status: json['status'] as String? ?? 'open',
    );
  }

  bool get isDone => status == 'done';
}

/// Response F-D1 GET /dashboard/today.
class DashboardSnapshot {
  final DateTime date;
  final int score; // 0..100
  final int todosTotal;
  final int todosDone;
  final Map<String, int> eisenhowerCounts; // q1, q2, q3, q4, unclassified
  final int habitsTotal;
  final int habitsCompleted;
  final FrogTodo? frog;

  const DashboardSnapshot({
    required this.date,
    required this.score,
    required this.todosTotal,
    required this.todosDone,
    required this.eisenhowerCounts,
    required this.habitsTotal,
    required this.habitsCompleted,
    required this.frog,
  });

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    final todosMap = json['todos'] as Map<String, dynamic>? ?? const {};
    final eisenhowerMap = json['eisenhower_counts'] as Map<String, dynamic>? ?? const {};
    final habitsMap = json['habits_today'] as Map<String, dynamic>? ?? const {};
    final frogJson = json['frog'] as Map<String, dynamic>?;
    return DashboardSnapshot(
      date: jsonDateOnly(json['date'] as String),
      score: (json['score'] as num?)?.toInt() ?? 0,
      todosTotal: (todosMap['total'] as num?)?.toInt() ?? 0,
      todosDone: (todosMap['done'] as num?)?.toInt() ?? 0,
      eisenhowerCounts: eisenhowerMap
          .map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      habitsTotal: (habitsMap['total'] as num?)?.toInt() ?? 0,
      habitsCompleted: (habitsMap['completed'] as num?)?.toInt() ?? 0,
      frog: frogJson == null ? null : FrogTodo.fromJson(frogJson),
    );
  }
}

/// Response F-D2 GET /dashboard/eisenhower.
class EisenhowerDetail {
  final DateTime date;
  final Map<String, int> counts;
  final Map<String, List<Todo>> byQuadrant;

  const EisenhowerDetail({
    required this.date,
    required this.counts,
    required this.byQuadrant,
  });

  factory EisenhowerDetail.fromJson(Map<String, dynamic> json) {
    final countsMap = json['counts'] as Map<String, dynamic>? ?? const {};
    final byQuadMap = json['by_quadrant'] as Map<String, dynamic>? ?? const {};
    return EisenhowerDetail(
      date: jsonDateOnly(json['date'] as String),
      counts: countsMap.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      byQuadrant: byQuadMap.map((k, v) {
        final list = (v as List?)
                ?.map((e) => Todo.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const <Todo>[];
        return MapEntry(k, list);
      }),
    );
  }
}

/// Một ngày trong calendar overview (F-D3).
class CalendarDay {
  final int totalTodos;
  final int doneTodos;
  final int? score; // null nếu future
  final int habitsTotal;
  final int habitsCompleted;

  const CalendarDay({
    required this.totalTodos,
    required this.doneTodos,
    this.score,
    required this.habitsTotal,
    required this.habitsCompleted,
  });

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    return CalendarDay(
      totalTodos: (json['total_todos'] as num?)?.toInt() ?? 0,
      doneTodos: (json['done_todos'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toInt(),
      habitsTotal: (json['habits_total'] as num?)?.toInt() ?? 0,
      habitsCompleted: (json['habits_completed'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isFuture => score == null;
}
