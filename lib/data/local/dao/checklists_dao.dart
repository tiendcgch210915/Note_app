import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'checklists_dao.g.dart';

@DriftAccessor(tables: [
  ChecklistTemplatesTable,
  ChecklistTemplateItemsTable,
  ChecklistRunsTable,
  ChecklistRunItemsTable,
])
class ChecklistsDao extends DatabaseAccessor<AppDatabase>
    with _$ChecklistsDaoMixin {
  ChecklistsDao(super.db);

  // ─── Templates ────────────────────────────────────────────────────

  Future<void> upsertTemplate(ChecklistTemplatesTableCompanion row) async {
    await into(db.checklistTemplatesTable).insertOnConflictUpdate(row);
  }

  Future<void> upsertTemplates(
      List<ChecklistTemplatesTableCompanion> rows) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(db.checklistTemplatesTable, rows);
    });
  }

  Future<TemplateRow?> getTemplateById(String id) {
    return (select(db.checklistTemplatesTable)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<List<TemplateRow>> getTemplates({bool? isSystem}) {
    final q = select(db.checklistTemplatesTable)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.title)]);
    if (isSystem != null) {
      q.where((t) => t.isSystem.equals(isSystem));
    }
    return q.get();
  }

  Future<void> softDeleteTemplate(String id, String deletedAtIso) async {
    await (update(db.checklistTemplatesTable)..where((t) => t.id.equals(id)))
        .write(
      ChecklistTemplatesTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  // ─── Template items ───────────────────────────────────────────────

  Future<void> upsertTemplateItem(
      ChecklistTemplateItemsTableCompanion row) async {
    await into(db.checklistTemplateItemsTable).insertOnConflictUpdate(row);
  }

  Future<List<TemplateItemRow>> getItemsForTemplate(String templateId) {
    return (select(db.checklistTemplateItemsTable)
          ..where(
              (i) => i.templateId.equals(templateId) & i.deletedAt.isNull())
          ..orderBy([(i) => OrderingTerm.asc(i.orderIndex)]))
        .get();
  }

  Future<void> softDeleteTemplateItem(String id, String deletedAtIso) async {
    await (update(db.checklistTemplateItemsTable)
          ..where((i) => i.id.equals(id)))
        .write(
      ChecklistTemplateItemsTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  // ─── Runs ─────────────────────────────────────────────────────────

  Future<void> upsertRun(ChecklistRunsTableCompanion row) async {
    await into(db.checklistRunsTable).insertOnConflictUpdate(row);
  }

  Future<RunRow?> getRunById(String id) {
    return (select(db.checklistRunsTable)
          ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<List<RunRow>> getRuns({int limit = 20}) {
    return (select(db.checklistRunsTable)
          ..where((r) => r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> softDeleteRun(String id, String deletedAtIso) async {
    await (update(db.checklistRunsTable)..where((r) => r.id.equals(id))).write(
      ChecklistRunsTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  // ─── Run items ────────────────────────────────────────────────────

  Future<void> upsertRunItem(ChecklistRunItemsTableCompanion row) async {
    await into(db.checklistRunItemsTable).insertOnConflictUpdate(row);
  }

  Future<List<RunItemRow>> getItemsForRun(String runId) {
    return (select(db.checklistRunItemsTable)
          ..where((i) => i.runId.equals(runId) & i.deletedAt.isNull())
          ..orderBy([(i) => OrderingTerm.asc(i.orderIndex)]))
        .get();
  }

  Future<void> softDeleteRunItem(String id, String deletedAtIso) async {
    await (update(db.checklistRunItemsTable)..where((i) => i.id.equals(id)))
        .write(
      ChecklistRunItemsTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }
}
