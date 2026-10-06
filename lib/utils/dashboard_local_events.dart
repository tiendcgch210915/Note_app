import 'package:flutter/foundation.dart';

class DashboardLocalEvents {
  DashboardLocalEvents._();

  static final DashboardLocalEvents instance = DashboardLocalEvents._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void notifyChanged() {
    revision.value++;
  }
}
