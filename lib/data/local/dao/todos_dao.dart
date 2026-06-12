import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'todos_dao.g.dart';

@DriftAccessor(tables: [TodosTable, TodoTagsTable, TagsTable, NoteTagsTable])
class TodosDao extends DatabaseAccessor<AppDatabase> with _$TodosDaoMixin {
  TodosDao(super.db);

  // ─── Upsert ───────────────────────────────────────────────────────

  Future<void> upsertTodo(TodosTableCompanion row) async {
    await into(db.todosTable).insertOnConflictUpdate(row);
  }

  Future<void> upsertTodos(List<TodosTableCompanion> rows) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(db.todosTable, rows);
    });
  }

  // ─── Reads ────────────────────────────────────────────────────────

  Future<TodoRow?> getTodoById(String id) {
    return (select(
      db.todosTable,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
  }

  /// Today's todos (scheduled_date = today, not done, not deleted).
  Future<List<TodoRow>> getTodayTodos(String dateOnly) {
    return (select(db.todosTable)..where(
          (t) =>
              t.scheduledDate.equals(dateOnly) &
              t.deletedAt.isNull() &
              t.status.isNotIn(const ['done', 'archived']),
        ))
        .get();
  }

  /// Upcoming todos (scheduled_date > today, not done).
  Future<List<TodoRow>> getUpcomingTodos(String dateOnly) {
    return (select(db.todosTable)
          ..where(
            (t) =>
                t.scheduledDate.isNotNull() &
                t.scheduledDate.isBiggerThanValue(dateOnly) &
                t.deletedAt.isNull() &
                t.status.isNotIn(const ['done', 'archived']),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.scheduledDate)]))
        .get();
  }

  /// Overdue todos (scheduled_date < today, not done).
  Future<List<TodoRow>> getOverdueTodos(String dateOnly) {
    return (select(db.todosTable)
          ..where(
            (t) =>
                t.scheduledDate.isNotNull() &
                t.scheduledDate.isSmallerThanValue(dateOnly) &
                t.deletedAt.isNull() &
                t.status.isNotIn(const ['done', 'archived']),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.scheduledDate)]))
        .get();
  }

  /// Done todos (top-level only, newest first), with optional cursor by id.
  Future<List<TodoRow>> getDoneTodos({int limit = 20, String? afterId}) {
    final q = select(db.todosTable)
      ..where(
        (t) =>
            t.status.equals('done') &
            t.parentId.isNull() &
            t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.completedAt)])
      ..limit(limit);
    return q.get();
  }

  /// Subtasks of a given parent todo.
  Future<List<TodoRow>> getSubtasks(String parentId) {
    return (select(db.todosTable)
          ..where((t) => t.parentId.equals(parentId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  // ─── Tags for a todo ─────────────────────────────────────────────

  Future<List<TagRow>> getTagsForTodo(String todoId) async {
    final junctions = await (select(
      db.todoTagsTable,
    )..where((j) => j.todoId.equals(todoId))).get();
    if (junctions.isEmpty) return const [];
    final tagIds = junctions.map((j) => j.tagId).toList();
    return (select(
      db.tagsTable,
    )..where((t) => t.id.isIn(tagIds) & t.deletedAt.isNull())).get();
  }

  Future<void> upsertTag(TagsTableCompanion row) async {
    await into(db.tagsTable).insertOnConflictUpdate(row);
  }

  Future<void> upsertTags(List<TagsTableCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(db.tagsTable, rows);
    });
  }

  Future<TagRow?> getTagById(String id) {
    return (select(
      db.tagsTable,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
  }

  Future<List<TagRow>> getTags({
    String? q,
    bool onlyUsedByTodos = false,
  }) async {
    final rows =
        await (select(db.tagsTable)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.name)]))
            .get();
    final usedIds = onlyUsedByTodos
        ? (await select(db.todoTagsTable).get()).map((j) => j.tagId).toSet()
        : null;
    final needle = q == null || q.trim().isEmpty ? null : _normalizeTagName(q);
    return rows
        .where((row) {
          if (usedIds != null && !usedIds.contains(row.id)) return false;
          if (needle == null) return true;
          return _normalizeTagName(row.name).contains(needle);
        })
        .toList(growable: false);
  }

  Future<TagRow?> findTagByNameInsensitive(String name, String userId) async {
    final normalized = _normalizeTagName(name);
    final rows = await (select(
      db.tagsTable,
    )..where((t) => t.userId.equals(userId) & t.deletedAt.isNull())).get();
    for (final row in rows) {
      if (_normalizeTagName(row.name) == normalized) return row;
    }
    return null;
  }

  /// Resurrect-local-first (contract §3.3): find a soft-deleted tag with the
  /// same (name, userId) so callers can reuse its id instead of minting a new
  /// one — avoids a server-side duplicate when re-creating a previously deleted tag.
  Future<TagRow?> findSoftDeletedTagByName(String name, String userId) {
    return (select(db.tagsTable)..where(
          (t) =>
              t.name.equals(name) &
              t.userId.equals(userId) &
              t.deletedAt.isNotNull(),
        ))
        .getSingleOrNull();
  }

  Future<TagRow?> findSoftDeletedTagByNameInsensitive(
    String name,
    String userId,
  ) async {
    final normalized = _normalizeTagName(name);
    final rows = await (select(
      db.tagsTable,
    )..where((t) => t.userId.equals(userId) & t.deletedAt.isNotNull())).get();
    for (final row in rows) {
      if (_normalizeTagName(row.name) == normalized) return row;
    }
    return null;
  }

  Future<void> softDeleteTag(String id, String deletedAtIso) async {
    await transaction(() async {
      await (update(db.tagsTable)..where((t) => t.id.equals(id))).write(
        TagsTableCompanion(
          deletedAt: Value(deletedAtIso),
          updatedAt: Value(deletedAtIso),
        ),
      );
      await (delete(db.todoTagsTable)..where((j) => j.tagId.equals(id))).go();
      await (delete(db.noteTagsTable)..where((j) => j.tagId.equals(id))).go();
    });
  }

  Future<void> setTodoTags(String todoId, List<String> tagIds) async {
    await transaction(() async {
      // Remove old junctions
      await (delete(
        db.todoTagsTable,
      )..where((j) => j.todoId.equals(todoId))).go();
      // Insert new
      if (tagIds.isNotEmpty) {
        await batch((b) {
          b.insertAllOnConflictUpdate(
            db.todoTagsTable,
            tagIds
                .map(
                  (tid) =>
                      TodoTagsTableCompanion.insert(todoId: todoId, tagId: tid),
                )
                .toList(),
          );
        });
      }
    });
  }

  Future<void> touchTodo(String todoId, String updatedAtIso) async {
    await (update(db.todosTable)..where((t) => t.id.equals(todoId))).write(
      TodosTableCompanion(updatedAt: Value(updatedAtIso)),
    );
  }

  Future<List<TodoRow>> getTodosForTag(String tagId) async {
    final links = await (select(
      db.todoTagsTable,
    )..where((j) => j.tagId.equals(tagId))).get();
    if (links.isEmpty) return const [];
    final todoIds = links.map((j) => j.todoId).toList();
    return (select(
      db.todosTable,
    )..where((t) => t.id.isIn(todoIds) & t.deletedAt.isNull())).get();
  }

  // ─── Soft delete ──────────────────────────────────────────────────

  Future<void> softDeleteTodo(String id, String deletedAtIso) async {
    await (update(db.todosTable)..where((t) => t.id.equals(id))).write(
      TodosTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  /// Remove junction rows whose todoId is in [tombstoneIds].
  /// Used by self-heal after pull.
  Future<void> cleanJunctionsForDeletedTodos(List<String> tombstoneIds) async {
    if (tombstoneIds.isEmpty) return;
    await (delete(
      db.todoTagsTable,
    )..where((j) => j.todoId.isIn(tombstoneIds))).go();
  }

  // ─── All todos for sync push ───────────────────────────────────────

  Future<List<TodoRow>> getAllNonDeletedTodos() {
    return (select(db.todosTable)..where((t) => t.deletedAt.isNull())).get();
  }

  Future<List<TodoTagRow>> getAllTodoTags() {
    return select(db.todoTagsTable).get();
  }

  // ─── Recurrence queries ───────────────────────────────────────────

  /// All rows where recurrence_type IS NOT NULL AND recurrence_template_id
  /// IS NULL — i.e. they ARE templates, not instances.
  Future<List<TodoRow>> getRecurrenceTemplates() {
    return (select(db.todosTable)..where(
          (t) =>
              t.recurrenceType.isNotNull() &
              t.recurrenceTemplateId.isNull() &
              t.deletedAt.isNull(),
        ))
        .get();
  }

  /// All instance rows that point to [templateId].
  Future<List<TodoRow>> getInstancesForTemplate(String templateId) {
    return (select(db.todosTable)..where(
          (t) =>
              t.recurrenceTemplateId.equals(templateId) & t.deletedAt.isNull(),
        ))
        .get();
  }

  /// Returns true if an instance for [templateId] with [dateOnly]
  /// (format "YYYY-MM-DD") already exists (dedup check).
  Future<bool> instanceExistsForDate(String templateId, String dateOnly) async {
    final row =
        await (select(db.todosTable)
              ..where(
                (t) =>
                    t.recurrenceTemplateId.equals(templateId) &
                    t.scheduledDate.equals(dateOnly) &
                    t.deletedAt.isNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Soft-delete all non-done instances of [templateId] whose
  /// scheduled_date >= [fromDateInclusive].
  Future<void> softDeleteFutureInstances(
    String templateId,
    String fromDateInclusive,
    String deletedAtIso,
  ) {
    return (update(db.todosTable)..where(
          (t) =>
              t.recurrenceTemplateId.equals(templateId) &
              t.scheduledDate.isBiggerOrEqualValue(fromDateInclusive) &
              t.status.isNotIn(const ['done']) &
              t.deletedAt.isNull(),
        ))
        .write(
          TodosTableCompanion(
            deletedAt: Value(deletedAtIso),
            updatedAt: Value(deletedAtIso),
          ),
        );
  }

  /// Soft-delete ALL instances of [templateId] (used by "delete all" scope).
  Future<void> softDeleteAllInstances(String templateId, String deletedAtIso) {
    return (update(db.todosTable)..where(
          (t) =>
              t.recurrenceTemplateId.equals(templateId) & t.deletedAt.isNull(),
        ))
        .write(
          TodosTableCompanion(
            deletedAt: Value(deletedAtIso),
            updatedAt: Value(deletedAtIso),
          ),
        );
  }

  static String _normalizeTagName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}
