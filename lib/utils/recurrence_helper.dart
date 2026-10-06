import '../models/tag.dart';
import '../models/todo.dart';
import '../utils/uuid_utils.dart' show newId;

/// Pure static helper for recurring todo logic.
///
/// No side-effects — all methods are deterministic, easy to unit-test.
class RecurrenceHelper {
  RecurrenceHelper._();

  // ─── Occurrence dates ──────────────────────────────────────────────

  /// Returns all occurrence dates for [template] in the range
  /// [startDate, horizon) (startDate inclusive, horizon exclusive).
  ///
  /// Respects [template.recurrenceEndDate] — no dates past it are returned.
  static List<DateTime> occurrenceDates({
    required Todo template,
    required DateTime startDate,
    required DateTime horizon,
  }) {
    if (!template.isRecurrenceTemplate) return const [];
    final results = <DateTime>[];

    // Determine effective end-date bound
    DateTime effectiveHorizon = horizon;
    if (template.recurrenceEndDate != null) {
      final end = _parseDateOnly(template.recurrenceEndDate!);
      if (end != null) {
        final endInclusive = end.add(const Duration(days: 1)); // make exclusive
        if (endInclusive.isBefore(effectiveHorizon)) {
          effectiveHorizon = endInclusive;
        }
      }
    }

    final type = template.recurrenceType!;
    final interval = template.recurrenceInterval.clamp(1, 366);

    switch (type) {
      case 'daily':
        _walkDays(
          start: startDate,
          horizon: effectiveHorizon,
          interval: interval,
          out: results,
        );
        break;

      case 'weekly':
        _walkWeekly(
          start: startDate,
          horizon: effectiveHorizon,
          interval: interval,
          activeDays: template.activeDaysOfWeek,
          out: results,
        );
        break;

      case 'custom':
        // Custom: interval = N days, optional weekday filter
        final days = template.activeDaysOfWeek;
        if (days.isEmpty) {
          // Fall back to every-N-days
          _walkDays(
            start: startDate,
            horizon: effectiveHorizon,
            interval: interval,
            out: results,
          );
        } else {
          _walkWeekly(
            start: startDate,
            horizon: effectiveHorizon,
            interval: interval,
            activeDays: days,
            out: results,
          );
        }
        break;
    }

    return results;
  }

  // ─── Next occurrence after a given date ───────────────────────────

