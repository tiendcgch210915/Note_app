import 'package:flutter/foundation.dart';

enum ActiveSessionKind { todo, checklist }

/// Định danh phiên đang giữ khóa: loại + id của todo hoặc run.
@immutable
class ActiveSessionRef {
  final ActiveSessionKind kind;
  final String id;

  const ActiveSessionRef(this.kind, this.id);

  @override
  bool operator ==(Object other) =>
      other is ActiveSessionRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'ActiveSessionRef($kind, $id)';
}

/// Khóa toàn app: tại một thời điểm chỉ có MỘT phiên làm việc, dù là tập trung
/// vào một todo hay đang chạy một checklist. Phải hoàn thành hoặc hủy phiên
/// đang chạy trước khi bắt đầu việc khác.
///
/// Mỗi controller xin khóa trong `start()` và trả lại khi kết thúc, nên luật
/// này được đảm bảo ở tầng dữ liệu chứ không chỉ nhờ UI nhớ kiểm tra. Khóa chỉ
/// lưu danh tính; tiêu đề/thời gian vẫn do từng controller giữ.
class ActiveSessionLock {
  ActiveSessionLock._();

  static final ActiveSessionLock instance = ActiveSessionLock._();

  ActiveSessionRef? _holder;

  /// Phiên đang giữ khóa, `null` nếu rảnh.
  ActiveSessionRef? get holder => _holder;

  /// Rảnh, hoặc đang do chính [ref] giữ (xin lại khóa của mình luôn hợp lệ).
  bool isFreeFor(ActiveSessionRef ref) => _holder == null || _holder == ref;

  /// Xin khóa cho [ref]. `false` (không đổi gì) nếu phiên khác đang giữ.
  bool tryAcquire(ActiveSessionRef ref) {
    if (!isFreeFor(ref)) return false;
    _holder = ref;
    return true;
  }

  /// Trả khóa; bỏ qua nếu khóa đang do phiên khác giữ.
  void release(ActiveSessionRef ref) {
    if (_holder == ref) _holder = null;
  }

  @visibleForTesting
  void resetForTest() => _holder = null;
}
