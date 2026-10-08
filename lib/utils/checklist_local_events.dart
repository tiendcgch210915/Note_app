import 'package:flutter/foundation.dart';

/// Báo cho UI Checklists biết dữ liệu trong Drift vừa đổi ngoài tầm kiểm soát
/// của màn hình (ví dụ sync pull áp dữ liệu mới), để đọc lại từ cache.
class ChecklistLocalEvents extends ValueNotifier<int> {
  ChecklistLocalEvents._() : super(0);

  static final ChecklistLocalEvents instance = ChecklistLocalEvents._();

  void notifyChanged() => value++;
}
