import 'package:flutter/material.dart';

import '../data/api_exception.dart';
import '../screens/checklists/run_detail_screen.dart';
import '../screens/todos/todo_detail_screen.dart';
import '../theme/app_colors.dart';
import '../utils/app_navigator.dart';
import '../utils/app_snack.dart';
import '../utils/checklist_session_controller.dart';
import '../utils/focus_session_controller.dart';

/// Thanh "đang làm" toàn app, đặt trong `MaterialApp.builder`. Hiện cho phiên
/// đang chạy ngầm: tập trung vào một todo (đếm ngược) hoặc đang làm một
/// checklist (đếm xuôi). Tại một thời điểm chỉ có một phiên (xem
/// `ActiveSessionLock`).
///
/// Thanh chiếm chỗ thật trong layout (Column) thay vì nổi đè lên nội dung, để
/// không che BottomNavigationBar, FAB hay thanh nút dưới của từng màn hình.
/// Ẩn khi màn hình của chính phiên đó đang mở (đã có đồng hồ lớn) hoặc khi bàn
/// phím mở.
class FocusSessionBannerHost extends StatelessWidget {
  final Widget child;

  const FocusSessionBannerHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final todo = FocusSessionController.instance;
    final checklist = ChecklistSessionController.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([
        todo.focusScreenOpen,
        todo.session,
        checklist.session,
        checklist.openRunScreens,
      ]),
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final banner = media.viewInsets.bottom == 0
            ? _currentBanner(todo, checklist)
            : null;
        final show = banner != null;
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
            if (banner != null) banner,
          ],
        );
      },
    );
  }

  static Widget? _currentBanner(
    FocusSessionController todo,
    ChecklistSessionController checklist,
  ) {
    final todoSession = todo.session.value;
    if (todoSession != null) {
      return todo.focusScreenOpen.value
          ? null
          : _FocusSessionBanner(session: todoSession);
    }
    final run = checklist.session.value;
    if (run != null) {
      return checklist.openRunScreens.value.contains(run.runId)
          ? null
          : _ChecklistSessionBanner(session: run);
    }
    return null;
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
    final isOver = session.isOver;
    return _SessionBar(
      key: const ValueKey('focus-session-banner'),
      icon: Icons.timer_outlined,
      caption: 'Đang tập trung · nhấn để quay lại',
      title: session.todo.title,
      timeText: isOver ? 'Hết giờ' : formatFocusDuration(session.remaining),
      accent: isOver ? AppColors.danger : AppColors.primary,
      onTap: resumeFocusSession,
      stopKey: const ValueKey('focus-session-banner-stop'),
      stopLabel: 'Kết thúc phiên tập trung',
      onStop: _confirmStop,
    );
  }
}

class _ChecklistSessionBanner extends StatelessWidget {
  final ChecklistSession session;

  const _ChecklistSessionBanner({required this.session});

  Future<void> _confirmAbandon() async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final abandon = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy bỏ checklist?'),
        content: Text(
          '"${session.title}" sẽ được lưu là "Đã hủy" cùng tiến độ hiện tại. '
          'Hoàn tất checklist để ghi nhận thời gian thực hiện.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Không'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hủy bỏ'),
          ),
        ],
      ),
    );
    if (abandon != true) return;
    try {
      await ChecklistSessionController.instance.abandonActive();
    } on ApiException catch (e) {
      final errorContext = rootNavigatorKey.currentContext;
      if (errorContext != null && errorContext.mounted) {
        showAppSnack(errorContext, e.vnMessage, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = session.doneSteps;
    final total = session.totalSteps;
    final progress = done == null || total == null
        ? ''
        : ' · $done/$total bước';
    return _SessionBar(
      key: const ValueKey('checklist-session-banner'),
      icon: Icons.checklist_rounded,
      caption: 'Đang làm checklist$progress',
      title: session.title,
      timeText: formatFocusDuration(session.elapsed),
      accent: AppColors.primary,
      onTap: resumeChecklistSession,
      stopKey: const ValueKey('checklist-session-banner-stop'),
      stopLabel: 'Hủy bỏ checklist đang làm',
      onStop: _confirmAbandon,
    );
  }
}

/// Khung thanh dưới cùng dùng chung cho mọi loại phiên.
class _SessionBar extends StatelessWidget {
  final IconData icon;
  final String caption;
  final String title;
  final String timeText;
  final Color accent;
  final VoidCallback onTap;
  final Key stopKey;
  final String stopLabel;
  final VoidCallback onStop;

  const _SessionBar({
    super.key,
    required this.icon,
    required this.caption,
    required this.title,
    required this.timeText,
    required this.accent,
    required this.onTap,
    required this.stopKey,
    required this.stopLabel,
    required this.onStop,
  });

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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: divider)),
      ),
      child: SafeArea(
        top: false,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
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
                    child: Icon(icon, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          caption,
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
                          title,
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
                    timeText,
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
                    label: stopLabel,
                    button: true,
                    child: IconButton(
                      key: stopKey,
                      icon: Icon(Icons.stop_circle_outlined, color: secondary),
                      onPressed: onStop,
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
