import 'package:flutter/foundation.dart';

import '../models/todo.dart';

class FrogCompletionEvent {
  final int seed;
  final String todoId;
  final String title;
  final DateTime completedAt;

  const FrogCompletionEvent({
    required this.seed,
    required this.todoId,
    required this.title,
    required this.completedAt,
  });
}

class FrogCompletionCelebrations {
  FrogCompletionCelebrations._();

  static final FrogCompletionCelebrations instance =
      FrogCompletionCelebrations._();

  final ValueNotifier<FrogCompletionEvent?> notifier =
      ValueNotifier<FrogCompletionEvent?>(null);

  int _seed = 0;

  void celebrate(Todo todo) {
    if (!todo.isFrog || !todo.isDone) return;
    notifier.value = FrogCompletionEvent(
      seed: _seed++,
      todoId: todo.id,
      title: todo.title,
      completedAt: DateTime.now(),
    );
  }
}
