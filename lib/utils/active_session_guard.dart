import 'package:flutter/material.dart';

import 'active_session_lock.dart';
import 'checklist_session_controller.dart';
import 'focus_session_controller.dart';

/// Kiểm tra trước khi bắt đầu một phiên mới (tập trung vào todo hoặc chạy
/// checklist). Trả về `true` nếu được phép; nếu đang có phiên khác thì hiện hộp
/// thoại giải thích và trả về `false`.
///
/// Người dùng phải hoàn thành hoặc hủy phiên đang chạy trước khi làm việc
/// khác. Caller tự xử lý trường hợp "bắt đầu lại đúng việc đang chạy" (mở lại
/// màn hình của nó) trước khi gọi hàm này.
Future<bool> ensureNoActiveSession(BuildContext context) async {
  if (ActiveSessionLock.instance.holder == null) return true;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Bạn đang làm việc khác'),
      content: Text(
        '${_describeActiveSession()}\n\n'
        'Hãy hoàn thành hoặc hủy việc đó trước khi bắt đầu việc khác. '
        'Chạm thanh đang chạy ở cuối màn hình để quay lại.',
      ),
      actions: [
        FilledButton(
          key: const ValueKey('active-session-ack'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );
  return false;
}

String _describeActiveSession() {
  final holder = ActiveSessionLock.instance.holder;
  switch (holder?.kind) {
    case ActiveSessionKind.todo:
      final todo = FocusSessionController.instance.session.value?.todo;
      if (todo != null) return 'Bạn đang tập trung vào việc "${todo.title}".';
    case ActiveSessionKind.checklist:
      final run = ChecklistSessionController.instance.session.value;
      if (run != null) return 'Bạn đang làm checklist "${run.title}".';
    case null:
      break;
  }
  return 'Bạn đang có một việc làm dở.';
}

/// Hủy mọi phiên đang chạy (logout, 401). Không ghi gì vào Drift.
void cancelAllSessions() {
  FocusSessionController.instance.cancel();
  ChecklistSessionController.instance.cancel();
}
