import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/api_exception.dart';
import '../data/auth_repository.dart';
import '../data/auth_storage.dart';
import 'push_registration_service.dart';

/// Hai endpoint đăng ký thiết bị của back-end (cần JWT, dùng chung `ApiClient`).
///
/// - `POST /devices` `{registrationId, kind, platform}` — upsert theo
///   (user, registrationId) và cập nhật `last_seen_at`.
/// - `DELETE /devices` `{registrationId}` — body JSON, idempotent, chỉ đụng
///   thiết bị của chính người gọi.
class PushDevicesApi {
  PushDevicesApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// Server Render gói miễn phí có thể mất ~1 phút để thức dậy ở lần gọi đầu,
  /// nên các lời gọi này chờ lâu hơn hẳn mặc định. Chạy nền, không chặn UI.
  static const Duration requestTimeout = Duration(seconds: 75);

  // Chỉ Android ở giai đoạn này (cột `platform` của server chỉ nhận 'android').
  static const String _platform = 'android';

  Future<void> register(PushRegistrationId id) {
    return _client.post(
      '/devices',
      body: {
        'registrationId': id.value,
        'kind': id.kindName,
        'platform': _platform,
      },
      timeout: requestTimeout,
    );
  }

  /// Hàm thường (không `async`) để `ApiClient` gắn `Authorization` ngay lúc gọi,
  /// khi token còn trong `AuthStorage` — quan trọng cho luồng đăng xuất.
  Future<void> unregister(String registrationId) {
    return _client
        .delete(
          '/devices',
          body: {'registrationId': registrationId},
          timeout: requestTimeout,
        )
        .then((_) {});
  }
}

/// Giữ đăng ký thiết bị của người dùng đang đăng nhập khớp với back-end.
///
/// - Mỗi khi [PushRegistrationService] phát một định danh (lúc app khởi động đã
///   đăng nhập, sau khi đăng nhập, hoặc FCM làm mới) → `POST /devices`.
/// - Lỗi tạm thời (mất mạng, timeout, 429, 5xx, server đang thức dậy) → thử lại
///   tối đa [maxAttempts] lần với backoff, chạy nền. Hết lượt thì chờ có mạng
///   lại rồi thử một vòng mới; cũng thử lại ở lần phát định danh kế tiếp.
/// - Đăng xuất: [unregisterCurrent] gọi `DELETE /devices` **trước khi** xóa
///   phiên (đăng ký làm hook của `AuthRepository.logout`). Thất bại, hết giờ
///   hoặc mất mạng đều không chặn việc đăng xuất.
///
/// Không bao giờ ghi định danh thiết bị ra log.
class PushDeviceRegistrar {
  PushDeviceRegistrar({
    PushDevicesApi? api,
    PushRegistrationService? registration,
    ValueListenable<bool>? authenticated,
    void Function(Future<void> Function() hook)? addLogoutHook,
    Stream<bool> Function()? onlineChanges,
    Future<void> Function(Duration)? delay,
    Duration logoutWait = const Duration(seconds: 3),
    void Function(String message)? logger,
  }) : _apiOverride = api,
       _registrationOverride = registration,
       _authenticatedOverride = authenticated,
       _addLogoutHookOverride = addLogoutHook,
       _onlineChanges = onlineChanges ?? _defaultOnlineChanges,
       _delay = delay ?? Future<void>.delayed,
       _logoutWait = logoutWait,
       _logger = logger ?? _defaultLogger;

  static final PushDeviceRegistrar instance = PushDeviceRegistrar();

  /// Số lần gọi `POST` tối đa trong một vòng thử.
  static const int maxAttempts = 5;

