import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../models/habit.dart';
import '../models/habit_log.dart';
import '../utils/json_utils.dart';
import '../utils/uuid_utils.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_storage.dart';
import 'local/database.dart';
import 'local/model_converters.dart';
import 'local/tables.dart';
import '../sync/connectivity_sync.dart';
import '../sync/sync_payload.dart';

/// Repository cho Group H — Habits. 11 endpoint F-H1..F-H11.
///
/// Strategy mirrors TodosRepository:
///  - Reads: REST first → cache in Drift.
///  - Writes: REST first; on success → write Drift + enqueue.
///            On no_connection → write Drift + enqueue (offline mode).
///  - Streak: ONLY updated via `adoptStreak` (server-authoritative).
///            We NEVER enqueue an `update habit` op just to change streak.
class HabitsRepository {
  HabitsRepository._();
  static final HabitsRepository instance = HabitsRepository._();
  final ApiClient _client = ApiClient.instance;
  final AppDatabase _db = AppDatabase.instance;

  String get _userId =>
      AuthStorage.instance.currentUserJson?['id'] as String? ?? '';

  // ─── F-H2 List ────────────────────────────────────────────────

  Future<List<Habit>> list({bool includeArchived = false}) async {
    final resp = await _client.get(
      '/habits',
      query: {'include_archived': includeArchived},
    );
    final items = (resp as Map<String, dynamic>)['items'] as List;
    final habits =
        items.map((e) => Habit.fromJson(e as Map<String, dynamic>)).toList();
    await _cacheHabits(habits);
    return habits;
  }

  // ─── F-H3 Detail with recent logs ─────────────────────────────

  Future<({Habit habit, List<HabitLog> recentLogs})> getDetail(
      String id) async {
    final resp = await _client.get('/habits/$id');
    final map = resp as Map<String, dynamic>;
    final habit = Habit.fromJson(map['habit'] as Map<String, dynamic>);
    final logs = ((map['recent_logs'] as List?) ?? const [])
        .map((e) => HabitLog.fromJson(e as Map<String, dynamic>))
        .toList();
    await _cacheHabits([habit]);
    await _cacheLogs(logs);
    return (habit: habit, recentLogs: logs);
  }

  // ─── F-H1 Create ──────────────────────────────────────────────

  Future<Habit> create(Map<String, dynamic> body) async {
    try {
      final resp = await _client.post('/habits', body: body);
      final habit =
          Habit.fromJson((resp as Map<String, dynamic>)['habit'] as Map<String, dynamic>);
      // Server already has it — cache locally only, do NOT enqueue.
      await _cacheHabits([habit]);
      return habit;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') return _createOffline(body);
      rethrow;
    }
  }

  Future<Habit> _createOffline(Map<String, dynamic> body) async {
    final habit = Habit(
      id: newId(),
      title: body['title'] as String,
      description: body['description'] as String?,
      iconName: body['icon'] as String?,
      color: jsonColor(body['color'] as String? ?? '#4CAF50'),
      frequencyType: FrequencyType.parse(
          body['frequency_type'] as String? ?? 'daily'),
      targetPerPeriod: (body['target_per_period'] as num?)?.toInt() ?? 1,
      activeWeekdays: _parseWeekdays(body['active_weekdays'] as String?),
      startDate: jsonDateOnly(
          body['start_date'] as String? ?? formatDateOnly(DateTime.now())),
    );
    await _upsertHabitWithSync(habit, 'create');
    ConnectivitySync.instance.scheduleWriteSync();
    return habit;
  }

  // ─── F-H4 Update ──────────────────────────────────────────────

