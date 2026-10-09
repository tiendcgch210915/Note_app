import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';

class TodoSwipeActions extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final bool enabled;
  final TodoSwipeDirection direction;
  final TodoSwipeActionAlignment actionAlignment;

  /// Màu nền phủ phía sau/trên hàng khi vuốt (mặc định: màu nền màn hình).
  /// Đặt bằng màu của thẻ chứa khi hàng nằm trong một thẻ có nền riêng.
  final Color? backgroundColor;

  const TodoSwipeActions({
    super.key,
    required this.child,
    required this.onPickTime,
    this.onPickDate,
    this.onDelete,
    this.onEdit,
    this.enabled = true,
    this.direction = TodoSwipeDirection.left,
    this.actionAlignment = TodoSwipeActionAlignment.center,
    this.backgroundColor,
  });

  @override
  State<TodoSwipeActions> createState() => _TodoSwipeActionsState();
}

enum TodoSwipeDirection { left, right }

enum TodoSwipeActionAlignment { center, top }

class _TodoSwipeActionsState extends State<TodoSwipeActions> {
  static final ValueNotifier<Object?> _openToken = ValueNotifier<Object?>(null);
  static const double _actionSize = 44;
  static const Duration _snapDuration = Duration(milliseconds: 160);

  final Object _token = Object();
  double _reveal = 0;
  bool _dragging = false;
  bool _pastDetent = false;

  int get _actionCount {
    if (widget.direction == TodoSwipeDirection.right) {
      return 1 + (widget.onEdit != null ? 1 : 0);
    }
    return (widget.onPickDate != null ? 1 : 0) +
        1 +
        (widget.onDelete != null ? 1 : 0);
  }

  double get _maxReveal =>
      _actionCount * _actionSize + (_actionCount - 1) * 10 + 32;

  List<_SwipeActionSpec> _buildActions(BuildContext context) {
    final primary = context.appPrimary;
    final primarySoft = context.appPrimarySoft;
    if (widget.direction == TodoSwipeDirection.right) {
      return [
        _SwipeActionSpec(
          tooltip: 'Đổi giờ',
          icon: Icons.schedule_rounded,
          backgroundColor: AppColors.warning.withValues(alpha: 0.14),
          iconColor: AppColors.warning,
          onPressed: widget.onPickTime,
        ),
        if (widget.onEdit != null)
          _SwipeActionSpec(
            tooltip: 'Chỉnh sửa',
            icon: Icons.edit_rounded,
            backgroundColor: primarySoft,
            iconColor: primary,
            onPressed: widget.onEdit!,
          ),
      ];
    }
    return [
      if (widget.onPickDate != null)
        _SwipeActionSpec(
          tooltip: 'Đổi ngày',
          icon: Icons.calendar_today_rounded,
          backgroundColor: primarySoft,
          iconColor: primary,
          onPressed: widget.onPickDate!,
        ),
      _SwipeActionSpec(
        tooltip: 'Đổi giờ',
        icon: Icons.schedule_rounded,
        backgroundColor: AppColors.warning.withValues(alpha: 0.14),
        iconColor: AppColors.warning,
        onPressed: widget.onPickTime,
      ),
      if (widget.onDelete != null)
        _SwipeActionSpec(
          tooltip: 'Xóa todo',
          icon: Icons.delete_rounded,
          backgroundColor: AppColors.danger.withValues(alpha: 0.14),
          iconColor: AppColors.danger,
          onPressed: widget.onDelete!,
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _openToken.addListener(_onOpenTokenChanged);
  }

  @override
  void dispose() {
    _openToken.removeListener(_onOpenTokenChanged);
    super.dispose();
  }

  void _onOpenTokenChanged() {
    if (_openToken.value == _token || _reveal == 0 || !mounted) return;
    _close();
  }

  void _setReveal(double value) {
    final reveal = value.clamp(0, _maxReveal).toDouble();
    if (reveal > _actionSize && _openToken.value != _token) {
      _openToken.value = _token;
    }
    final pastDetent = reveal > _maxReveal * 0.35;
    if (_dragging && pastDetent != _pastDetent) AppHaptics.selection();
    _pastDetent = pastDetent;
    setState(() => _reveal = reveal);
  }

  void _close() {
    if (_reveal == 0) return;
    _pastDetent = false;
    setState(() {
      _dragging = false;
      _reveal = 0;
    });
  }

  void _runAction(VoidCallback action) {
    _close();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final background =
        widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    final canTapActions = widget.enabled && _reveal > _actionSize;
    final actions = _buildActions(context);
    final isRight = widget.direction == TodoSwipeDirection.right;
    final alignTop = widget.actionAlignment == TodoSwipeActionAlignment.top;
    final actionAlignment = switch (widget.actionAlignment) {
      TodoSwipeActionAlignment.center =>
        isRight ? Alignment.centerLeft : Alignment.centerRight,
      TodoSwipeActionAlignment.top =>
        isRight ? Alignment.topLeft : Alignment.topRight,
    };
    return ClipRect(
      child: Stack(
        alignment: actionAlignment,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: background,
              child: Align(
                alignment: actionAlignment,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: isRight ? 16 : 0,
                    top: alignTop ? 8 : 0,
                    right: isRight ? 0 : 16,
                  ),
                  child: IgnorePointer(
                    ignoring: !canTapActions,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          _CircleActionButton(
                            tooltip: actions[i].tooltip,
                            icon: actions[i].icon,
                            backgroundColor: actions[i].backgroundColor,
                            iconColor: actions[i].iconColor,
                            onPressed: () => _runAction(actions[i].onPressed),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: widget.enabled
                ? (_) => setState(() => _dragging = true)
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (details) => _setReveal(
                    _reveal + (isRight ? details.delta.dx : -details.delta.dx),
                  )
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) {
                    final open = _reveal > _maxReveal * 0.35;
                    setState(() {
                      _dragging = false;
                      _reveal = open ? _maxReveal : 0;
                    });
                    if (open) {
                      _openToken.value = _token;
                    } else if (_openToken.value == _token) {
                      _openToken.value = null;
                    }
                  }
                : null,
            onHorizontalDragCancel: widget.enabled
                ? () {
                    final open = _reveal > _maxReveal * 0.35;
                    setState(() {
                      _dragging = false;
                      _reveal = open ? _maxReveal : 0;
                    });
                    if (open) {
                      _openToken.value = _token;
                    } else if (_openToken.value == _token) {
                      _openToken.value = null;
                    }
                  }
                : null,
            child: AnimatedContainer(
              duration: _dragging ? Duration.zero : _snapDuration,
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(
                isRight ? _reveal : -_reveal,
                0,
                0,
              ),
              child: ColoredBox(color: background, child: widget.child),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeActionSpec {
  final String tooltip;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onPressed;

  const _SwipeActionSpec({
    required this.tooltip,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.onPressed,
  });
}

class _CircleActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onPressed;

  const _CircleActionButton({
    required this.tooltip,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Thẻ thấp (vd. todo đã xong trong timeline) -> thu nút cho vừa chiều cao.
        const full = _TodoSwipeActionsState._actionSize;
        final side = constraints.maxHeight.isFinite
            ? math.min(full, constraints.maxHeight)
            : full;
        final shape = AppShape.squircle(AppRadius.md);
        return Tooltip(
          message: tooltip,
          child: Material(
            color: backgroundColor,
            shape: shape,
            child: InkWell(
              customBorder: shape,
              onTap: onPressed,
              child: SizedBox(
                width: full,
                height: side,
                child: Icon(icon, color: iconColor, size: 20),
              ),
            ),
          ),
        );
      },
    );
  }
}
