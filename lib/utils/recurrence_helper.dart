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
      status: TodoStatus.open,
      position: 0,
      isFrog: false,
      frogDate: null,
      isImportant: template.isImportant,
      isUrgent: template.isUrgent,
      estimatedMinutes: template.estimatedMinutes,
      actualMinutes: null,
      startAt: null,
      dueAt: null,
      triggerAfterTodoId: null,
      tagIds: const [],
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

  // ─── Helpers ──────────────────────────────────────────────────────

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
