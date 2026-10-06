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

  /// Correlation id returned by the backend for server-side diagnostics.
  final String? requestId;

  /// Sanitized response body. Authorization headers are never stored here.
  final Object? rawResponse;

  /// Server-requested delay parsed from Retry-After.
  final Duration? retryAfter;

  const ApiException(
    this.statusCode,
    this.code,
    this.message, {
    this.issues,
    this.requestId,
    this.rawResponse,
    this.retryAfter,
  });

  /// Build từ response body parse được.
  factory ApiException.fromResponse(
    int statusCode,
    Map<String, dynamic> body, {
    Object? rawResponse,
    Duration? retryAfter,
  }) {
    final fallbackCode = statusCode > 0 ? 'http_$statusCode' : 'network_error';
    final code = body['error'] is String && (body['error'] as String).isNotEmpty
        ? body['error'] as String
        : fallbackCode;
    final issues = body['issues'] is List
        ? List<dynamic>.from(body['issues'] as List)
        : null;
    final requestId = body['request_id'] as String?;
    final backendMessage = body['message'];
    final message = backendMessage is String && backendMessage.isNotEmpty
        ? backendMessage
        : code;
    return ApiException(
      statusCode,
      code,
      message,
      issues: issues,
      requestId: requestId,
      rawResponse: rawResponse ?? body,
      retryAfter: retryAfter,
    );
  }

  /// Có phải auth error (token hết hạn / sai).
  bool get isAuthError =>
      statusCode == 401 ||
      code == 'unauthorized' ||
      code == 'invalid_credentials';

  bool get isRetryable =>
      code == 'no_connection' ||
      code == 'timeout' ||
      statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode >= 500;

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
  String toString() =>
      'ApiException($statusCode, $code: $message'
      '${requestId == null ? '' : ', requestId: $requestId'})';

  static const Map<String, String> _vnMessages = {
    // 400
    'bad_input': 'Dữ liệu không hợp lệ',
    'bad_cursor': 'Phân trang không hợp lệ',
    'self_link': 'Không thể liên kết với chính nó',
    'invalid_parent': 'Việc cha không hợp lệ',
    'invalid_trigger': 'Việc trigger không hợp lệ',
    'invalid_habit': 'Habit liên kết không hợp lệ, vui lòng chọn lại',
    'invalid_category': 'Danh mục không hợp lệ, vui lòng chọn lại',
    'archived': 'Đối tượng đã được lưu trữ',
    'read_only': 'Danh mục hệ thống chỉ có thể xem',
    'invalid_range': 'Khoảng thời gian không hợp lệ',
    'request_timeout': 'Yêu cầu hết thời gian chờ',
    'too_early': 'Máy chủ chưa sẵn sàng xử lý yêu cầu',
    'rate_limited': 'Thao tác quá nhanh, vui lòng thử lại',
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
    'timeout': 'Yêu cầu hết thời gian chờ',
    'network_error': 'Không thể kết nối tới máy chủ',
    'sync_failed': 'Máy chủ không thể hoàn tất đồng bộ',
    'sync_unavailable': 'Dịch vụ đồng bộ tạm thời không khả dụng',
    'response_parse_error': 'Phản hồi máy chủ không đúng định dạng',
    'sync_model_parse_error': 'Dữ liệu đồng bộ không tương thích',
    'server_error': 'Lỗi máy chủ, thử lại sau',
    'unknown': 'Đã xảy ra lỗi',
  };
}
