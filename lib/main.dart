import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'push/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initPush();
  runApp(const MyApp());
}

/// Khởi tạo Firebase + kênh thông báo. Lỗi ở đây (thiếu Google Play services,
/// cấu hình sai...) chỉ làm tắt tính năng thông báo, không được chặn app mở.
Future<void> _initPush() async {
  if (!PushNotificationService.isSupported) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await PushNotificationService.instance.init();
  } catch (error) {
    if (kDebugMode) debugPrint('[push] init failed: $error');
  }
}
