import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'app_surface.dart';

/// Nhóm hàng kiểu "inset grouped" của iOS: một thẻ bo góc chứa nhiều hàng,
/// ngăn cách bằng đường kẻ chân tóc thụt vào.
class AppListSection extends StatelessWidget {
  /// Lề trái của đường kẻ khi hàng có icon (icon 30 + khoảng cách + padding).
  static const double iconIndent = 58;

  final String? header;
  final String? footer;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final double dividerIndent;

  const AppListSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.dividerIndent = 16,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = context.appTextSecondary;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: dividerIndent,
            color: context.appDivider,
          ),
        );
      }
      rows.add(children[i]);
    }

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                header!.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: secondary,
                ),
              ),
            ),
          AppSurface(
            radius: AppRadius.lg,
            showShadow: false,
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                footer!,
                style: TextStyle(fontSize: 12, height: 1.3, color: secondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Nút "x" tròn ở cuối hàng để xoá giá trị đã chọn (vùng chạm ≥ 36px).
class AppClearButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  const AppClearButton({super.key, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            Icons.cancel_rounded,
            size: 20,
            color: context.appTextSecondary.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

/// Một hàng trong [AppListSection]: icon tinted (tuỳ chọn), tiêu đề, giá trị
/// phụ và mũi tên. Có phản hồi nhấn (nền đổi màu nhẹ).
class AppListTile extends StatefulWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool destructive;

  /// Mặc định: hiện mũi tên khi có [onTap] và không có [trailing].
  final bool? showChevron;

  const AppListTile({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.destructive = false,
    this.showChevron,
  });

  @override
  State<AppListTile> createState() => _AppListTileState();
}

class _AppListTileState extends State<AppListTile> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v || !mounted) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final secondary = context.appTextSecondary;
    final tappable = widget.onTap != null || widget.onLongPress != null;
    final accent = widget.destructive
        ? AppColors.danger
        : (widget.iconColor ?? context.appPrimary);
    final titleColor = widget.destructive
        ? AppColors.danger
        : context.appTextPrimary;
    final chevron = widget.showChevron ?? (widget.onTap != null);

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Row(
          children: [
            if (widget.icon != null) ...[
              Container(
                width: 30,
                height: 30,
                decoration: ShapeDecoration(
                  color: accent.withValues(alpha: context.isDark ? 0.22 : 0.14),
                  shape: AppShape.squircle(8),
                ),
                child: Icon(widget.icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 16,
                      color: titleColor,
                      fontWeight: widget.destructive
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.value != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 15, color: secondary),
                ),
              ),
            ],
            if (widget.trailing != null) ...[
              const SizedBox(width: 8),
              widget.trailing!,
            ],
            if (chevron && widget.trailing == null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: secondary.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );

    if (!tappable) return row;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        color: _pressed
            ? context.appTextPrimary.withValues(alpha: 0.06)
            : Colors.transparent,
        child: row,
      ),
    );
  }
}
