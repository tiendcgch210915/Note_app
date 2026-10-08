import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/todos_repository.dart';
import '../models/todo.dart';
import 'todo_local_events.dart';

/// Snapshot của một phiên tập trung (focus) đang chạy.
class FocusSession {
  final Todo todo;
  final List<Todo> subtasks;
  final Duration remaining;
  final Duration total;
  final List<Todo> triggeredTodos;

  const FocusSession({
    required this.todo,
    required this.subtasks,
    required this.remaining,
    required this.total,
    required this.triggeredTodos,
  });

  bool get isOver => remaining <= Duration.zero;

  FocusSession copyWith({
    Todo? todo,
    List<Todo>? subtasks,
    Duration? remaining,
    List<Todo>? triggeredTodos,
  }) {
    return FocusSession(
      todo: todo ?? this.todo,
      subtasks: subtasks ?? this.subtasks,
      remaining: remaining ?? this.remaining,
      total: total,
      triggeredTodos: triggeredTodos ?? this.triggeredTodos,
    );
  }
}

class FocusSessionResult {
  final Todo todo;
  final List<Todo> subtasks;
  final List<Todo> triggeredTodos;
  final bool completedAll;

  const FocusSessionResult({
    required this.todo,
    required this.subtasks,
    required this.triggeredTodos,
    required this.completedAll,
  });
}

typedef FocusLocalDetailLoader = Future<TodoWithRelations?> Function(String id);

/// Giữ phiên tập trung ở cấp app để đồng hồ tiếp tục chạy khi người dùng rời
/// màn hình Focus (nút Home/Lịch). Chỉ lưu in-memory, không ghi Drift: tắt
/// hẳn app thì phiên mất.
///
/// Todo của phiên luôn được đối chiếu lại với Drift mỗi khi có thay đổi todo
/// cục bộ (kể cả sync pull), để không hoàn thành lại/ghi đè một todo đã bị
/// sửa, hoàn thành hoặc xóa ở nơi khác trong lúc phiên chạy ngầm.
class FocusSessionController {
  FocusSessionController._();

  static final FocusSessionController instance = FocusSessionController._();

  final ValueNotifier<FocusSession?> session = ValueNotifier<FocusSession?>(
    null,
  );

  /// `true` khi TodoFocusScreen đang nằm trên stack — banner nổi sẽ ẩn đi.
  final ValueNotifier<bool> focusScreenOpen = ValueNotifier<bool>(false);

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  @visibleForTesting
  FocusLocalDetailLoader localDetailLoader = (id) =>
      TodosRepository.instance.getLocalDetail(id);

  Timer? _timer;
  DateTime? _endsAt;
  int _refreshGeneration = 0;
  bool _listening = false;

  bool isActiveFor(String todoId) => session.value?.todo.id == todoId;

  /// Bắt đầu phiên mới, thay thế phiên đang chạy (nếu có). Caller chịu trách
  /// nhiệm xin xác nhận người dùng trước khi thay thế.
  void start(TodoWithRelations detail, Duration duration) {
    _stopTimer();
    _endsAt = clock().add(duration);
    session.value = FocusSession(
      todo: detail.todo,
      subtasks: [...detail.subtasks],
      remaining: duration,
      total: duration,
      triggeredTodos: const [],
    );
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    if (!_listening) {
      _listening = true;
      TodoLocalEvents.instance.revision.addListener(_onLocalTodoChanged);
    }
  }

  void _tick(Timer timer) {
    final current = session.value;
    final endsAt = _endsAt;
    if (current == null || endsAt == null) {
      timer.cancel();
      return;
    }
    final left = endsAt.difference(clock());
    final remaining = left <= Duration.zero
        ? Duration.zero
        : Duration(seconds: (left.inMilliseconds + 999) ~/ 1000);
    session.value = current.copyWith(remaining: remaining);
    if (remaining <= Duration.zero) _stopTimer();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void updateSubtasks(List<Todo> updatedTodos) {
    final current = session.value;
    if (current == null || updatedTodos.isEmpty) return;
    final byId = {for (final todo in updatedTodos) todo.id: todo};
    session.value = current.copyWith(
      todo: byId[current.todo.id] ?? current.todo,
      subtasks: [
        for (final subtask in current.subtasks) byId[subtask.id] ?? subtask,
      ],
    );
  }

  void addTriggered(List<Todo> todos) {
    final current = session.value;
    if (current == null || todos.isEmpty) return;
    final existingIds = current.triggeredTodos.map((t) => t.id).toSet();
    session.value = current.copyWith(
      triggeredTodos: [
        ...current.triggeredTodos,
        ...todos.where((t) => existingIds.add(t.id)),
      ],
    );
  }

  /// Kết thúc phiên và trả về kết quả cuối cùng (null nếu không có phiên).
  FocusSessionResult? finish({required bool completedAll}) {
    final current = session.value;
    if (current == null) return null;
    _stopTimer();
    _endsAt = null;
    _refreshGeneration++;
    if (_listening) {
      _listening = false;
      TodoLocalEvents.instance.revision.removeListener(_onLocalTodoChanged);
    }
    session.value = null;
    return FocusSessionResult(
      todo: current.todo,
      subtasks: current.subtasks,
      triggeredTodos: current.triggeredTodos,
      completedAll: completedAll,
    );
  }

  /// Hủy phiên không cần kết quả (logout, 401, người dùng tắt từ banner).
  void cancel() => finish(completedAll: false);

  void _onLocalTodoChanged() => unawaited(_refreshFromLocal());

  Future<void> _refreshFromLocal() async {
    final started = session.value;
    if (started == null) return;
    final generation = ++_refreshGeneration;
    TodoWithRelations? detail;
    try {
      detail = await localDetailLoader(started.todo.id);
    } catch (_) {
      return;
    }
    final latest = session.value;
    if (latest == null || latest.todo.id != started.todo.id) return;
    if (generation != _refreshGeneration) return;
    if (detail == null) {
      cancel();
      return;
    }
    if (detail.todo.isDone && !focusScreenOpen.value) {
      cancel();
      return;
    }
    session.value = latest.copyWith(
      todo: detail.todo,
      subtasks: detail.subtasks,
    );
  }

  @visibleForTesting
  void resetForTest() {
    cancel();
    focusScreenOpen.value = false;
    clock = DateTime.now;
    localDetailLoader = (id) => TodosRepository.instance.getLocalDetail(id);
  }
}

String formatFocusDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60);
  final seconds = safe.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
