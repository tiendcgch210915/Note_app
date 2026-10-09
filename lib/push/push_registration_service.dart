import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Loại định danh dùng để đăng ký thiết bị với FCM.
///
/// Bản `firebase_messaging` đang dùng (16.7.0) chưa có `onRegistered()` /
/// `register()` nên chỉ có [token]. [fid] để dành cho khi nâng cấp lên bản có
/// Firebase Installation ID.
enum PushRegistrationKind { fid, token }

/// Một định danh đăng ký thiết bị kèm loại của nó.
class PushRegistrationId {
  const PushRegistrationId({required this.value, required this.kind});

  final String value;
  final PushRegistrationKind kind;

  /// `"fid"` hoặc `"token"` — giá trị gửi lên back-end ở giai đoạn 2.
  String get kindName => kind.name;

  @override
  bool operator ==(Object other) =>
      other is PushRegistrationId && other.value == value && other.kind == kind;

  @override
  int get hashCode => Object.hash(value, kind);

  /// Cố ý không in [value]: đây là định danh thiết bị, không được lọt vào log.
  @override
  String toString() => 'PushRegistrationId($kindName, ${value.length} ký tự)';
}

/// Lấy và theo dõi định danh đăng ký FCM của thiết bị.
///
/// Lớp này chỉ lấy định danh và phát ra [registrationIds] (kèm `debugPrint` ở
/// bản debug); nó không gọi mạng. `PushDeviceRegistrar` lắng nghe stream này /
/// đọc [current] để `POST`/`DELETE /devices` lên back-end.
class PushRegistrationService {
  PushRegistrationService({
    Future<String?> Function()? getToken,
    Stream<String> Function()? onTokenRefresh,
  }) : _getToken = getToken ?? _defaultGetToken,
       _onTokenRefresh = onTokenRefresh ?? _defaultOnTokenRefresh;

  static final PushRegistrationService instance = PushRegistrationService();

  // Truy cập FirebaseMessaging.instance lười (lúc gọi) để tạo `instance` được
  // trước khi Firebase.initializeApp() chạy xong.
  static Future<String?> _defaultGetToken() =>
      FirebaseMessaging.instance.getToken();
  static Stream<String> _defaultOnTokenRefresh() =>
      FirebaseMessaging.instance.onTokenRefresh;

  final Future<String?> Function() _getToken;
  final Stream<String> Function() _onTokenRefresh;

  final StreamController<PushRegistrationId> _controller =
      StreamController<PushRegistrationId>.broadcast();
  StreamSubscription<String>? _refreshSubscription;
  PushRegistrationId? _current;

  /// Mỗi lần định danh đổi (lần đầu, hoặc FCM làm mới). Broadcast.
  Stream<PushRegistrationId> get registrationIds => _controller.stream;

  /// Định danh mới nhất, `null` nếu chưa có hoặc đã [stop].
  PushRegistrationId? get current => _current;

  /// Bắt đầu theo dõi. Lắng nghe làm mới **trước** khi hỏi giá trị hiện tại để
  /// không lỡ bản làm mới xảy ra giữa chừng. Gọi lại khi đang chạy là no-op.
  Future<void> start() async {
    if (_refreshSubscription != null) return;
    final subscription = _onTokenRefresh().listen(
      _emit,
      onError: (Object error) => _log('onTokenRefresh lỗi: $error'),
    );
    _refreshSubscription = subscription;
    try {
      final before = _current;
      final token = await _getToken();
      // Đã [stop] trong lúc chờ, hoặc FCM vừa làm mới thì kết quả này đã cũ.
      if (!identical(_refreshSubscription, subscription)) return;
      if (token != null && _current == before) _emit(token);
    } catch (error) {
      // Máy không có Google Play services, mất mạng lần đầu... Giá trị sẽ đến
      // qua onTokenRefresh khi FCM sẵn sàng; không để lỗi này chặn app.
      _log('getToken lỗi: $error');
    }
  }

  /// Dừng theo dõi (ví dụ khi đăng xuất). Không xóa token trên FCM — việc hủy
  /// đăng ký thiết bị với back-end thuộc giai đoạn 2.
  Future<void> stop() async {
    final subscription = _refreshSubscription;
    _refreshSubscription = null;
    _current = null;
    await subscription?.cancel();
  }

  void _emit(String value) {
    if (value.isEmpty || value == _current?.value) return;
    final id = PushRegistrationId(
      value: value,
      kind: PushRegistrationKind.token,
    );
    _current = id;
    _controller.add(id);
    // Chỉ ở bản debug, để bạn copy thử. Bản release không in gì.
    if (kDebugMode) debugPrint('[push] registration ${id.kindName}: $value');
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[push] $message');
  }
}
