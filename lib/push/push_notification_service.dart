import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/auth_storage.dart';
import 'push_device_registrar.dart';
import 'push_navigation.dart';
import 'push_registration_service.dart';
import 'push_target.dart';

/// Thông báo đẩy qua FCM (chỉ Android) — giai đoạn 1: phía app, chưa gọi
/// back-end.
///
/// - [init] (gọi sau `Firebase.initializeApp`): tạo kênh thông báo, gắn các
///   listener, xử lý thông báo đã mở app lúc khởi động nguội.
/// - Đăng nhập/đăng xuất được phát hiện qua `AuthStorage.authenticated` nên
///   không phải vá vào từng màn hình: đăng nhập → lấy định danh thiết bị và xin
///   quyền hiện thông báo; đăng xuất → dừng theo dõi định danh.
///
/// Không in token/ID thiết bị ra log ngoài bản debug.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  /// Phải khớp meta-data `default_notification_channel_id` trong
  /// AndroidManifest để thông báo FCM lúc app ở nền dùng đúng kênh này.
  static const String channelId = 'general_notifications';
  static const String channelName = 'Thông báo chung';
  static const String channelDescription =
      'Nhắc việc và thông báo chung của ứng dụng';

  /// Tên drawable (không kèm `@drawable/`), khớp `res/drawable/`.
  static const String _smallIcon = 'ic_stat_notification';

  /// Mới hỗ trợ Android. iOS/web để sau.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final PushRegistrationService _registration =
      PushRegistrationService.instance;
  final PushNavigation _navigation = PushNavigation.instance;

  bool _initialized = false;
  bool _signedIn = false;

  /// Cần gọi sau `Firebase.initializeApp`. Gọi lại là no-op.
  Future<void> init() async {
    if (!isSupported || _initialized) return;
    _initialized = true;

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_smallIcon),
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.high,
          ),
        );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    await _handleLaunchNotification();

    // Phải attach trước khi `_registration.start()` chạy (bên dưới) để không
    // lỡ định danh đầu tiên.
    PushDeviceRegistrar.instance.attach();

    final authenticated = AuthStorage.instance.authenticated;
    authenticated.addListener(() => _onAuthChanged(authenticated.value));
    _onAuthChanged(authenticated.value);
  }

  // ── Đăng nhập / đăng xuất ───────────────────────────────────────────────

  void _onAuthChanged(bool authenticated) {
    if (authenticated == _signedIn) return;
    _signedIn = authenticated;
    if (authenticated) {
      unawaited(_onSignedIn());
    } else {
      unawaited(_registration.stop());
    }
  }

  Future<void> _onSignedIn() async {
    // Định danh thiết bị không cần quyền thông báo nên lấy ngay.
    unawaited(_registration.start());
    // Đừng bật hộp thoại xin quyền khi màn hình khởi động còn đang hiện.
    await _navigation.appReady;
    if (!_signedIn) return; // đã đăng xuất trong lúc chờ
    await _requestPermissionIfNeeded();
  }

  /// Chỉ xin khi người dùng chưa từng được hỏi (`notDetermined`). Đã từ chối
  /// thì không hỏi lại mỗi lần mở app; muốn bật lại, họ vào cài đặt hệ thống.
  Future<void> _requestPermissionIfNeeded() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.notDetermined) {
        return;
      }
      await messaging.requestPermission();
    } catch (error) {
      _log('xin quyền thông báo lỗi: $error');
    }
  }

  // ── Nhận thông báo ──────────────────────────────────────────────────────

  /// Android không tự hiện thông báo FCM khi app đang mở, nên hiện bằng
  /// thông báo cục bộ và gắn `type`/`id` vào payload để chạm vào còn điều hướng.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) {
      // Tin chỉ có data: không có gì để hiện. Cần xử lý thì thêm ở giai đoạn sau.
      _log('bỏ qua tin chỉ có data (${message.messageId})');
      return;
    }
    // Đã đăng xuất: không hiện thông báo của tài khoản cũ.
    if (!_signedIn) return;
    try {
      await _local.show(
        id: _notificationId(message),
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            icon: _smallIcon,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: PushTarget.fromData(message.data)?.toPayload(),
      );
    } catch (error) {
      _log('hiện thông báo lỗi: $error');
    }
  }

  static int _notificationId(RemoteMessage message) {
    final key =
        message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString();
    return key.hashCode & 0x7FFFFFFF; // id phải là số nguyên dương 31 bit
  }

  // ── Chạm vào thông báo ──────────────────────────────────────────────────

  /// Chạm thông báo FCM khi app đang ở nền. (App đã tắt hẳn thì bản
  /// firebase_messaging 16.7.0 trên Android **không** gọi hàm này mà phải dùng
  /// `getInitialMessage` — xem [_handleLaunchNotification].)
  void _onMessageOpenedApp(RemoteMessage message) {
    _openTarget(PushTarget.fromData(message.data));
  }

  /// Chạm thông báo cục bộ (thông báo ta tự hiện lúc app đang mở).
  void _onLocalNotificationTapped(NotificationResponse response) {
    _openTarget(PushTarget.fromPayload(response.payload));
  }

  /// Khởi động nguội do chạm vào thông báo: hoặc thông báo FCM do hệ điều hành
  /// hiện (→ `getInitialMessage`), hoặc thông báo cục bộ còn sót lại sau khi
  /// app bị tắt (→ `getNotificationAppLaunchDetails`; callback chạm không được
  /// gọi trong trường hợp này).
  Future<void> _handleLaunchNotification() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _openTarget(PushTarget.fromData(initial.data));
        return;
      }
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _openTarget(
          PushTarget.fromPayload(launch!.notificationResponse?.payload),
        );
      }
    } catch (error) {
      _log('đọc thông báo lúc khởi động lỗi: $error');
    }
  }

  void _openTarget(PushTarget? target) {
    if (target == null) return;
    _navigation.handle(target);
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[push] $message');
  }
}
