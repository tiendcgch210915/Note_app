import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';

/// Mở bottom sheet thống nhất. Bo góc, tay nắm kéo và nền do `bottomSheetTheme`
/// quyết định; hàm này lo cuộn theo bàn phím + vùng an toàn.
///
/// Luôn dùng `isScrollControlled: true` để sheet có thể cao tới hết màn hình
/// (mặc định của Flutter giới hạn ~56% chiều cao nên nội dung dài dễ tràn).
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useSafeArea = true,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    builder: builder,
  );
}

/// Khung chuẩn cho nội dung sheet: tiêu đề cố định + phần thân **cuộn được**.
/// Dùng khung này (thay vì `Column(mainAxisSize: min)` trần) để sheet không bao
/// giờ báo "Bottom overflowed" khi màn hình thấp hoặc chữ hệ thống lớn.
class AppSheetScaffold extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? headerTrailing;
  final EdgeInsetsGeometry bodyPadding;
  final Widget child;

  const AppSheetScaffold({
    super.key,
    this.title,
    this.subtitle,
    this.headerTrailing,
    this.bodyPadding = EdgeInsets.zero,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Tiêu đề cũng nằm trong vùng cuộn: tiêu đề rất dài + chữ lớn + màn thấp
    // vẫn không đẩy phần thân ra ngoài màn hình.
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              AppSheetHeader(
                title: title!,
                subtitle: subtitle,
                trailing: headerTrailing,
              ),
            Padding(padding: bodyPadding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Tiêu đề chuẩn cho nội dung sheet.
class AppSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const AppSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 12, 12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Hộp thoại xác nhận. Trả về `true` khi người dùng đồng ý.
/// [destructive] tô đỏ nút xác nhận và rung mạnh khi bấm.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Đồng ý',
  String cancelLabel = 'Hủy',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            cancelLabel,
            style: TextStyle(color: ctx.appTextSecondary),
          ),
        ),
        TextButton(
          onPressed: () {
            if (destructive) {
              AppHaptics.heavy();
            } else {
              AppHaptics.light();
            }
            Navigator.of(ctx).pop(true);
          },
          child: Text(
            confirmLabel,
            style: destructive
                ? const TextStyle(color: AppColors.danger)
                : null,
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Hộp thoại nhập một dòng (hoặc đoạn) chữ. Trả về chữ đã `trim()` khi người
/// dùng xác nhận (có thể rỗng), `null` khi hủy hoặc chạm ra ngoài.
///
/// Dùng hàm này thay vì tự tạo `TextEditingController` rồi `dispose()` ngay sau
/// `await showDialog`: lúc đó dialog còn đang chạy hiệu ứng đóng, `TextField`
/// vẫn dùng controller đã hủy và cả app hiện màn hình lỗi đỏ. Ở đây controller
/// thuộc về State của dialog nên chỉ bị hủy khi dialog đã gỡ khỏi cây.
Future<String?> showAppTextInputDialog(
  BuildContext context, {
  required String title,
  String? hintText,
  String initialText = '',
  String confirmLabel = 'Lưu',
  String cancelLabel = 'Hủy',
  int maxLines = 1,
  int? maxLength,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _AppTextInputDialog(
      title: title,
      hintText: hintText,
      initialText: initialText,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      maxLines: maxLines,
      maxLength: maxLength,
    ),
  );
}

class _AppTextInputDialog extends StatefulWidget {
  final String title;
  final String? hintText;
  final String initialText;
  final String confirmLabel;
  final String cancelLabel;
  final int maxLines;
  final int? maxLength;

  const _AppTextInputDialog({
    required this.title,
    required this.hintText,
    required this.initialText,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.maxLines,
    required this.maxLength,
  });

  @override
  State<_AppTextInputDialog> createState() => _AppTextInputDialogState();
}

class _AppTextInputDialogState extends State<_AppTextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final singleLine = widget.maxLines == 1;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        textInputAction: singleLine
            ? TextInputAction.done
            : TextInputAction.newline,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: singleLine ? (_) => _submit() : null,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        TextButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
