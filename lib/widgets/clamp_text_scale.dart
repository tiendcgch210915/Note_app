import 'package:flutter/widgets.dart';

/// Giới hạn cỡ chữ hệ thống tối đa [maxScale] cho [child].
///
/// Dùng cho các ô/thẻ có chiều cao cố định theo lưới (Eisenhower, lịch, thói
/// quen...): chiều cao ô co giãn tới đúng [maxScale], còn chữ bên trong không
/// được phóng to quá mức đó — nếu không nội dung sẽ lớn hơn ô và báo
/// "Bottom overflowed".
class ClampTextScale extends StatelessWidget {
  final double maxScale;
  final Widget child;

  const ClampTextScale({
    super.key,
    required this.maxScale,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxScale,
      child: child,
    );
  }
}
