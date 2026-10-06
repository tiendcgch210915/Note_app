import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class TodoSwipeActions extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final bool enabled;
  final TodoSwipeDirection direction;
  final TodoSwipeActionAlignment actionAlignment;

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
  });

  @override
  State<TodoSwipeActions> createState() => _TodoSwipeActionsState();
}

enum TodoSwipeDirection { left, right }

enum TodoSwipeActionAlignment { center, top }

class _TodoSwipeActionsState extends State<TodoSwipeActions> {
  static final ValueNotifier<Object?> _openToken = ValueNotifier<Object?>(null);
  static const double _actionSize = 36;
  static const Duration _snapDuration = Duration(milliseconds: 160);

  final Object _token = Object();
  double _reveal = 0;
  bool _dragging = false;

  double get _maxReveal =>
      _actions.length * _actionSize + (_actions.length - 1) * 10 + 32;

  List<_SwipeActionSpec> get _actions {
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
            backgroundColor: AppColors.primarySoft,
            iconColor: AppColors.primary,
            onPressed: widget.onEdit!,
          ),
      ];
    }
    return [
      if (widget.onPickDate != null)
        _SwipeActionSpec(
          tooltip: 'Đổi ngày',
          icon: Icons.calendar_today_rounded,
          backgroundColor: AppColors.primarySoft,
          iconColor: AppColors.primary,
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
    setState(() => _reveal = reveal);
  }

  void _close() {
    if (_reveal == 0) return;
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
    final background = Theme.of(context).scaffoldBackgroundColor;
    final canTapActions = widget.enabled && _reveal > _actionSize;
    final actions = _actions;
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
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: _TodoSwipeActionsState._actionSize,
            height: _TodoSwipeActionsState._actionSize,
            child: Icon(icon, color: iconColor, size: 18),
          ),
        ),
      ),
    );
  }
}
