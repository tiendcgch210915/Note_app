enum RecurringTodoDeleteScope {
  thisOccurrence,
  thisAndFuture,
  all;

  String get apiValue {
    switch (this) {
      case RecurringTodoDeleteScope.thisOccurrence:
        return 'this';
      case RecurringTodoDeleteScope.thisAndFuture:
        return 'future';
      case RecurringTodoDeleteScope.all:
        return 'all';
    }
  }
}
