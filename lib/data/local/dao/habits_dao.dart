import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'habits_dao.g.dart';

@DriftAccessor(tables: [HabitsTable, HabitLogsTable])
class HabitsDao extends DatabaseAccessor<AppDatabase> with _$HabitsDaoMixin {
  HabitsDao(super.db);

  // ─── Habits ───────────────────────────────────────────────────────

  Future<void> upsertHabit(HabitsTableCompanion row) async {
    await into(db.habitsTable).insertOnConflictUpdate(row);
  }

  Future<void> upsertHabits(List<HabitsTableCompanion> rows) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(db.habitsTable, rows);
    });
  }

  Future<HabitRow?> getHabitById(String id) {
    return (select(
      db.habitsTable,
    )..where((h) => h.id.equals(id) & h.deletedAt.isNull())).getSingleOrNull();
  }

  Future<List<HabitRow>> getActiveHabits() {
    return (select(db.habitsTable)
          ..where((h) => h.deletedAt.isNull() & h.isArchived.equals(false))
          ..orderBy([(h) => OrderingTerm.asc(h.title)]))
        .get();
  }

  Future<List<HabitRow>> getAllHabits() {
    return (select(db.habitsTable)..where((h) => h.deletedAt.isNull())).get();
  }

  Future<void> softDeleteHabit(String id, String deletedAtIso) async {
    await (update(db.habitsTable)..where((h) => h.id.equals(id))).write(
      HabitsTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  /// Cache streak values derived from logs or adopted from server.
  Future<void> adoptStreak(
    String habitId,
    int currentStreak,
    int longestStreak,
    String updatedAt,
  ) async {
    await (update(db.habitsTable)..where((h) => h.id.equals(habitId))).write(
      HabitsTableCompanion(
        currentStreak: Value(currentStreak),
        longestStreak: Value(longestStreak),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  // ─── Habit logs ───────────────────────────────────────────────────

  Future<void> upsertHabitLog(HabitLogsTableCompanion row) async {
    await into(db.habitLogsTable).insertOnConflictUpdate(row);
  }

  Future<HabitLogRow?> getHabitLogById(String id) {
    return (select(
      db.habitLogsTable,
    )..where((l) => l.id.equals(id) & l.deletedAt.isNull())).getSingleOrNull();
  }

  Future<HabitLogRow?> getHabitLogByHabitAndDate(
    String habitId,
    String logDate,
  ) {
    final q = select(db.habitLogsTable)
      ..where(
        (l) =>
            l.habitId.equals(habitId) &
            l.logDate.equals(logDate) &
            l.deletedAt.isNull(),
      )
      ..orderBy([
        (l) => OrderingTerm.desc(l.updatedAt),
        (l) => OrderingTerm.desc(l.createdAt),
        (l) => OrderingTerm.asc(l.id),
      ])
      ..limit(1);
    return q.getSingleOrNull();
  }

  Future<List<HabitLogRow>> getActiveHabitLogsByHabitAndDate(
    String habitId,
    String logDate,
  ) {
    final q = select(db.habitLogsTable)
      ..where(
        (l) =>
            l.habitId.equals(habitId) &
            l.logDate.equals(logDate) &
            l.deletedAt.isNull(),
      )
      ..orderBy([
        (l) => OrderingTerm.desc(l.updatedAt),
        (l) => OrderingTerm.desc(l.createdAt),
        (l) => OrderingTerm.asc(l.id),
      ]);
    return q.get();
  }

  /// Resurrect-local-first (contract §3.5): find a soft-deleted log for the
  /// same (habitId, logDate) so callers can reuse its id instead of minting
  /// a new one when creating a log for a date that was previously deleted.
  Future<HabitLogRow?> findSoftDeletedHabitLog(String habitId, String logDate) {
    final q = select(db.habitLogsTable)
      ..where(
        (l) =>
            l.habitId.equals(habitId) &
            l.logDate.equals(logDate) &
            l.deletedAt.isNotNull(),
      )
      ..orderBy([
        (l) => OrderingTerm.desc(l.updatedAt),
        (l) => OrderingTerm.desc(l.createdAt),
        (l) => OrderingTerm.asc(l.id),
      ])
      ..limit(1);
    return q.getSingleOrNull();
  }

  Future<List<HabitLogRow>> getLogsForRange(
    String habitId,
    String fromDate,
    String toDate,
  ) {
    final q = select(db.habitLogsTable)
      ..where(
        (l) =>
            l.habitId.equals(habitId) &
            l.logDate.isBiggerOrEqualValue(fromDate) &
            l.logDate.isSmallerOrEqualValue(toDate) &
            l.deletedAt.isNull(),
      )
      ..orderBy([
        (l) => OrderingTerm.asc(l.logDate),
        (l) => OrderingTerm.desc(l.updatedAt),
        (l) => OrderingTerm.desc(l.createdAt),
        (l) => OrderingTerm.asc(l.id),
      ]);
    return q.get();
  }

  Future<List<HabitLogRow>> getAllLogsForRange(String fromDate, String toDate) {
    final q = select(db.habitLogsTable)
      ..where(
        (l) =>
            l.logDate.isBiggerOrEqualValue(fromDate) &
            l.logDate.isSmallerOrEqualValue(toDate) &
            l.deletedAt.isNull(),
      )
      ..orderBy([
        (l) => OrderingTerm.asc(l.habitId),
        (l) => OrderingTerm.asc(l.logDate),
        (l) => OrderingTerm.desc(l.updatedAt),
        (l) => OrderingTerm.desc(l.createdAt),
        (l) => OrderingTerm.asc(l.id),
      ]);
    return q.get();
  }

  Future<void> softDeleteDuplicateHabitLogs(
    String habitId,
    String logDate, {
    required String keepId,
    required String deletedAtIso,
  }) async {
    final rows = await getActiveHabitLogsByHabitAndDate(habitId, logDate);
    for (final row in rows) {
      if (row.id == keepId) continue;
      await softDeleteHabitLog(row.id, deletedAtIso);
    }
  }

  Future<List<HabitLogRow>> softDeleteActiveHabitLogsByHabitAndDate(
    String habitId,
    String logDate,
    String deletedAtIso,
  ) async {
    final rows = await getActiveHabitLogsByHabitAndDate(habitId, logDate);
    for (final row in rows) {
      await softDeleteHabitLog(row.id, deletedAtIso);
    }
    return rows;
  }

  Future<void> softDeleteHabitLog(String id, String deletedAtIso) async {
    await (update(db.habitLogsTable)..where((l) => l.id.equals(id))).write(
      HabitLogsTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }
}