  /// Chờ giữa các lần thử (lần thứ n dùng phần tử n; vượt thì dùng phần tử cuối).
  static const List<Duration> backoff = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(seconds: 90),
  ];

  /// Trần cho gợi ý `Retry-After` của server.
  static const Duration _maxRetryAfter = Duration(minutes: 2);

  // Tạo lười: `instance` dựng được trước khi Firebase/AuthStorage sẵn sàng.
  final PushDevicesApi? _apiOverride;
  final PushRegistrationService? _registrationOverride;
  final ValueListenable<bool>? _authenticatedOverride;
  final void Function(Future<void> Function() hook)? _addLogoutHookOverride;
  late final PushDevicesApi _api = _apiOverride ?? PushDevicesApi();
  late final PushRegistrationService _registration =
      _registrationOverride ?? PushRegistrationService.instance;
  late final ValueListenable<bool> _authenticated =
      _authenticatedOverride ?? AuthStorage.instance.authenticated;

  final Stream<bool> Function() _onlineChanges;
  final Future<void> Function(Duration) _delay;
  final Duration _logoutWait;
  final void Function(String) _logger;

  bool _attached = false;
  bool _signedIn = false;
  PushRegistrationId? _wanted; // định danh mới nhất cần có trên server
  PushRegistrationId? _registered; // định danh server đã xác nhận
  int _runToken = 0; // tăng để cắt mọi vòng thử lại đã cũ
  StreamSubscription<bool>? _onlineSubscription;

  /// Bắt đầu theo dõi. Gọi một lần, **trước** khi `PushRegistrationService`
  /// được `start()` để không lỡ định danh đầu tiên. Gọi lại là no-op.
  void attach() {
    if (_attached) return;
    _attached = true;
    _signedIn = _authenticated.value;
    _authenticated.addListener(_onAuthChanged);
    _registration.registrationIds.listen(_onRegistrationId);
    (_addLogoutHookOverride ?? AuthRepository.instance.addBeforeLogoutHook)(
      unregisterCurrent,
    );
    // Định danh có thể đã được phát trước khi attach.
    final existing = _registration.current;
    if (existing != null) _onRegistrationId(existing);
  }

  void _onAuthChanged() {
    final signedIn = _authenticated.value;
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    // Đổi người dùng/đăng xuất: bản ghi trên server không còn là của phiên này.
    _wanted = null;
    _registered = null;
    _runToken++;
    _cancelOnlineRetry();
  }

  void _onRegistrationId(PushRegistrationId id) {
    if (!_signedIn) return;
    _wanted = id;
    if (_registered == id) return;
    _startRound(id);
  }

  // ── POST /devices (có thử lại) ──────────────────────────────────────────

  void _startRound(PushRegistrationId id) {
    _cancelOnlineRetry();
    final token = ++_runToken;
    unawaited(
      _registerWithRetry(id, token).catchError((Object error) {
        // Không để lỗi bất ngờ nào lọt ra ngoài thành "unhandled exception".
        _log('đăng ký thiết bị lỗi bất ngờ: ${error.runtimeType}');
      }),
    );
  }

  bool _superseded(PushRegistrationId id, int token) =>
      token != _runToken || !_signedIn || _wanted != id;

  Future<void> _registerWithRetry(PushRegistrationId id, int token) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_superseded(id, token)) return;
      Duration? serverHint;
      try {
        await _api.register(id);
        if (_superseded(id, token)) return;
        _registered = id;
        _log('đã đăng ký thiết bị với server (lần ${attempt + 1})');
        return;
      } on ApiException catch (error) {
        if (!_shouldRetry(error)) {
          _log('không thử lại: ${error.code} (HTTP ${error.statusCode})');
          return;
        }
        serverHint = error.retryAfter;
        _log('lần ${attempt + 1} lỗi tạm thời: ${error.code}');
      } catch (error) {
        // Lỗi mạng không đi qua ApiClient (ClientException, TLS...).
        _log('lần ${attempt + 1} lỗi mạng: ${error.runtimeType}');
      }
      if (attempt == maxAttempts - 1) break;
      await _delay(_backoffFor(attempt, serverHint));
    }
    // Hết lượt: chờ có mạng lại (hoặc định danh mới / lần mở app sau).
    if (!_superseded(id, token)) {
      _log('hết lượt thử, chờ có mạng lại');
      _armOnlineRetry(id, token);
    }
  }

  /// Lỗi tạm thời đáng thử lại. `response_parse_error` được tính vì lúc server
  /// Render đang thức dậy, proxy có thể trả trang HTML thay vì JSON.
  static bool _shouldRetry(ApiException error) =>
      error.isRetryable || error.code == 'response_parse_error';

  static Duration _backoffFor(int attempt, Duration? serverHint) {
    final base =
        backoff[attempt < backoff.length ? attempt : backoff.length - 1];
    if (serverHint == null || serverHint <= base) return base;
    return serverHint > _maxRetryAfter ? _maxRetryAfter : serverHint;
  }

  void _armOnlineRetry(PushRegistrationId id, int token) {
    _onlineSubscription?.cancel();
    _onlineSubscription = _onlineChanges().where((online) => online).listen((
      _,
    ) {
      if (_superseded(id, token)) return;
      _log('có mạng lại, thử đăng ký thiết bị');
      _startRound(id);
    });
  }

  void _cancelOnlineRetry() {
    final subscription = _onlineSubscription;
    _onlineSubscription = null;
    unawaited(subscription?.cancel());
  }

  // ── DELETE /devices (đăng xuất) ─────────────────────────────────────────

  /// Hủy đăng ký thiết bị hiện tại. Được gọi **trước khi** xóa phiên đăng nhập.
  ///
  /// Lời gọi `DELETE` được phát đồng bộ ngay đầu hàm (khi token còn) và chỉ chờ
  /// tối đa [_logoutWait]; sau đó đăng xuất tiếp tục còn request vẫn chạy nền.
  /// Không bao giờ ném lỗi.
  Future<void> unregisterCurrent() async {
    final id = _registration.current ?? _wanted;
    // Dừng mọi vòng thử lại và chặn định danh mới được POST trong lúc đăng xuất.
    _signedIn = false;
    _wanted = null;
    _registered = null;
    _runToken++;
    _cancelOnlineRetry();
    if (id == null) return;

    final Future<void> call;
    try {
      call = _api.unregister(id.value);
    } catch (error) {
      _log('hủy đăng ký thiết bị lỗi: ${error.runtimeType}');
      return;
    }
    try {
      await call.timeout(_logoutWait);
      _log('đã hủy đăng ký thiết bị trên server');
    } on TimeoutException {
      _log('hủy đăng ký chậm, tiếp tục đăng xuất (request vẫn chạy nền)');
    } on ApiException catch (error) {
      _log('hủy đăng ký thất bại: ${error.code} (HTTP ${error.statusCode})');
    } catch (error) {
      _log('hủy đăng ký thất bại: ${error.runtimeType}');
    }
  }

  // ── Tiện ích ────────────────────────────────────────────────────────────

  static Stream<bool> _defaultOnlineChanges() => Connectivity()
      .onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));

  /// Log chỉ ở bản debug và tuyệt đối không chứa định danh thiết bị.
  static void _defaultLogger(String message) {
    if (kDebugMode) debugPrint('[push] $message');
  }

  void _log(String message) => _logger(message);
}
