import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Route chuyển mờ dần — dùng khi đổi "thế giới" (đăng nhập ↔ trang chính)
/// thay vì trượt ngang như các màn hình thường.
class AppRoutes {
  AppRoutes._();

  static Route<T> fade<T>(WidgetBuilder builder) {
    return PageRouteBuilder<T>(
      transitionDuration: AppMotion.slow,
      reverseTransitionDuration: AppMotion.normal,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AppMotion.curve),
        child: child,
      ),
    );
  }
}
