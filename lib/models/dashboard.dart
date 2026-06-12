import '../utils/json_utils.dart';
import 'tag.dart';

const List<String> dashboardQuadrantKeys = ['q1', 'q2', 'q3', 'q4'];

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<dynamic> _asList(dynamic value) => value is List ? value : const [];

String _stringValue(dynamic value, {String fallback = ''}) {
  if (value is String && value.isNotEmpty) return value;
  return fallback;
}

int _intValue(dynamic value) => value is num ? value.toInt() : 0;

DateTime _dateOnlyOrToday(dynamic value) {
  final dateString = value is String ? value : null;
  if (dateString != null && dateString.isNotEmpty) {
    try {
      return jsonDateOnly(dateString);
    } catch (_) {
      // Fall through to local today for malformed dashboard payloads.
    }
  }
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime? _dateOnlyNullable(dynamic value) {
  final dateString = value is String ? value : null;
  if (dateString == null || dateString.isEmpty) return null;
  try {
    return jsonDateOnly(dateString);
  } catch (_) {
    return null;
  }
}

String? _quadrantKey(dynamic value) {
  final key = value is String ? value.toLowerCase() : null;
  return dashboardQuadrantKeys.contains(key) ? key : null;
}

String _quadrantFromFlags({required bool important, required bool urgent}) {
  if (important && urgent) return 'q1';
  if (important && !urgent) return 'q2';
  if (!important && urgent) return 'q3';
  return 'q4';
}

Map<String, int> _parseCounts(dynamic value) {
  final source = _asMap(value);
  return {
    for (final key in dashboardQuadrantKeys) key: _intValue(source?[key]),
  };
}

/// Tóm tắt todo đại diện cho Frog trên Dashboard.
class FrogTodo {
  final String id;
  final String title;
  final String status;

  const FrogTodo({required this.id, required this.title, required this.status});

  factory FrogTodo.fromJson(Map<String, dynamic> json) {
    return FrogTodo(
      id: _stringValue(json['id']),
      title: _stringValue(json['title'], fallback: 'Không có tiêu đề'),
      status: _stringValue(json['status'], fallback: 'open'),
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
  final Map<String, int> eisenhowerCounts; // q1, q2, q3, q4
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
    final todosMap = _asMap(json['todos']);
    final habitsMap = _asMap(json['habits_today']);
    final frogJson = _asMap(json['frog']);
    return DashboardSnapshot(
      date: _dateOnlyOrToday(json['date']),
      score: _intValue(json['score']),
      todosTotal: _intValue(todosMap?['total']),
      todosDone: _intValue(todosMap?['done']),
      eisenhowerCounts: _parseCounts(json['eisenhower_counts']),
      habitsTotal: _intValue(habitsMap?['total']),
      habitsCompleted: _intValue(habitsMap?['completed']),
      frog: frogJson == null ? null : FrogTodo.fromJson(frogJson),
    );
  }
}

class DashboardEisenhowerTodo {
  final String id;
  final String title;
  final String status;
  final DateTime? scheduledDate;
  final bool isImportant;
  final bool isUrgent;
  final bool isFrog;
  final DateTime? frogDate;
  final String quadrant;
  final List<Tag> tags;
  final List<String> tagIds;

  const DashboardEisenhowerTodo({
    required this.id,
    required this.title,
    required this.status,
    required this.scheduledDate,
    required this.isImportant,
    required this.isUrgent,
    required this.isFrog,
    required this.frogDate,
    required this.quadrant,
    this.tags = const [],
    this.tagIds = const [],
  });

  factory DashboardEisenhowerTodo.fromJson(
    Map<String, dynamic> json, {
    required String fallbackQuadrant,
  }) {
    final important = jsonBool(json['is_important']);
    final urgent = jsonBool(json['is_urgent']);
    final quadrant =
        _quadrantKey(json['quadrant']) ??
        _quadrantKey(fallbackQuadrant) ??
        _quadrantFromFlags(important: important, urgent: urgent);
    final tags = _asList(json['tags'])
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList(growable: false);
    final tagIds =
        (json['tag_ids'] as List?)?.map((e) => e as String).toList() ??
        tags.map((tag) => tag.id).toList();
    return DashboardEisenhowerTodo(
      id: _stringValue(json['id']),
      title: _stringValue(json['title'], fallback: 'Không có tiêu đề'),
      status: _stringValue(json['status'], fallback: 'open'),
      scheduledDate: _dateOnlyNullable(json['scheduled_date']),
      isImportant: important,
      isUrgent: urgent,
      isFrog: jsonBool(json['is_frog']),
      frogDate: _dateOnlyNullable(json['frog_date']),
      quadrant: quadrant,
      tags: tags,
      tagIds: tagIds,
    );
  }

  bool get isDoneOrArchived => status == 'done' || status == 'archived';
}

/// Response F-D2 GET /dashboard/eisenhower.
class EisenhowerDetail {
  final DateTime date;
  final Map<String, int> counts;
  final Map<String, List<DashboardEisenhowerTodo>> byQuadrant;

  const EisenhowerDetail({
    required this.date,
    required this.counts,
    required this.byQuadrant,
  });

  factory EisenhowerDetail.fromJson(Map<String, dynamic> json) {
    final byQuadMap = _asMap(json['by_quadrant']);
    return EisenhowerDetail(
      date: _dateOnlyOrToday(json['date']),
      counts: _parseCounts(json['counts']),
      byQuadrant: {
        for (final key in dashboardQuadrantKeys)
          key: _parseDashboardTodos(byQuadMap?[key], fallbackQuadrant: key),
      },
    );
  }
}

List<DashboardEisenhowerTodo> _parseDashboardTodos(
  dynamic value, {
  required String fallbackQuadrant,
}) {
  return _asList(value)
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map(
        (json) => DashboardEisenhowerTodo.fromJson(
          json,
          fallbackQuadrant: fallbackQuadrant,
        ),
      )
      .where((todo) => !todo.isDoneOrArchived)
      .toList(growable: false);
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
