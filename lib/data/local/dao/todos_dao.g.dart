// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todos_dao.dart';

// ignore_for_file: type=lint
mixin _$TodosDaoMixin on DatabaseAccessor<AppDatabase> {
  $TodosTableTable get todosTable => attachedDatabase.todosTable;
  $TodoTagsTableTable get todoTagsTable => attachedDatabase.todoTagsTable;
  $TagsTableTable get tagsTable => attachedDatabase.tagsTable;
  $NoteTagsTableTable get noteTagsTable => attachedDatabase.noteTagsTable;
  TodosDaoManager get managers => TodosDaoManager(this);
}

class TodosDaoManager {
  final _$TodosDaoMixin _db;
  TodosDaoManager(this._db);
  $$TodosTableTableTableManager get todosTable =>
      $$TodosTableTableTableManager(_db.attachedDatabase, _db.todosTable);
  $$TodoTagsTableTableTableManager get todoTagsTable =>
      $$TodoTagsTableTableTableManager(_db.attachedDatabase, _db.todoTagsTable);
  $$TagsTableTableTableManager get tagsTable =>
      $$TagsTableTableTableManager(_db.attachedDatabase, _db.tagsTable);
  $$NoteTagsTableTableTableManager get noteTagsTable =>
      $$NoteTagsTableTableTableManager(_db.attachedDatabase, _db.noteTagsTable);
}
