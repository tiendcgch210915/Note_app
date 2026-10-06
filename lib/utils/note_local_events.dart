import 'package:flutter/foundation.dart';

class NoteLocalEvents extends ValueNotifier<int> {
  NoteLocalEvents._() : super(0);

  static final NoteLocalEvents instance = NoteLocalEvents._();

  void notifyChanged() => value++;
}
