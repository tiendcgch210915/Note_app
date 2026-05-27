/// Exception throw bởi ApiClient khi server trả 4xx/5xx hoặc lỗi mạng.
///
/// Code mapping theo API Reference (Auth + Notes + Todos + Habits + Checklists + Dashboard).
class ApiException implements Exception {
  /// HTTP status code (0 nếu network error).
  final int statusCode;

  /// Error code từ backend: bad_input, email_taken, not_found, ...
  /// hoặc 'no_connection', 'server_error', 'unknown' cho client-side.
  final String code;

  /// Message tiếng Anh hoặc raw (lấy từ getter vnMessage cho UI).
  final String message;

  /// Danh sách Zod issues (chỉ có khi code='bad_input').
  final List<dynamic>? issues;

  const ApiException(this.statusCode, this.code, this.message, {this.issues});

  /// Build từ response body parse được.
  factory ApiException.fromResponse(int statusCode, Map<String, dynamic> body) {
    final code = (body['error'] as String?) ?? 'unknown';
    final issues = body['issues'] as List<dynamic>?;
    return ApiException(statusCode, code, code, issues: issues);
  }

  /// Có phải auth error (token hết hạn / sai).
  bool get isAuthError =>
      statusCode == 401 || code == 'unauthorized' || code == 'invalid_credentials';

  /// Vietnamese-localized message để show trên UI.
  String get vnMessage {
    // Nếu có Zod issues, lấy message đầu tiên
    if (code == 'bad_input' && issues != null && issues!.isNotEmpty) {
      final first = issues!.first;
      if (first is Map && first['message'] is String) {
        return first['message'] as String;
      }
    }
    return _vnMessages[code] ?? 'Đã xảy ra lỗi ($code)';
  }

  @override
  String toString() => 'ApiException($statusCode, $code: $message)';

  static const Map<String, String> _vnMessages = {
    // 400
    'bad_input': 'Dữ liệu không hợp lệ',
    'bad_cursor': 'Phân trang không hợp lệ',
    'self_link': 'Không thể liên kết với chính nó',
    'invalid_parent': 'Việc cha không hợp lệ',
    'invalid_trigger': 'Việc trigger không hợp lệ',
    'archived': 'Đối tượng đã được lưu trữ',
    'invalid_range': 'Khoảng thời gian không hợp lệ',
    // 401
    'unauthorized': 'Phiên đăng nhập đã hết hạn',
    'invalid_credentials': 'Email hoặc mật khẩu sai',
    // 404
    'not_found': 'Không tìm thấy',
    // 409
    'daily_limit_reached': 'Đã đủ 6 việc trong ngày',
    'cycle': 'Tạo vòng lặp parent-child không hợp lệ',
    'duplicate': 'Đã tồn tại',
    'email_taken': 'Email đã được đăng ký',
    'incomplete_required': 'Còn bước bắt buộc chưa hoàn thành',
    // Client-side
    'no_connection': 'Không có kết nối mạng',
    'server_error': 'Lỗi máy chủ, thử lại sau',
    'unknown': 'Đã xảy ra lỗi',
  };
}
