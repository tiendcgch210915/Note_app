import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../models/habit.dart';
import '../models/habit_log.dart';
import '../utils/habit_streak_utils.dart';
import '../utils/json_utils.dart';
import '../utils/uuid_utils.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_storage.dart';
import 'local/database.dart';
import 'local/model_converters.dart';
import '../sync/connectivity_sync.dart';
import '../sync/sync_payload.dart';

/// Repository cho Group H — Habits. 11 endpoint F-H1..F-H11.
///
/// Strategy:
///  - Habit metadata reads still use REST first and cache into Drift.
///  - Habit log writes are local-first: write Drift, enqueue sync, then
///    ConnectivitySync pushes in the background.
///  - Streak: derived locally from logs for fast/offline UI, then cached via
///    `adoptStreak`. We NEVER enqueue an `update habit` op just to change it.
class HabitsRepository {
  HabitsRepository._();
  static final HabitsRepository instance = HabitsRepository._();
  final ApiClient _client = ApiClient.instance;
  final AppDatabase _db = AppDatabase.instance;

  String get _userId =>
      AuthStorage.instance.currentUserJson?['id'] as String? ?? '';

  bool _belongsToCurrentUser(String rowUserId) {
    final userId = _userId;
    return userId.isEmpty || rowUserId == userId;
  }

  // ─── F-H2 List ────────────────────────────────────────────────

  Future<List<Habit>> list({bool includeArchived = false}) async {
    final resp = await _client.get(
      '/habits',
      query: {'include_archived': includeArchived},
    );
    final items = (resp as Map<String, dynamic>)['items'] as List;
    final habits = items
        .map((e) => Habit.fromJson(e as Map<String, dynamic>))
        .toList();
    await _cacheHabits(habits);
    return _applyArchiveVisibility(habits, includeArchived: includeArchived);
  }

  Future<List<Habit>> listLocal({bool includeArchived = false}) async {
    final rows = includeArchived
        ? await _db.habitsDao.getAllHabits()
        : await _db.habitsDao.getActiveHabits();
    final habits = rows
        .where((row) => _belongsToCurrentUser(row.userId))
        .map(_habitRowToModel)
        .toList();
    habits.sort((a, b) {
      final archivedOrder = (a.isArchived ? 1 : 0).compareTo(
        b.isArchived ? 1 : 0,
      );
      if (archivedOrder != 0) return archivedOrder;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return habits;
  }

  Future<Habit?> getLocalHabit(String id) async {
    final row = await _db.habitsDao.getHabitById(id);
    if (row != null && !_belongsToCurrentUser(row.userId)) return null;
    return row == null ? null : _habitRowToModel(row);
  }

  // ─── F-H3 Detail with recent logs ─────────────────────────────

  Future<({Habit habit, List<HabitLog> recentLogs})> getDetail(
    String id,
  ) async {
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
      final habit = Habit.fromJson(
        (resp as Map<String, dynamic>)['habit'] as Map<String, dynamic>,
      );
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
        body['frequency_type'] as String? ?? 'daily',
      ),
      targetPerPeriod:
          (body['target_per_period'] as num?)?.toInt() ??
          Habit.defaultTargetPerPeriod,
      activeWeekdays: _parseWeekdays(body['active_weekdays'] as String?),
      startDate: jsonDateOnly(
        body['start_date'] as String? ?? formatDateOnly(DateTime.now()),
      ),
      endDate: jsonDateOnlyNullable(body['end_date'] as String?),
    );
    await _upsertHabitWithSync(habit, 'create');
    ConnectivitySync.instance.scheduleWriteSync();
    return habit;
  }

  // ─── F-H4 Update ──────────────────────────────────────────────

