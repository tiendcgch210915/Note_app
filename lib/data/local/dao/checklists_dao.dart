import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'checklists_dao.g.dart';

@DriftAccessor(
  tables: [
    ChecklistCategoriesTable,
    ChecklistTemplatesTable,
    ChecklistTemplateOrdersTable,
    ChecklistTemplateItemsTable,
    ChecklistRunsTable,
    ChecklistRunItemsTable,
  ],
)
class ChecklistsDao extends DatabaseAccessor<AppDatabase>
    with _$ChecklistsDaoMixin {
  ChecklistsDao(super.db);

  // ─── Categories ───────────────────────────────────────────────────

  Future<void> upsertCategory(ChecklistCategoriesTableCompanion row) async {
    await into(db.checklistCategoriesTable).insertOnConflictUpdate(row);
  }

  Future<void> upsertCategories(
    List<ChecklistCategoriesTableCompanion> rows,
  ) async {
    if (rows.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(db.checklistCategoriesTable, rows);
    });
  }

  Future<ChecklistCategoryRow?> getCategoryById(String id) {
    return (select(
      db.checklistCategoriesTable,
    )..where((c) => c.id.equals(id) & c.deletedAt.isNull())).getSingleOrNull();
  }

  Future<List<ChecklistCategoryRow>> getCategories({String scope = 'all'}) {
    final q = select(db.checklistCategoriesTable)
      ..where((c) => c.deletedAt.isNull())
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.name),
      ]);
    if (scope == 'own') {
      q.where((c) => c.isSystem.equals(false));
    } else if (scope == 'system') {
      q.where((c) => c.isSystem.equals(true));
    }
    return q.get();
  }

  Future<void> softDeleteCategory(String id, String deletedAtIso) async {
    await (update(
      db.checklistCategoriesTable,
    )..where((c) => c.id.equals(id))).write(
      ChecklistCategoriesTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
    await (update(
      db.checklistTemplatesTable,
    )..where((t) => t.categoryId.equals(id))).write(
      ChecklistTemplatesTableCompanion(
        category: const Value(null),
        categoryId: const Value(null),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  // ─── Templates ────────────────────────────────────────────────────

  Future<void> upsertTemplate(ChecklistTemplatesTableCompanion row) async {
    await into(db.checklistTemplatesTable).insertOnConflictUpdate(row);
  }

  Future<void> upsertTemplates(
    List<ChecklistTemplatesTableCompanion> rows,
  ) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(db.checklistTemplatesTable, rows);
    });
  }

  Future<TemplateRow?> getTemplateById(String id) {
    return (select(
      db.checklistTemplatesTable,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
  }

  Future<List<TemplateRow>> getTemplates({
    bool? isSystem,
    String? categoryId,
    bool uncategorized = false,
  }) {
    final q = select(db.checklistTemplatesTable)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.desc(t.updatedAt),
        (t) => OrderingTerm.asc(t.title),
        (t) => OrderingTerm.asc(t.id),
      ]);
    if (isSystem != null) {
      q.where((t) => t.isSystem.equals(isSystem));
    }
    if (categoryId != null) {
      q.where((t) => t.categoryId.equals(categoryId));
    } else if (uncategorized) {
      q.where((t) => t.categoryId.isNull());
    }
    return q.get();
  }

  Future<TemplateOrderRow?> getTemplateOrderById(String id) {
    return (select(
      db.checklistTemplateOrdersTable,
    )..where((o) => o.id.equals(id) & o.deletedAt.isNull())).getSingleOrNull();
  }

  Future<TemplateOrderRow?> getTemplateOrderForTemplate({
    required String userId,
    required String templateId,
  }) {
    return (select(db.checklistTemplateOrdersTable)
          ..where(
            (o) =>
                o.userId.equals(userId) &
                o.templateId.equals(templateId) &
                o.deletedAt.isNull(),
          )
          ..orderBy([(o) => OrderingTerm.desc(o.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<TemplateOrderRow>> getTemplateOrders({required String userId}) {
    return (select(db.checklistTemplateOrdersTable)
          ..where((o) => o.userId.equals(userId) & o.deletedAt.isNull())
          ..orderBy([(o) => OrderingTerm.asc(o.sortOrder)]))
        .get();
  }

  Future<void> upsertTemplateOrder(
    ChecklistTemplateOrdersTableCompanion row,
  ) async {
    await into(db.checklistTemplateOrdersTable).insertOnConflictUpdate(row);
  }

  Future<void> upsertTemplateOrders(
    List<ChecklistTemplateOrdersTableCompanion> rows,
  ) async {
    if (rows.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(db.checklistTemplateOrdersTable, rows);
    });
  }

  Future<void> softDeleteTemplateOrder(String id, String deletedAtIso) async {
    await (update(
      db.checklistTemplateOrdersTable,
    )..where((o) => o.id.equals(id))).write(
      ChecklistTemplateOrdersTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  Future<void> softDeleteTemplate(String id, String deletedAtIso) async {
    await (update(
      db.checklistTemplatesTable,
    )..where((t) => t.id.equals(id))).write(
      ChecklistTemplatesTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }

  // ─── Template items ───────────────────────────────────────────────

  Future<void> upsertTemplateItem(
    ChecklistTemplateItemsTableCompanion row,
  ) async {
    await into(db.checklistTemplateItemsTable).insertOnConflictUpdate(row);
  }

  Future<List<TemplateItemRow>> getItemsForTemplate(String templateId) {
    return (select(db.checklistTemplateItemsTable)
          ..where((i) => i.templateId.equals(templateId) & i.deletedAt.isNull())
          ..orderBy([(i) => OrderingTerm.asc(i.orderIndex)]))
        .get();
  }

  Future<TemplateItemRow?> getTemplateItemById(String id) {
    return (select(
      db.checklistTemplateItemsTable,
    )..where((i) => i.id.equals(id) & i.deletedAt.isNull())).getSingleOrNull();
  }

  Future<void> updateTemplateItemFields(
    String id, {
    String? title,
    String? description,
    bool writeDescription = false,
    bool? isRequired,
    int? orderIndex,
    required String updatedAt,
  }) async {
    await (update(
      db.checklistTemplateItemsTable,
    )..where((i) => i.id.equals(id))).write(
      ChecklistTemplateItemsTableCompanion(
        title: title == null ? const Value.absent() : Value(title),
        description: writeDescription
            ? Value(description)
            : const Value.absent(),
        isRequired: isRequired == null
            ? const Value.absent()
            : Value(isRequired),
        orderIndex: orderIndex == null
            ? const Value.absent()
            : Value(orderIndex),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> softDeleteTemplateItem(String id, String deletedAtIso) async {
    await (update(
      db.checklistTemplateItemsTable,
    )..where((i) => i.id.equals(id))).write(
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
    return (select(
      db.checklistRunsTable,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).getSingleOrNull();
  }

  Future<RunRow?> getInProgressRunForTemplate(String templateId) {
    return (select(db.checklistRunsTable)
          ..where(
            (r) =>
                r.templateId.equals(templateId) &
                r.status.equals('in_progress') &
                r.deletedAt.isNull(),
          )
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<RunRow>> getRuns({
    int limit = 20,
    String? status,
    String? templateId,
  }) {
    final q = select(db.checklistRunsTable)
      ..where((r) => r.deletedAt.isNull())
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
      ..limit(limit);
    if (status != null) {
      q.where((r) => r.status.equals(status));
    }
    if (templateId != null) {
      q.where((r) => r.templateId.equals(templateId));
    }
    return q.get();
  }

  Future<void> updateRunStatus(
    String id, {
    required String status,
    String? completedAt,
    int? durationMs,
    bool writeDuration = false,
    required String updatedAt,
  }) async {
    await (update(db.checklistRunsTable)..where((r) => r.id.equals(id))).write(
      ChecklistRunsTableCompanion(
        status: Value(status),
        completedAt: Value(completedAt),
        durationMs: writeDuration ? Value(durationMs) : const Value.absent(),
        updatedAt: Value(updatedAt),
      ),
    );
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

  Future<RunItemRow?> getRunItemById(String id) {
    return (select(
      db.checklistRunItemsTable,
    )..where((i) => i.id.equals(id) & i.deletedAt.isNull())).getSingleOrNull();
  }

  Future<List<RunItemRow>> getItemsForRun(String runId) {
    return (select(db.checklistRunItemsTable)
          ..where((i) => i.runId.equals(runId) & i.deletedAt.isNull())
          ..orderBy([(i) => OrderingTerm.asc(i.orderIndex)]))
        .get();
  }

  Future<void> updateRunItemFields(
    String id, {
    required String status,
    String? completedAt,
    String? note,
    required String updatedAt,
  }) async {
    await (update(
      db.checklistRunItemsTable,
    )..where((i) => i.id.equals(id))).write(
      ChecklistRunItemsTableCompanion(
        status: Value(status),
        completedAt: Value(completedAt),
        note: Value(note),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> softDeleteRunItem(String id, String deletedAtIso) async {
    await (update(
      db.checklistRunItemsTable,
    )..where((i) => i.id.equals(id))).write(
      ChecklistRunItemsTableCompanion(
        deletedAt: Value(deletedAtIso),
        updatedAt: Value(deletedAtIso),
      ),
    );
  }
}
