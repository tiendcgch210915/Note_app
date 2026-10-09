import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';

/// Hiệu ứng nhấn kiểu iOS: thu nhỏ + mờ nhẹ khi đang chạm.
///
/// Dùng [Listener] (pointer thô) nên không tranh gesture arena với
/// `InkWell`/`GestureDetector` bên trong, và không bị che như ripple khi thẻ
/// có nền đặc. Tự trả về trạng thái bình thường khi ngón tay trượt đi (đang
/// cuộn danh sách).
class Pressable extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double scale;
  final bool haptic;

  const Pressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
    this.haptic = false,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  static const double _slop = 12;

  bool _pressed = false;
  Offset? _downAt;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _downAt = event.position;
    _setPressed(true);
  }

  void _onMove(PointerMoveEvent event) {
    final start = _downAt;
    if (!_pressed || start == null) return;
    if ((event.position - start).distance > _slop) _setPressed(false);
  }

  void _onUp(PointerUpEvent event) {
    if (_pressed && widget.haptic) AppHaptics.light();
    _downAt = null;
    _setPressed(false);
  }

  void _onCancel(PointerCancelEvent event) {
    _downAt = null;
    _setPressed(false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.9 : 1,
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          child: widget.child,
        ),
      ),
    );
  }
}