  Future<Habit> update(String id, Map<String, dynamic> body) async {
    try {
      final resp = await _client.patch('/habits/$id', body: body);
      final habit = Habit.fromJson(
        (resp as Map<String, dynamic>)['habit'] as Map<String, dynamic>,
      );
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

  Future<Habit> updateLocalFirst(
    Habit current,
    Map<String, dynamic> body,
  ) async {
    final existing = await _db.habitsDao.getHabitById(current.id);
    final now = nowIso();
    final updated = _patchHabit(current, body);
    await _db.habitsDao.upsertHabit(
      HabitsTableCompanion(
        id: Value(updated.id),
        userId: Value(existing?.userId ?? _userId),
        title: Value(updated.title),
        description: Value(updated.description),
        iconName: Value(updated.iconName),
        color: Value(formatColorHex(updated.color)),
        frequencyType: Value(updated.frequencyType.backendValue),
        targetPerPeriod: Value(updated.targetPerPeriod),
        activeWeekdays: Value(updated.activeWeekdays?.join(',') ?? ''),
        startDate: Value(formatDateOnly(updated.startDate)),
        endDate: Value(
          updated.endDate == null ? null : formatDateOnly(updated.endDate!),
        ),
        currentStreak: Value(updated.currentStreak),
        longestStreak: Value(updated.longestStreak),
        isArchived: Value(updated.isArchived),
        createdAt: Value(existing?.createdAt ?? now),
        updatedAt: Value(now),
        deletedAt: const Value(null),
      ),
    );
    final row = await _db.habitsDao.getHabitById(current.id);
    if (row != null) {
      await _db.syncDao.enqueueSyncOp(
        entityType: 'habit',
        entityId: current.id,
        operation: 'update',
        payload: SyncPayload.encode(SyncPayload.fromHabit(row)),
      );
    }
    ConnectivitySync.instance.scheduleWriteSync();
    return updated;
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
    final habit = Habit.fromJson(
      (resp as Map<String, dynamic>)['habit'] as Map<String, dynamic>,
    );
    // Server already has it — cache only, do NOT enqueue.
    await _cacheHabits([habit]);
    return habit;
  }

  Future<Habit> unarchive(String id) async {
    final resp = await _client.post('/habits/$id/unarchive', body: const {});
    final habit = Habit.fromJson(
      (resp as Map<String, dynamic>)['habit'] as Map<String, dynamic>,
    );
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
    final log = await _upsertHabitLogLocalFirst(
      habitId: id,
      logDate: logDate,
      completed: completed,
      note: note,
      updateNote: note != null,
    );
    final streaks = await _adoptEstimatedStreak(id);
    ConnectivitySync.instance.scheduleWriteSync();
    return (
      log: log,
      currentStreak: streaks.current,
      longestStreak: streaks.longest,
    );
  }

  Future<void> applyTodoCompletionProjection({
    required String habitId,
    required DateTime scheduledDate,
  }) async {
    final logDateStr = formatDateOnly(scheduledDate);
    final todos = await _db.todosDao.getLiveTodosForHabitOnDate(
      habitId,
      logDateStr,
    );
    if (todos.isEmpty) return;

    final scheduledDay = jsonDateOnly(logDateStr);
    final completed = todos.every((todo) {
      if (todo.status != 'done' || todo.completedAt == null) return false;
      final completedAt = DateTime.tryParse(todo.completedAt!);
      if (completedAt == null) return false;
      final localCompletedAt = completedAt.toLocal();
      final completedDay = DateTime(
        localCompletedAt.year,
        localCompletedAt.month,
        localCompletedAt.day,
      );
      return !completedDay.isAfter(scheduledDay);
    });

    final now = nowIso();
    final existingRows = await _db.habitsDao.getActiveHabitLogsByHabitAndDate(
      habitId,
      logDateStr,
    );
    final existing = existingRows.isEmpty ? null : existingRows.first;
    final tombstone = await _db.habitsDao.findSoftDeletedHabitLog(
      habitId,
      logDateStr,
    );
    final id = existing?.id ?? tombstone?.id ?? newId();
    final createdAt = existing?.createdAt ?? tombstone?.createdAt ?? now;

    await _db.habitsDao.upsertHabitLog(
      HabitLogsTableCompanion(
        id: Value(id),
        habitId: Value(habitId),
        userId: Value(_userId),
        logDate: Value(logDateStr),
        completed: Value(completed),
        note: Value(existing?.note ?? tombstone?.note),
        createdAt: Value(createdAt),
        updatedAt: Value(now),
        deletedAt: const Value(null),
      ),
    );

    await _softDeleteDuplicateLogsForDate(
      habitId,
      logDateStr,
      keepId: id,
      deletedAtIso: now,
      enqueueDeletes: false,
    );
    await _adoptEstimatedStreak(habitId);
  }

  Future<HabitLog> _upsertHabitLogLocalFirst({
    required String habitId,
    required DateTime logDate,
    bool? completed,
    String? note,
    bool updateNote = false,
  }) async {
    final logDateStr = formatDateOnly(logDate);
    final now = nowIso();
    final existingRows = await _db.habitsDao.getActiveHabitLogsByHabitAndDate(
      habitId,
      logDateStr,
    );
    final existing = existingRows.isEmpty ? null : existingRows.first;

    // Resurrect-local-first: reuse a tombstoned log for the same (habitId, logDate)
    final tombstone = await _db.habitsDao.findSoftDeletedHabitLog(
      habitId,
      logDateStr,
    );
    final id = existing?.id ?? tombstone?.id ?? newId();
    final operation = existing == null && tombstone == null
        ? 'create'
        : 'update';
    final createdAt = existing?.createdAt ?? tombstone?.createdAt ?? now;

    await _db.habitsDao.upsertHabitLog(
      HabitLogsTableCompanion(
        id: Value(id),
        habitId: Value(habitId),
        userId: Value(_userId),
        logDate: Value(logDateStr),
        completed: Value(completed ?? existing?.completed ?? false),
        note: Value(updateNote ? note : existing?.note),
        createdAt: Value(createdAt),
        updatedAt: Value(now),
        deletedAt: const Value(null), // clear tombstone when resurrecting
      ),
    );

    await _softDeleteDuplicateLogsForDate(
      habitId,
      logDateStr,
      keepId: id,
      deletedAtIso: now,
      enqueueDeletes: true,
    );

    final row = await _db.habitsDao.getHabitLogById(id);
    if (row == null) {
      throw const ApiException(0, 'local_write_failed', 'Không lưu được log');
    }
    await _db.syncDao.enqueueSyncOp(
      entityType: 'habit_log',
      entityId: id,
      operation: operation,
      payload: SyncPayload.encode(SyncPayload.fromHabitLog(row)),
    );

    return _habitLogRowToModel(row);
  }

  // ─── F-H8 Patch log ───────────────────────────────────────────

  Future<({HabitLog log, int currentStreak, int longestStreak})> patchLog(
    String id,
    DateTime logDate, {
    bool? completed,
    String? note,
    bool updateNote = false,
  }) async {
    final log = await _upsertHabitLogLocalFirst(
      habitId: id,
      logDate: logDate,
      completed: completed,
      note: note,
      updateNote: updateNote,
    );
    final streaks = await _adoptEstimatedStreak(id);
    ConnectivitySync.instance.scheduleWriteSync();
    return (
      log: log,
      currentStreak: streaks.current,
      longestStreak: streaks.longest,
    );
  }

  // ─── F-H9 Delete log ──────────────────────────────────────────

  Future<({int currentStreak, int longestStreak})> deleteLog(
    String id,
    DateTime logDate,
  ) async {
    final now = nowIso();
    final deletedRows = await _db.habitsDao
        .softDeleteActiveHabitLogsByHabitAndDate(
          id,
          formatDateOnly(logDate),
          now,
        );
    for (final row in deletedRows) {
      await _db.syncDao.enqueueSyncOp(
        entityType: 'habit_log',
        entityId: row.id,
        operation: 'delete',
        payload: jsonEncode({
          'id': row.id,
          'deleted_at': now,
          'updated_at': now,
        }),
      );
    }
    if (deletedRows.isNotEmpty) ConnectivitySync.instance.scheduleWriteSync();

    final streaks = await _adoptEstimatedStreak(id);
    return (currentStreak: streaks.current, longestStreak: streaks.longest);
  }

  // ─── F-H10 Logs in range ──────────────────────────────────────

  Future<List<HabitLog>> getLogs(
    String id, {
    required DateTime from,
    required DateTime to,
  }) async {
    final localLogs = await _getLocalLogs(id, from: from, to: to);

    try {
      final resp = await _client.get(
        '/habits/$id/logs',
        query: {'from': formatDateOnly(from), 'to': formatDateOnly(to)},
      );
      final items = (resp as Map<String, dynamic>)['items'] as List;
      final logs = items
          .map((e) => HabitLog.fromJson(e as Map<String, dynamic>))
          .toList();
      await _cacheLogs(logs);
      final mergedLogs = await _getLocalLogs(id, from: from, to: to);
      return mergedLogs.isNotEmpty ? mergedLogs : logs;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') return localLogs;
      rethrow;
    }
  }

  // ─── F-H11 Calendar (all habits) ──────────────────────────────

  /// Trả `Map<date -> Map<habitId, completed>>`.
  Future<Map<DateTime, Map<String, bool>>> getCalendar({
    required DateTime from,
    required DateTime to,
  }) async {
    final localCalendar = await _getLocalCalendar(from: from, to: to);

    try {
      final resp = await _client.get(
        '/habits/calendar',
        query: {'from': formatDateOnly(from), 'to': formatDateOnly(to)},
      );
      final byDate =
          (resp as Map<String, dynamic>)['by_date'] as Map<String, dynamic>? ??
          {};
      final result = <DateTime, Map<String, bool>>{};
      byDate.forEach((dateStr, value) {
        final habitsMap = value as Map<String, dynamic>;
        result[jsonDateOnly(dateStr)] = habitsMap.map(
          (k, v) => MapEntry(k, jsonBool(v)),
        );
      });
      for (final entry in localCalendar.entries) {
        result
            .putIfAbsent(entry.key, () => <String, bool>{})
            .addAll(entry.value);
      }
      return result;
    } on ApiException catch (e) {
      if (e.code == 'no_connection') return localCalendar;
      rethrow;
    }
  }

  Future<Map<DateTime, Map<String, bool>>> getCalendarLocal({
    required DateTime from,
    required DateTime to,
  }) {
    return _getLocalCalendar(from: from, to: to);
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
    final touchedDates =
        <String, ({String habitId, String logDate, String keepId})>{};
    for (final log in logs) {
      await _db.habitsDao.upsertHabitLog(habitLogToCompanion(log, userId));
      final logDate = formatDateOnly(log.logDate);
      touchedDates['${log.habitId}|$logDate'] = (
        habitId: log.habitId,
        logDate: logDate,
        keepId: log.id,
      );
    }
    final now = nowIso();
    for (final entry in touchedDates.values) {
      final activeRows = await _db.habitsDao.getActiveHabitLogsByHabitAndDate(
        entry.habitId,
        entry.logDate,
      );
      if (activeRows.isEmpty) continue;
      await _softDeleteDuplicateLogsForDate(
        entry.habitId,
        entry.logDate,
        keepId: entry.keepId,
        deletedAtIso: now,
        enqueueDeletes: false,
      );
    }
  }

  Future<List<HabitLog>> _getLocalLogs(
    String habitId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.habitsDao.getLogsForRange(
      habitId,
      formatDateOnly(from),
      formatDateOnly(to),
    );
    final logs = _dedupeLogRowsByDate(
      rows.where((row) => _belongsToCurrentUser(row.userId)).toList(),
    ).map(_habitLogRowToModel).toList();
    logs.sort((a, b) => a.logDate.compareTo(b.logDate));
    return logs;
  }

  Future<Map<DateTime, Map<String, bool>>> _getLocalCalendar({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.habitsDao.getAllLogsForRange(
      formatDateOnly(from),
      formatDateOnly(to),
    );
    final result = <DateTime, Map<String, bool>>{};
    for (final row in rows) {
      if (!_belongsToCurrentUser(row.userId)) continue;
      final date = jsonDateOnly(row.logDate);
      result
          .putIfAbsent(date, () => <String, bool>{})
          .putIfAbsent(row.habitId, () => row.completed);
    }
    return result;
  }

  List<HabitLogRow> _dedupeLogRowsByDate(List<HabitLogRow> rows) {
    final byDate = <String, HabitLogRow>{};
    for (final row in rows) {
      byDate.putIfAbsent(row.logDate, () => row);
    }
    return byDate.values.toList();
  }

  Future<void> _softDeleteDuplicateLogsForDate(
    String habitId,
    String logDate, {
    required String keepId,
    required String deletedAtIso,
    required bool enqueueDeletes,
  }) async {
    final rows = await _db.habitsDao.getActiveHabitLogsByHabitAndDate(
      habitId,
      logDate,
    );
    for (final row in rows) {
      if (row.id == keepId) continue;
      await _db.habitsDao.softDeleteHabitLog(row.id, deletedAtIso);
      if (!enqueueDeletes) continue;
      await _db.syncDao.enqueueSyncOp(
        entityType: 'habit_log',
        entityId: row.id,
        operation: 'delete',
        payload: jsonEncode({
          'id': row.id,
          'deleted_at': deletedAtIso,
          'updated_at': deletedAtIso,
        }),
      );
    }
  }

  HabitLog _habitLogRowToModel(HabitLogRow row) {
    return HabitLog(
      id: row.id,
      habitId: row.habitId,
      logDate: jsonDateOnly(row.logDate),
      completed: row.completed,
      note: row.note,
    );
  }

  Future<({int current, int longest})> _adoptEstimatedStreak(
    String habitId,
  ) async {
    final habit = await _db.habitsDao.getHabitById(habitId);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final from = habit?.startDate != null
        ? jsonDateOnly(habit!.startDate)
        : todayOnly.subtract(const Duration(days: 365));
    final logs = await _getLocalLogs(habitId, from: from, to: todayOnly);
    final streak = deriveHabitStreakFromLogs(
      logs: logs,
      today: todayOnly,
      startDate: from,
      fallbackCurrent: habit?.currentStreak ?? 0,
      fallbackLongest: habit?.longestStreak ?? 0,
    );
    final current = streak.current;
    final longest = streak.longest;
    if (habit != null) {
      await _db.habitsDao.adoptStreak(habitId, current, longest, nowIso());
    }
    return (current: current, longest: longest);
  }

  Future<List<Habit>> _applyArchiveVisibility(
    List<Habit> habits, {
    required bool includeArchived,
  }) async {
    final visible = includeArchived
        ? await _withCachedArchived(habits)
        : habits.where((habit) => !habit.isArchived).toList();
    visible.sort((a, b) {
      final archivedOrder = (a.isArchived ? 1 : 0).compareTo(
        b.isArchived ? 1 : 0,
      );
      if (archivedOrder != 0) return archivedOrder;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return visible;
  }

  Future<List<Habit>> _withCachedArchived(List<Habit> habits) async {
    final byId = {for (final habit in habits) habit.id: habit};
    final cached = await _db.habitsDao.getAllHabits();
    for (final row in cached) {
      if (!_belongsToCurrentUser(row.userId)) continue;
      if (!row.isArchived || byId.containsKey(row.id)) continue;
      byId[row.id] = _habitRowToModel(row);
    }
    return byId.values.toList();
  }

  Habit _habitRowToModel(HabitRow row) {
    return Habit(
      id: row.id,
      title: row.title,
      description: row.description,
      iconName: row.iconName,
      icon: Habit.iconFor(row.iconName),
      color: jsonColor(row.color),
      frequencyType: FrequencyType.parse(row.frequencyType),
      targetPerPeriod: row.targetPerPeriod,
      activeWeekdays: _parseWeekdays(row.activeWeekdays),
      startDate: jsonDateOnly(row.startDate),
      endDate: jsonDateOnlyNullable(row.endDate),
      currentStreak: row.currentStreak,
      longestStreak: row.longestStreak,
      isArchived: row.isArchived,
    );
  }

  Habit _patchHabit(Habit current, Map<String, dynamic> body) {
    final frequency = body.containsKey('frequency_type')
        ? FrequencyType.parse(body['frequency_type'] as String? ?? 'daily')
        : current.frequencyType;
    final activeWeekdays = body.containsKey('active_weekdays')
        ? _parseWeekdays(body['active_weekdays'] as String?)
        : current.activeWeekdays;
    final startDate = body.containsKey('start_date')
        ? jsonDateOnly(body['start_date'] as String)
        : current.startDate;
    final endDate = body.containsKey('end_date')
        ? jsonDateOnlyNullable(body['end_date'] as String?)
        : current.endDate;

    return Habit(
      id: current.id,
      title: body.containsKey('title')
          ? body['title'] as String
          : current.title,
      description: body.containsKey('description')
          ? body['description'] as String?
          : current.description,
      iconName: body.containsKey('icon')
          ? body['icon'] as String?
          : current.iconName,
      icon: Habit.iconFor(
        body.containsKey('icon') ? body['icon'] as String? : current.iconName,
      ),
      color: body.containsKey('color')
          ? jsonColor(body['color'] as String? ?? '#4CAF50')
          : current.color,
      frequencyType: frequency,
      targetPerPeriod: body.containsKey('target_per_period')
          ? (body['target_per_period'] as num?)?.toInt() ??
                current.targetPerPeriod
          : current.targetPerPeriod,
      activeWeekdays: activeWeekdays,
      startDate: startDate,
      endDate: endDate,
      currentStreak: current.currentStreak,
      longestStreak: current.longestStreak,
      isArchived: current.isArchived,
    );
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

  Future<void> _enqueueOfflineHabitUpdate(
    String habitId,
    Map<String, dynamic> patch,
  ) async {
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
