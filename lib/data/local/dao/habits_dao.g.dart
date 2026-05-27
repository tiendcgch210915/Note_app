// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habits_dao.dart';

// ignore_for_file: type=lint
mixin _$HabitsDaoMixin on DatabaseAccessor<AppDatabase> {
  $HabitsTableTable get habitsTable => attachedDatabase.habitsTable;
  $HabitLogsTableTable get habitLogsTable => attachedDatabase.habitLogsTable;
  HabitsDaoManager get managers => HabitsDaoManager(this);
}

class HabitsDaoManager {
  final _$HabitsDaoMixin _db;
  HabitsDaoManager(this._db);
  $$HabitsTableTableTableManager get habitsTable =>
      $$HabitsTableTableTableManager(_db.attachedDatabase, _db.habitsTable);
  $$HabitLogsTableTableTableManager get habitLogsTable =>
      $$HabitLogsTableTableTableManager(
        _db.attachedDatabase,
        _db.habitLogsTable,
      );
}
