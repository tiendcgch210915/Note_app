import 'package:flutter/foundation.dart';

class HomeShellController {
  HomeShellController._();

  static final HomeShellController instance = HomeShellController._();

  final ValueNotifier<int> currentIndex = ValueNotifier<int>(0);

  void setTab(int index) {
    if (index < 0 || index > 4) return;
    currentIndex.value = index;
  }

  void showToday() => setTab(0);
}
