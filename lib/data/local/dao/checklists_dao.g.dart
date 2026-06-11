// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklists_dao.dart';

// ignore_for_file: type=lint
mixin _$ChecklistsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ChecklistCategoriesTableTable get checklistCategoriesTable =>
      attachedDatabase.checklistCategoriesTable;
  $ChecklistTemplatesTableTable get checklistTemplatesTable =>
      attachedDatabase.checklistTemplatesTable;
  $ChecklistTemplateItemsTableTable get checklistTemplateItemsTable =>
      attachedDatabase.checklistTemplateItemsTable;
  $ChecklistRunsTableTable get checklistRunsTable =>
      attachedDatabase.checklistRunsTable;
  $ChecklistRunItemsTableTable get checklistRunItemsTable =>
      attachedDatabase.checklistRunItemsTable;
  ChecklistsDaoManager get managers => ChecklistsDaoManager(this);
}

class ChecklistsDaoManager {
  final _$ChecklistsDaoMixin _db;
  ChecklistsDaoManager(this._db);
  $$ChecklistCategoriesTableTableTableManager get checklistCategoriesTable =>
      $$ChecklistCategoriesTableTableTableManager(
        _db.attachedDatabase,
        _db.checklistCategoriesTable,
      );
  $$ChecklistTemplatesTableTableTableManager get checklistTemplatesTable =>
      $$ChecklistTemplatesTableTableTableManager(
        _db.attachedDatabase,
        _db.checklistTemplatesTable,
      );
  $$ChecklistTemplateItemsTableTableTableManager
  get checklistTemplateItemsTable =>
      $$ChecklistTemplateItemsTableTableTableManager(
        _db.attachedDatabase,
        _db.checklistTemplateItemsTable,
      );
  $$ChecklistRunsTableTableTableManager get checklistRunsTable =>
      $$ChecklistRunsTableTableTableManager(
        _db.attachedDatabase,
        _db.checklistRunsTable,
      );
  $$ChecklistRunItemsTableTableTableManager get checklistRunItemsTable =>
      $$ChecklistRunItemsTableTableTableManager(
        _db.attachedDatabase,
        _db.checklistRunItemsTable,
      );
}
