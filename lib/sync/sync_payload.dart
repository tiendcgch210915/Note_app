import 'dart:convert';

import '../data/local/database.dart'; // provides generated *Row types from database.g.dart
import '../data/local/tables.dart';
import '../utils/json_utils.dart';

/// Converts Drift row objects into sync JSON payloads that match the
/// API_CONTRACT.md shape for POST /sync/push.
///
/// Rules:
///  - bool fields → true/false (never 0/1)
///  - date-only fields → "YYYY-MM-DD" string
///  - datetime fields → ISO-8601 UTC string
///  - null values included explicitly (server uses them for PATCH semantics)
///  - Computed/server-only fields (streak, times_used) may be sent; server ignores them.
///  - User: ONLY display_name/avatar_url/timezone/settings (NO email/password)
class SyncPayload {
  SyncPayload._();

  // ─── Tag ──────────────────────────────────────────────────────────

  static Map<String, dynamic> fromTag(TagRow row) => {
        'id': row.id,
        'name': row.name,
        'color': row.color,
        'user_id': row.userId,
        'created_at': row.createdAt,
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── Todo ─────────────────────────────────────────────────────────

  static Map<String, dynamic> fromTodo(
    TodoRow row,
    List<String> tagIds,
    List<String> linkedNoteIds,
  ) =>
      {
        'id': row.id,
        'user_id': row.userId,
        'parent_id': row.parentId,
        'title': row.title,
        'description': row.description,
        'status': row.status,
        'position': row.position,
        'is_frog': row.isFrog,
        'frog_date': row.frogDate,
        'is_important': row.isImportant,
        'is_urgent': row.isUrgent,
        'estimated_minutes': row.estimatedMinutes,
        'actual_minutes': row.actualMinutes,
        'start_at': row.startAt,
        'due_at': row.dueAt,
        'scheduled_date': row.scheduledDate,
        'trigger_after_todo_id': row.triggerAfterTodoId,
        'completed_at': row.completedAt,
        // Recurrence fields
        'recurrence_type': row.recurrenceType,
        'recurrence_interval': row.recurrenceInterval,
        'recurrence_days_of_week': row.recurrenceWeekdays,
        'recurrence_end_date': row.recurrenceEndDate,
        'recurrence_template_id': row.recurrenceTemplateId,
        // Junction embed
        'tag_ids': tagIds,
        'linked_note_ids': linkedNoteIds,
        'created_at': row.createdAt,
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── Note ─────────────────────────────────────────────────────────

  static Map<String, dynamic> fromNote(
    NoteRow row,
    List<String> tagIds,
    List<Map<String, dynamic>> noteLinks, // [{target_note_id, label}]
    List<String> linkedTodoIds,
  ) =>
      {
        'id': row.id,
        'user_id': row.userId,
        'title': row.title,
        'type': row.type,
        'body': row.body,
        'cornell_cue': row.cornellCue,
        'cornell_summary': row.cornellSummary,
        'is_pinned': row.isPinned,
        // Junction embeds
        'tag_ids': tagIds,
        'note_links': noteLinks,
        'linked_todo_ids': linkedTodoIds,
        'created_at': row.createdAt,
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── Habit ────────────────────────────────────────────────────────

  static Map<String, dynamic> fromHabit(HabitRow row) => {
        'id': row.id,
        'user_id': row.userId,
        'title': row.title,
        'description': row.description,
        'icon': row.iconName,
        'color': row.color,
        'frequency_type': row.frequencyType,
        'target_per_period': row.targetPerPeriod,
        'active_weekdays': row.activeWeekdays,
        'start_date': row.startDate,
        'end_date': row.endDate,
        'is_archived': row.isArchived,
        // Computed — server ignores but fine to send
        'current_streak': row.currentStreak,
        'longest_streak': row.longestStreak,
        'created_at': row.createdAt,
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── Habit log ────────────────────────────────────────────────────

  static Map<String, dynamic> fromHabitLog(HabitLogRow row) => {
        'id': row.id,
        'habit_id': row.habitId,
        'user_id': row.userId,
        'log_date': row.logDate,
        'completed': row.completed,
        'note': row.note,
        'created_at': row.createdAt,
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── Checklist template ───────────────────────────────────────────

  static Map<String, dynamic> fromTemplate(TemplateRow row) => {
        'id': row.id,
        'user_id': row.userId,
        'title': row.title,
        'description': row.description,
        'icon': row.icon,
        'category': row.category,
        'is_system': row.isSystem,
        'times_used': row.timesUsed,
        'last_used_at': row.lastUsedAt,
        'created_at': row.createdAt,
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── Template item ────────────────────────────────────────────────

  static Map<String, dynamic> fromTemplateItem(TemplateItemRow row) => {
        'id': row.id,
        'template_id': row.templateId,
        'title': row.title,
        'description': row.description,
        'is_required': row.isRequired,
        'position': row.orderIndex, // Drift column = orderIndex, contract key = position
        'created_at': row.createdAt,
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── Run ──────────────────────────────────────────────────────────

  static Map<String, dynamic> fromRun(RunRow row) => {
        'id': row.id,
        'template_id': row.templateId,
        'user_id': row.userId,
        'name': row.name,
        'status': row.status,
        'completed_at': row.completedAt,
        'started_at': row.createdAt, // stored in createdAt, contract key = started_at
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── Run item ─────────────────────────────────────────────────────

  // contract §3.8: run_item push payload does NOT include denormalised fields
  // (title, is_required, order_index come from the template_item, not from here)
  static Map<String, dynamic> fromRunItem(RunItemRow row) => {
        'id': row.id,
        'run_id': row.runId,
        'template_item_id': row.templateItemId,
        'status': row.status,
        'note': row.note,
        'created_at': row.createdAt,
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── User (only safe fields) ──────────────────────────────────────

  static Map<String, dynamic> fromUser(UserRow row) => {
        'id': row.id,
        'display_name': row.displayName,
        'avatar_url': row.avatarUrl,
        'timezone': row.timezone,
        'settings': row.settings != null
            ? jsonDecode(row.settings!)
            : null,
        // NO email, NO password_hash
        'created_at': row.createdAt,
        'updated_at': row.updatedAt,
        'deleted_at': row.deletedAt,
      };

  // ─── Encode helpers ───────────────────────────────────────────────

  static String encode(Map<String, dynamic> map) => jsonEncode(map);

  static Map<String, dynamic> decode(String payload) =>
      jsonDecode(payload) as Map<String, dynamic>;
}

/// Dependency order for sync push (§5 of API contract):
/// tag / habit / template → note / todo parent before child → logs / items
const _entityOrder = [
  'tag',
  'habit',
  'checklist_template',
  'note',
  'todo',
  'checklist_template_item',
  'habit_log',
  'checklist_run',
  'checklist_run_item',
  'user',
];

/// Sort a list of sync queue rows into dependency order for push.
/// Within the same entity type, preserve FIFO order (by queue id).
List<T> sortedByDependency<T>({
  required List<T> rows,
  required String Function(T) getEntityType,
  required int Function(T) getId,
}) {
  return [...rows]..sort((a, b) {
      final ai =
          _entityOrder.indexOf(getEntityType(a)).let((i) => i < 0 ? 99 : i);
      final bi =
          _entityOrder.indexOf(getEntityType(b)).let((i) => i < 0 ? 99 : i);
      if (ai != bi) return ai.compareTo(bi);
      return getId(a).compareTo(getId(b));
    });
}

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
