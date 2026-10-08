import 'package:flutter/material.dart';

import '../screens/todos/todo_detail_screen.dart';
import '../theme/app_colors.dart';
import '../utils/app_navigator.dart';
import '../utils/focus_session_controller.dart';

/// Thanh "đang tập trung" toàn app, đặt trong `MaterialApp.builder`.
///
/// Thanh chiếm chỗ thật trong layout (Column) thay vì nổi đè lên nội dung, để
/// không che BottomNavigationBar, FAB hay thanh nút dưới của từng màn hình.
/// Ẩn khi màn hình Focus đang mở (đã có đồng hồ lớn) hoặc khi bàn phím mở.
class FocusSessionBannerHost extends StatelessWidget {
  final Widget child;

  const FocusSessionBannerHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final controller = FocusSessionController.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: controller.focusScreenOpen,
      builder: (context, screenOpen, _) {
        return ValueListenableBuilder<FocusSession?>(
          valueListenable: controller.session,
          builder: (context, session, _) {
            final media = MediaQuery.of(context);
            final show =
                session != null && !screenOpen && media.viewInsets.bottom == 0;
            // Banner đã tự xử lý safe-area đáy, nên phần nội dung phía trên
            // phải coi như không còn inset đáy để tránh chừa khoảng trống kép.
            final contentMedia = show
                ? media.copyWith(
                    padding: media.padding.copyWith(bottom: 0),
                    viewPadding: media.viewPadding.copyWith(bottom: 0),
                  )
                : media;
            return Column(
              children: [
                Expanded(
                  child: MediaQuery(data: contentMedia, child: child),
                ),
                if (show) _FocusSessionBanner(session: session),
              ],
            );
          },
        );
      },
    );
  }
}

class _FocusSessionBanner extends StatelessWidget {
  final FocusSession session;

  const _FocusSessionBanner({required this.session});

  Future<void> _confirmStop() async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final stop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kết thúc phiên tập trung?'),
        content: Text(
          'Đồng hồ cho "${session.todo.title}" sẽ dừng lại. '
          'Trạng thái công việc vẫn được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kết thúc'),
          ),
        ],
      ),
    );
    if (stop == true) FocusSessionController.instance.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.surfaceDark : AppColors.surface;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;
    final textPrimary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final isOver = session.isOver;
    final accent = isOver ? AppColors.danger : AppColors.primary;
    return DecoratedBox(
      key: const ValueKey('focus-session-banner'),
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: divider)),
      ),
      child: SafeArea(
        top: false,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: resumeFocusSession,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.timer_outlined, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Đang tập trung · nhấn để quay lại',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session.todo.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isOver ? 'Hết giờ' : formatFocusDuration(session.remaining),
                    style: TextStyle(
                      color: accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  // Không dùng `tooltip`: banner nằm trên Navigator nên không
                  // có Overlay ancestor.
                  Semantics(
                    label: 'Kết thúc phiên tập trung',
                    button: true,
                    child: IconButton(
                      key: const ValueKey('focus-session-banner-stop'),
                      icon: Icon(Icons.stop_circle_outlined, color: secondary),
                      onPressed: _confirmStop,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