  Future<Habit> update(String id, Map<String, dynamic> body) async {
    try {
      final resp = await _client.patch('/habits/$id', body: body);
      final habit =
          Habit.fromJson((resp as Map<String, dynamic>)['habit'] as Map<String, dynamic>);
      // Server already has it — cache locally only, do NOT enqueue.
      await _cacheHabits([habit]);
      return habit;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') {
        await _enqueueOfflineHabitUpdate(id, body);
        rethrow;
      }
      rethrow;
    }
  }

  // ─── F-H5 Delete ──────────────────────────────────────────────

  Future<void> delete(String id) async {
    final now = nowIso();
    bool isOffline = false;
    try {
      await _client.delete('/habits/$id');
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      isOffline = true;
    }
    await _db.habitsDao.softDeleteHabit(id, now);
    if (isOffline) {
      await _db.syncDao.enqueueSyncOp(
        entityType: 'habit',
        entityId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'deleted_at': now, 'updated_at': now}),
      );
      ConnectivitySync.instance.scheduleWriteSync();
    }
  }

  // ─── F-H6 Archive/Unarchive ───────────────────────────────────

  Future<Habit> archive(String id) async {
    final resp = await _client.post('/habits/$id/archive', body: const {});
    final habit =
        Habit.fromJson((resp as Map<String, dynamic>)['habit'] as Map<String, dynamic>);
    // Server already has it — cache only, do NOT enqueue.
    await _cacheHabits([habit]);
    return habit;
  }

  Future<Habit> unarchive(String id) async {
    final resp = await _client.post('/habits/$id/unarchive', body: const {});
    final habit =
        Habit.fromJson((resp as Map<String, dynamic>)['habit'] as Map<String, dynamic>);
    await _cacheHabits([habit]);
    return habit;
  }

  // ─── F-H7 Log habit ───────────────────────────────────────────

  Future<({HabitLog log, int currentStreak, int longestStreak})> logHabit(
    String id, {
    required DateTime logDate,
    bool completed = true,
    String? note,
  }) async {
    try {
      final resp = await _client.post(
        '/habits/$id/logs',
        body: {
          'log_date': formatDateOnly(logDate),
          'completed': completed,
          if (note != null) 'note': note,
        },
      );
      final map = resp as Map<String, dynamic>;
      final streaks = map['streaks'] as Map<String, dynamic>;
      final log = HabitLog.fromJson(map['log'] as Map<String, dynamic>);
      // Server already has this log — cache locally only, do NOT enqueue.
      await _cacheLogs([log]);
      // Adopt server-authoritative streak (no sync enqueue for streak)
      await _db.habitsDao.adoptStreak(
        id,
        (streaks['current'] as num).toInt(),
        (streaks['longest'] as num).toInt(),
        DateTime.now().toUtc().toIso8601String(),
      );
      return (
        log: log,
        currentStreak: (streaks['current'] as num).toInt(),
        longestStreak: (streaks['longest'] as num).toInt(),
      );
    } on ApiException catch (e) {
      if (e.code == 'no_connection') {
        final log = await _logHabitOffline(
          habitId: id,
          logDate: logDate,
          completed: completed,
          note: note,
        );
        return (log: log, currentStreak: 0, longestStreak: 0);
      }
      rethrow;
    }
  }

  /// Offline log creation with resurrect-local-first (contract §3.5).
  /// HabitLog model has no userId/timestamps, so we write the companion directly.
  Future<HabitLog> _logHabitOffline({
    required String habitId,
    required DateTime logDate,
    required bool completed,
    String? note,
  }) async {
    final logDateStr = formatDateOnly(logDate);
    final now = nowIso();

    // Resurrect-local-first: reuse a tombstoned log for the same (habitId, logDate)
    final tombstone =
        await _db.habitsDao.findSoftDeletedHabitLog(habitId, logDateStr);
    final id = tombstone?.id ?? newId();
    final operation = tombstone != null ? 'update' : 'create';

    await _db.habitsDao.upsertHabitLog(HabitLogsTableCompanion(
      id: Value(id),
      habitId: Value(habitId),
      userId: Value(_userId),
      logDate: Value(logDateStr),
      completed: Value(completed),
      note: Value(note),
      createdAt: Value(tombstone?.createdAt ?? now),
      updatedAt: Value(now),
      deletedAt: const Value(null), // clear tombstone when resurrecting
    ));

    final row = await _db.habitsDao.getHabitLogById(id);
    if (row != null) {
      await _db.syncDao.enqueueSyncOp(
        entityType: 'habit_log',
        entityId: id,
        operation: operation,
        payload: SyncPayload.encode(SyncPayload.fromHabitLog(row)),
      );
    }
    ConnectivitySync.instance.scheduleWriteSync();

    return HabitLog(
      id: id,
      habitId: habitId,
      logDate: logDate,
      completed: completed,
      note: note,
    );
  }

  // ─── F-H8 Patch log ───────────────────────────────────────────

  Future<({HabitLog log, int currentStreak, int longestStreak})> patchLog(
    String id,
    DateTime logDate, {
    bool? completed,
    String? note,
  }) async {
    try {
      final resp = await _client.patch(
        '/habits/$id/logs/${formatDateOnly(logDate)}',
        body: {
          if (completed != null) 'completed': completed,
          if (note != null) 'note': note,
        },
      );
      final map = resp as Map<String, dynamic>;
      final streaks = map['streaks'] as Map<String, dynamic>;
      final log = HabitLog.fromJson(map['log'] as Map<String, dynamic>);
      // Server already has this — cache locally only, do NOT enqueue.
      await _cacheLogs([log]);
      await _db.habitsDao.adoptStreak(
        id,
        (streaks['current'] as num).toInt(),
        (streaks['longest'] as num).toInt(),
        DateTime.now().toUtc().toIso8601String(),
      );
      return (
        log: log,
        currentStreak: (streaks['current'] as num).toInt(),
        longestStreak: (streaks['longest'] as num).toInt(),
      );
    } on ApiException catch (e) {
      if (e.code == 'no_connection') {
        // Enqueue an update for the existing log
        final existing = await _db.habitsDao
            .getHabitLogByHabitAndDate(id, formatDateOnly(logDate));
        if (existing != null) {
          await _db.syncDao.enqueueSyncOp(
            entityType: 'habit_log',
            entityId: existing.id,
            operation: 'update',
            payload: SyncPayload.encode(SyncPayload.fromHabitLog(existing)),
          );
          ConnectivitySync.instance.scheduleWriteSync();
        }
        rethrow;
      }
      rethrow;
    }
  }

  // ─── F-H9 Delete log ──────────────────────────────────────────

  Future<({int currentStreak, int longestStreak})> deleteLog(
    String id,
    DateTime logDate,
  ) async {
    final now = nowIso();
    Map<String, dynamic>? streaks;
    bool isOffline = false;
    try {
      final resp =
          await _client.delete('/habits/$id/logs/${formatDateOnly(logDate)}');
      streaks =
          (resp as Map<String, dynamic>)['streaks'] as Map<String, dynamic>?;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      isOffline = true;
    }

    // Soft-delete locally regardless
    final existing = await _db.habitsDao
        .getHabitLogByHabitAndDate(id, formatDateOnly(logDate));
    if (existing != null) {
      await _db.habitsDao.softDeleteHabitLog(existing.id, now);
      // Only enqueue when offline — server already processed it when online.
      if (isOffline) {
        await _db.syncDao.enqueueSyncOp(
          entityType: 'habit_log',
          entityId: existing.id,
          operation: 'delete',
          payload: jsonEncode({
            'id': existing.id,
            'deleted_at': now,
            'updated_at': now,
          }),
        );
        ConnectivitySync.instance.scheduleWriteSync();
      }
    }

    return (
      currentStreak: (streaks?['current'] as num?)?.toInt() ?? 0,
      longestStreak: (streaks?['longest'] as num?)?.toInt() ?? 0,
    );
  }

  // ─── F-H10 Logs in range ──────────────────────────────────────

  Future<List<HabitLog>> getLogs(
    String id, {
    required DateTime from,
    required DateTime to,
  }) async {
    final resp = await _client.get(
      '/habits/$id/logs',
      query: {
        'from': formatDateOnly(from),
        'to': formatDateOnly(to),
      },
    );
    final items = (resp as Map<String, dynamic>)['items'] as List;
    final logs =
        items.map((e) => HabitLog.fromJson(e as Map<String, dynamic>)).toList();
    await _cacheLogs(logs);
    return logs;
  }

  // ─── F-H11 Calendar (all habits) ──────────────────────────────

  /// Trả `Map<date -> Map<habitId, completed>>`.
  Future<Map<DateTime, Map<String, bool>>> getCalendar({
    required DateTime from,
    required DateTime to,
  }) async {
    final resp = await _client.get(
      '/habits/calendar',
      query: {
        'from': formatDateOnly(from),
        'to': formatDateOnly(to),
      },
    );
    final byDate =
        (resp as Map<String, dynamic>)['by_date'] as Map<String, dynamic>? ??
            {};
    final result = <DateTime, Map<String, bool>>{};
    byDate.forEach((dateStr, value) {
      final habitsMap = value as Map<String, dynamic>;
      result[jsonDateOnly(dateStr)] =
          habitsMap.map((k, v) => MapEntry(k, jsonBool(v)));
    });
    return result;
  }

  // ─── Drift helpers ────────────────────────────────────────────

  Future<void> _cacheHabits(List<Habit> habits) async {
    if (habits.isEmpty) return;
    final userId = _userId;
    await _db.habitsDao.upsertHabits(
      habits.map((h) => habitToCompanion(h, userId)).toList(),
    );
  }

  Future<void> _cacheLogs(List<HabitLog> logs) async {
    if (logs.isEmpty) return;
    final userId = _userId;
    for (final log in logs) {
      await _db.habitsDao.upsertHabitLog(habitLogToCompanion(log, userId));
    }
  }

  Future<void> _upsertHabitWithSync(Habit habit, String operation) async {
    final userId = _userId;
    await _db.habitsDao.upsertHabit(habitToCompanion(habit, userId));
    final row = await _db.habitsDao.getHabitById(habit.id);
    if (row == null) return;
    await _db.syncDao.enqueueSyncOp(
      entityType: 'habit',
      entityId: habit.id,
      operation: operation,
      payload: SyncPayload.encode(SyncPayload.fromHabit(row)),
    );
  }

  Future<void> _upsertLogWithSync(HabitLog log, String operation) async {
    final userId = _userId;
    await _db.habitsDao.upsertHabitLog(habitLogToCompanion(log, userId));
    final row = await _db.habitsDao.getHabitLogById(log.id);
    if (row == null) return;
    // Contract: tick habit_log → enqueue 'habit_log' op ONLY, NEVER 'habit' op
    await _db.syncDao.enqueueSyncOp(
      entityType: 'habit_log',
      entityId: log.id,
      operation: operation,
      payload: SyncPayload.encode(SyncPayload.fromHabitLog(row)),
    );
  }

  Future<void> _enqueueOfflineHabitUpdate(
      String habitId, Map<String, dynamic> patch) async {
    final existing = await _db.habitsDao.getHabitById(habitId);
    if (existing == null) return;
    final payload = SyncPayload.fromHabit(existing);
    final merged = {...payload, ...patch};
    await _db.syncDao.enqueueSyncOp(
      entityType: 'habit',
      entityId: habitId,
      operation: 'update',
      payload: SyncPayload.encode(merged),
    );
  }

  // ─── Tiny helpers ─────────────────────────────────────────────

  List<int>? _parseWeekdays(String? s) {
    if (s == null || s.isEmpty) return null;
    return s.split(',').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  }
}