  /// Returns the first occurrence date strictly after [afterDate],
  /// looking up to 366 days ahead. Returns null if none found.
  static DateTime? nextOccurrence({
    required Todo template,
    required DateTime afterDate,
  }) {
    final candidates = occurrenceDates(
      template: template,
      startDate: afterDate.add(const Duration(days: 1)),
      horizon: afterDate.add(const Duration(days: 366)),
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Returns the next scheduled date after completing a recurring todo.
  /// Mirrors the backend complete endpoint semantics.
  static DateTime? nextDateAfterCompletedTodo(Todo todo) {
    final type = todo.recurrenceType;
    final scheduledDate = todo.scheduledDate;
    if (type == null || scheduledDate == null) return null;

    final current = _dateOnly(scheduledDate);
    final interval = todo.recurrenceInterval < 1 ? 1 : todo.recurrenceInterval;
    final DateTime next;

    switch (type) {
      case 'daily':
      case 'custom':
        next = current.add(Duration(days: interval));
        break;
      case 'weekly':
        next = _nextWeeklyDate(
          current: current,
          interval: interval,
          activeDays: todo.activeDaysOfWeek,
        );
        break;
      default:
        return null;
    }

    final endDate = todo.recurrenceEndDate == null
        ? null
        : _parseDateOnly(todo.recurrenceEndDate!);
    if (endDate != null && next.isAfter(endDate)) return null;
    return next;
  }

  /// Returns the first recurrence strictly after [todo.scheduledDate] that is
  /// on or after [minimumDate].
  ///
  /// This is used to repair legacy recurring series that were completed before
  /// the app could create their next occurrence. Missed historical dates are
  /// skipped so the repaired todo becomes actionable now or in the future.
  static DateTime? nextDateOnOrAfter({
    required Todo todo,
    required DateTime minimumDate,
  }) {
    if (todo.recurrenceType == null || todo.scheduledDate == null) return null;

    final minimum = _dateOnly(minimumDate);
    var cursor = todo;
    while (true) {
      final currentDate = _dateOnly(cursor.scheduledDate!);
      final next = nextDateAfterCompletedTodo(cursor);
      if (next == null || !next.isAfter(currentDate)) return null;
      if (!next.isBefore(minimum)) return next;
      cursor = cursor.copyWith(scheduledDate: next);
    }
  }

  static DateTime? nextDateSkippingExceptions({
    required Todo todo,
    DateTime? minimumDate,
    Set<String> exceptionDates = const {},
  }) {
    var cursor = todo;
    var next = minimumDate == null
        ? nextDateAfterCompletedTodo(cursor)
        : nextDateOnOrAfter(todo: cursor, minimumDate: minimumDate);
    for (var attempt = 0; attempt < 366 && next != null; attempt++) {
      if (!exceptionDates.contains(_dateKey(next))) return next;
      cursor = cursor.copyWith(scheduledDate: next);
      next = nextDateAfterCompletedTodo(cursor);
    }
    return null;
  }

  static DateTime _nextWeeklyDate({
    required DateTime current,
    required int interval,
    required List<int> activeDays,
  }) {
    final days =
        activeDays
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toSet()
            .toList()
          ..sort();
    if (days.isEmpty) return current.add(Duration(days: 7 * interval));

    for (final day in days) {
      if (day > current.weekday) {
        return current.add(Duration(days: day - current.weekday));
      }
    }

    final weekStart = current.subtract(Duration(days: current.weekday - 1));
    return weekStart.add(Duration(days: 7 * interval + days.first - 1));
  }

  // ─── Build instance ───────────────────────────────────────────────

  /// Creates a new Todo instance for [template] on [date].
  /// Uses [newId] if no [overrideId] is provided.
  static Todo buildInstance({
    required Todo template,
    required DateTime date,
    String? overrideId,
  }) {
    final now = DateTime.now().toUtc();
    return Todo(
      id: overrideId ?? newId(),
      title: template.title,
      description: template.description,
      parentId: null, // instances are always top-level
      scheduledDate: date,
      time: template.time,
      status: TodoStatus.open,
      position: 0,
      isFrog: false,
      frogDate: null,
      isImportant: template.isImportant,
      isUrgent: template.isUrgent,
      estimatedMinutes: template.estimatedMinutes,
      actualMinutes: null,
      startAt: null,
      dueAt: DateTime.utc(date.year, date.month, date.day, 23, 59),
      triggerAfterTodoId: null,
      habitId: template.habitId,
      tags: template.tags,
      tagIds: template.tagIds,
      tagsLoaded: template.tagsLoaded,
      completedAt: null,
      // Recurrence: instance has no type, just points back to template
      recurrenceType: null,
      recurrenceInterval: 1,
      recurrenceDaysOfWeek: null,
      recurrenceEndDate: null,
      recurrenceTemplateId: template.id,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Builds the real next occurrence created after a completed recurring todo.
  /// Unlike [buildInstance], this keeps recurrence fields because this row is
  /// the next actionable occurrence, not a display-only projection.
  static Todo buildNextAfterCompletion({
    required Todo source,
    required DateTime scheduledDate,
    required String templateId,
    String? overrideId,
    List<Tag> tags = const [],
    List<String> tagIds = const [],
  }) {
    final now = DateTime.now().toUtc();
    return Todo(
      id: overrideId ?? newId(),
      parentId: source.parentId,
      title: source.title,
      description: source.description,
      scheduledDate: scheduledDate,
      time: source.parentId == null ? source.time : null,
      status: TodoStatus.open,
      position: source.position,
      isFrog: source.isFrog,
      frogDate: source.frogDate,
      isImportant: source.isImportant,
      isUrgent: source.isUrgent,
      estimatedMinutes: source.estimatedMinutes,
      actualMinutes: null,
      startAt: source.startAt,
      dueAt: source.dueAt == null ? null : _endOfDayUtc(scheduledDate),
      triggerAfterTodoId: source.triggerAfterTodoId,
      habitId: source.habitId,
      tags: tags,
      tagIds: tagIds,
      tagsLoaded: tags.isNotEmpty || tagIds.isNotEmpty,
      completedAt: null,
      recurrenceType: source.recurrenceType,
      recurrenceInterval: source.recurrenceInterval,
      recurrenceDaysOfWeek: source.recurrenceDaysOfWeek,
      recurrenceEndDate: source.recurrenceEndDate,
      recurrenceTemplateId: templateId,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  static DateTime _endOfDayUtc(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day, 23, 59);

  /// Walk every [interval] days starting from [start] up to [horizon].
  static void _walkDays({
    required DateTime start,
    required DateTime horizon,
    required int interval,
    required List<DateTime> out,
  }) {
    var current = _dateOnly(start);
    final end = _dateOnly(horizon);
    while (!current.isAfter(end) && !current.isAtSameMomentAs(end)) {
      out.add(current);
      current = current.add(Duration(days: interval));
    }
  }

  /// Walk each week, emitting [activeDays] weekday occurrences.
  /// [interval] = number of weeks between repetitions.
  static void _walkWeekly({
    required DateTime start,
    required DateTime horizon,
    required int interval,
    required List<int> activeDays,
    required List<DateTime> out,
  }) {
    if (activeDays.isEmpty) {
      // No weekday filter — treat like daily with interval weeks
      _walkDays(
        start: start,
        horizon: horizon,
        interval: interval * 7,
        out: out,
      );
      return;
    }

    // Find the Monday of the week containing [start]
    var weekStart = _dateOnly(start);
    final weekday = weekStart.weekday; // 1=Mon…7=Sun
    weekStart = weekStart.subtract(Duration(days: weekday - 1));

    final end = _dateOnly(horizon);

    while (weekStart.isBefore(end)) {
      for (final day in activeDays) {
        final candidate = weekStart.add(Duration(days: day - 1));
        if (!candidate.isBefore(_dateOnly(start)) && candidate.isBefore(end)) {
          out.add(candidate);
        }
      }
      weekStart = weekStart.add(Duration(days: 7 * interval));
    }
  }

  static DateTime _dateOnly(DateTime dt) =>
      DateTime.utc(dt.year, dt.month, dt.day);

  static String _dateKey(DateTime date) {
    final value = _dateOnly(date);
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseDateOnly(String s) {
    try {
      final parts = s.split('-');
      if (parts.length != 3) return null;
      return DateTime.utc(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } catch (_) {
      return null;
    }
  }
}
