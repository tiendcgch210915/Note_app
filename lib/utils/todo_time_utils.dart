int? todoTimeMinutes(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(raw);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

enum TodoTimeState { upcoming, near, overdue }

int compareTodoTimes(String? a, String? b) {
  final aMinutes = todoTimeMinutes(a);
  final bMinutes = todoTimeMinutes(b);
  if (aMinutes == null && bMinutes == null) return 0;
  if (aMinutes == null) return 1;
  if (bMinutes == null) return -1;
  return aMinutes.compareTo(bMinutes);
}

String? formatTodoTime(String? value) {
  final minutes = todoTimeMinutes(value);
  if (minutes == null) {
    final raw = value?.trim();
    return raw == null || raw.isEmpty ? null : raw;
  }
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

TodoTimeState? todoTimeState({
  required DateTime? scheduledDate,
  required String? time,
  DateTime? now,
}) {
  final minutes = todoTimeMinutes(time);
  if (minutes == null) return null;
  final current = now ?? DateTime.now();
  final date = scheduledDate ?? current;
  final target = DateTime(
    date.year,
    date.month,
    date.day,
    minutes ~/ 60,
    minutes % 60,
  );
  final difference = target.difference(current);
  if (difference < const Duration(hours: -1)) {
    return TodoTimeState.overdue;
  }
  if (difference > const Duration(hours: 1)) {
    return TodoTimeState.upcoming;
  }
  return TodoTimeState.near;
}

String todoTitleWithTime(String title, String? time) {
  final label = formatTodoTime(time);
  return label == null ? title : '[$label] $title';
}
