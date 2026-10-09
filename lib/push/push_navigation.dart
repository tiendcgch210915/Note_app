import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/auth_storage.dart';
import '../screens/checklists/run_detail_screen.dart';
import '../screens/checklists/template_detail_screen.dart';
import '../screens/habits/habit_detail_screen.dart';
import '../screens/notes/note_detail_screen.dart';
import '../screens/shell/home_shell_controller.dart';
import '../screens/todos/todo_detail_screen.dart';
import '../utils/app_navigator.dart';
import 'push_target.dart';

/// Mở màn hình ứng với [target]. Trả `true` nếu đã mở, `false` nếu type chưa
/// được hỗ trợ hoặc thiếu dữ liệu cần thiết (ví dụ thiếu `id`).
typedef PushTargetOpener =
    bool Function(NavigatorState navigator, PushTarget target);

/// ════════════════════════════════════════════════════════════════════════
/// HÀM ĐIỀU HƯỚNG TẬP TRUNG CHO THÔNG BÁO ĐẨY
///
/// Back-end gửi `data: { type, id }`. Muốn hỗ trợ một type mới, thêm một `case`
/// vào `switch` bên dưới:
///
/// ```dart
/// case 'ten_type':
///   return _push(navigator, id, (id) => TenManHinh(xyzId: id));
/// ```
///
/// - Type không cần `id` (mở một tab, một màn hình tĩnh): bỏ qua `_push`, tự
///   gọi `navigator.push(...)` hoặc `HomeShellController.instance.setTab(...)`
///   như `case 'example'`, rồi `return true`.
/// - Type lạ được bỏ qua (trả `false`), app không crash.
/// ════════════════════════════════════════════════════════════════════════
bool openPushTarget(NavigatorState navigator, PushTarget target) {
  final id = target.id;
  switch (target.type) {
    case 'example':
      // Mẫu: type không cần id. Về tab "Hôm nay".
      navigator.popUntil((route) => route.isFirst);
      HomeShellController.instance.showToday();
      return true;
    case 'todo':
      return _push(navigator, id, (id) => TodoDetailScreen(todoId: id));
    case 'note':
      return _push(navigator, id, (id) => NoteDetailScreen(noteId: id));
    case 'habit':
      return _push(navigator, id, (id) => HabitDetailScreen(habitId: id));
    case 'checklist_run':
      return _push(navigator, id, (id) => RunDetailScreen(runId: id));
    case 'checklist_template':
      return _push(navigator, id, (id) => TemplateDetailScreen(templateId: id));
    default:
      return false;
  }
}

bool _push(
  NavigatorState navigator,
  String? id,
  Widget Function(String id) builder,
) {
  if (id == null) return false;
  navigator.push(MaterialPageRoute<void>(builder: (_) => builder(id)));
  return true;
}

/// Nhận các đích đến từ thông báo đẩy và mở chúng vào đúng thời điểm.
///
/// Thông báo có thể được chạm khi app **chưa dựng xong** (khởi động nguội: lúc
/// đó còn đang đọc token đăng nhập, chưa có HomeShell) hoặc khi người dùng
/// **chưa đăng nhập**. Quy tắc:
/// - Trước [markAppReady]: giữ lại đích đến mới nhất, chưa mở.
/// - Sau đó: chỉ mở nếu đang đăng nhập; chưa đăng nhập thì bỏ qua đích đến.
class PushNavigation {
  PushNavigation({
    GlobalKey<NavigatorState>? navigatorKey,
    bool Function()? isAuthenticated,
    PushTargetOpener? opener,
  }) : _navigatorKey = navigatorKey ?? rootNavigatorKey,
       _isAuthenticated = isAuthenticated ?? _defaultIsAuthenticated,
       _opener = opener ?? openPushTarget;

  static final PushNavigation instance = PushNavigation();

  static bool _defaultIsAuthenticated() =>
      AuthStorage.instance.currentToken?.isNotEmpty ?? false;

  final GlobalKey<NavigatorState> _navigatorKey;
  final bool Function() _isAuthenticated;
  final PushTargetOpener _opener;

  final Completer<void> _ready = Completer<void>();
  bool _appReady = false;
  PushTarget? _pending;

  /// Hoàn tất khi app đã dựng xong màn hình đầu tiên (xem [markAppReady]).
  Future<void> get appReady => _ready.future;

  /// Có một đích đến đang chờ app sẵn sàng.
  @visibleForTesting
  PushTarget? get pending => _pending;

  /// Nhận một đích đến từ thông báo vừa được chạm.
  void handle(PushTarget target) {
    if (!_appReady) {
      _pending = target;
      return;
    }
    _open(target);
  }

  /// Gọi khi app đã bootstrap xong và đã chọn màn hình đầu tiên (đăng nhập hoặc
  /// HomeShell). Mở đích đến đang chờ (nếu có) sau frame kế tiếp, khi cây
  /// Navigator đã có màn hình.
  void markAppReady() {
    if (_appReady) return;
    _appReady = true;
    _ready.complete();
    final pending = _pending;
    _pending = null;
    if (pending == null) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _open(pending))
      // Đảm bảo có một frame để callback trên chạy, kể cả khi không còn gì đổi.
      ..scheduleFrame();
  }

  void _open(PushTarget target) {
    if (!_isAuthenticated()) {
      _log('bỏ qua $target: chưa đăng nhập');
      return;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _log('bỏ qua $target: chưa có Navigator');
      return;
    }
    if (!_opener(navigator, target)) _log('chưa hỗ trợ $target');
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[push] $message');
  }
}
