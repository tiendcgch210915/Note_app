import 'package:flutter/foundation.dart';

class TodoLocalEvents {
  TodoLocalEvents._();

  static final TodoLocalEvents instance = TodoLocalEvents._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void notifyChanged() {
    revision.value++;
  }
}
