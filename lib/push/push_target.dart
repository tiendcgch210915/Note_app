import 'dart:convert';

/// Đích đến mà một thông báo đẩy muốn mở, lấy từ trường `data` của FCM:
/// `type` (loại màn hình) và `id` (định danh bản ghi, nếu có).
///
/// Cùng một đối tượng đi qua hai đường: tin FCM (`RemoteMessage.data`) và
/// thông báo cục bộ (chuỗi `payload` của flutter_local_notifications).
class PushTarget {
  const PushTarget({required this.type, this.id});

  final String type;
  final String? id;

  /// Đọc từ `RemoteMessage.data`. Trả `null` nếu thiếu `type`.
  static PushTarget? fromData(Map<String, dynamic>? data) {
    final type = _clean(data?['type']);
    if (type == null) return null;
    return PushTarget(type: type.toLowerCase(), id: _clean(data?['id']));
  }

  /// Đọc từ payload của thông báo cục bộ (xem [toPayload]). Payload hỏng hoặc
  /// không phải JSON object thì trả `null`, không ném lỗi.
  static PushTarget? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      return fromData(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  String toPayload() => jsonEncode({'type': type, if (id != null) 'id': id});

  static String? _clean(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  @override
  bool operator ==(Object other) =>
      other is PushTarget && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => 'PushTarget($type${id == null ? '' : ', $id'})';
}
