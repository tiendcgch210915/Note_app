import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'notes_dao.g.dart';

@DriftAccessor(tables: [NotesTable, NoteTagsTable, TagsTable, NoteLinksTable, NoteTodoLinksTable])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  // ─── Upsert ───────────────────────────────────────────────────────

  Future<void> upsertNote(NotesTableCompanion row) async {
    await into(db.notesTable).insertOnConflictUpdate(row);
  }

  Future<void> upsertNotes(List<NotesTableCompanion> rows) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(db.notesTable, rows);
    });
  }

  // ─── Reads ────────────────────────────────────────────────────────

  Future<NoteRow?> getNoteById(String id) {
    return (select(db.notesTable)
          ..where((n) => n.id.equals(id) & n.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<List<NoteRow>> getNotes({String? q, int limit = 50}) {
    final query = select(db.notesTable)
      ..where((n) => n.deletedAt.isNull())
      ..orderBy([
        (n) => OrderingTerm.desc(n.isPinned),
        (n) => OrderingTerm.desc(n.updatedAt),
      ])
      ..limit(limit);
    if (q != null && q.isNotEmpty) {
      query.where((n) => n.title.contains(q) | n.body.contains(q));
    }
    return query.get();
  }

  Future<List<TagRow>> getTagsForNote(String noteId) async {
    final junctions = await (select(db.noteTagsTable)
          ..where((j) => j.noteId.equals(noteId)))
        .get();
    if (junctions.isEmpty) return const [];
    final tagIds = junctions.map((j) => j.tagId).toList();
    return (select(db.tagsTable)
          ..where((t) => t.id.isIn(tagIds) & t.deletedAt.isNull()))
        .get();
  }

  Future<void> setNoteTags(String noteId, List<String> tagIds) async {
    await transaction(() async {
      await (delete(db.noteTagsTable)
            ..where((j) => j.noteId.equals(noteId)))
          .go();
      if (tagIds.isNotEmpty) {
        await batch((b) {
          b.insertAllOnConflictUpdate(
            db.noteTagsTable,
            tagIds
                .map((tid) => NoteTagsTableCompanion.insert(
                      noteId: noteId,
                      tagId: tid,
                    ))
                .toList(),
          );
        });
      }
    });
  }

  // ─── Note links ───────────────────────────────────────────────────

  Future<void> upsertNoteLink(NoteLinksTableCompanion row) async {
    await into(db.noteLinksTable).insertOnConflictUpdate(row);
  }

  Future<List<NoteLinkRow>> getOutgoingLinks(String sourceNoteId) {
    return (select(db.noteLinksTable)
          ..where((l) =>
              l.sourceNoteId.equals(sourceNoteId) & l.deletedAt.isNull()))
        .get();
  }

  Future<List<NoteLinkRow>> getIncomingLinks(String targetNoteId) {
    return (select(db.noteLinksTable)
          ..where((l) =>
              l.targetNoteId.equals(targetNoteId) & l.deletedAt.isNull()))
        .get();
  }

  Future<void> softDeleteNoteLink(String id, String deletedAtIso) async {
    await (update(db.noteLinksTable)..where((l) => l.id.equals(id))).write(
      NoteLinksTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  // ─── Note ↔ Todo links ────────────────────────────────────────────

  Future<void> upsertNoteTodoLink(NoteTodoLinksTableCompanion row) async {
    await into(db.noteTodoLinksTable).insertOnConflictUpdate(row);
  }

  Future<List<NoteTodoLinkRow>> getTodoLinksForNote(String noteId) {
    return (select(db.noteTodoLinksTable)
          ..where((l) => l.noteId.equals(noteId)))
        .get();
  }

  Future<void> removeNoteTodoLink(String noteId, String todoId) async {
    await (delete(db.noteTodoLinksTable)
          ..where((l) => l.noteId.equals(noteId) & l.todoId.equals(todoId)))
        .go();
  }

  // ─── Soft delete ──────────────────────────────────────────────────

  Future<void> softDeleteNote(String id, String deletedAtIso) async {
    await (update(db.notesTable)..where((n) => n.id.equals(id))).write(
      NotesTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  /// Self-heal: remove junction rows for tombstoned notes.
  Future<void> cleanJunctionsForDeletedNotes(List<String> tombstoneIds) async {
    if (tombstoneIds.isEmpty) return;
    await (delete(db.noteTagsTable)
          ..where((j) => j.noteId.isIn(tombstoneIds)))
        .go();
    await (delete(db.noteTodoLinksTable)
          ..where((l) => l.noteId.isIn(tombstoneIds)))
        .go();
    await (delete(db.noteLinksTable)
          ..where((l) =>
              l.sourceNoteId.isIn(tombstoneIds) |
              l.targetNoteId.isIn(tombstoneIds)))
        .go();
  }
}
