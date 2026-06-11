import '../utils/json_utils.dart';

class HabitLog {
  final String id;
  final String habitId;
  final DateTime logDate; // date-only (00:00)
  final bool completed;
  final String? note;

  const HabitLog({
    required this.id,
    required this.habitId,
    required this.logDate,
    required this.completed,
    this.note,
  });

  factory HabitLog.fromJson(Map<String, dynamic> json) {
    return HabitLog(
      id: json['id'] as String,
      habitId: json['habit_id'] as String,
      logDate: jsonDateOnly(json['log_date'] as String),
      completed: jsonBool(json['completed']),
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'log_date': formatDateOnly(logDate),
    'completed': completed,
    'note': note,
  };
}
