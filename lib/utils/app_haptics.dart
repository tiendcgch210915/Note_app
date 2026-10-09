import 'dart:async';

import 'package:flutter/services.dart';

/// Phản hồi rung nhẹ cho thao tác chạm. Mọi lệnh đều an toàn khi chạy trong
/// test hoặc trên nền tảng không hỗ trợ (bỏ qua lỗi).
class AppHaptics {
  AppHaptics._();

  /// Đổi lựa chọn: tab, segment, công tắc, bánh xe chọn.
  static void selection() => _run(HapticFeedback.selectionClick);

  /// Chạm nút thông thường.
  static void light() => _run(HapticFeedback.lightImpact);

  /// Hoàn thành một việc (tick todo, log thói quen).
  static void medium() => _run(HapticFeedback.mediumImpact);

  /// Hành động nguy hiểm / lỗi.
  static void heavy() => _run(HapticFeedback.heavyImpact);

  static void _run(Future<void> Function() fn) {
    try {
      unawaited(fn().catchError((Object _) {}));
    } catch (_) {
      // Bỏ qua: thiết bị không hỗ trợ rung.
    }
  }
}
