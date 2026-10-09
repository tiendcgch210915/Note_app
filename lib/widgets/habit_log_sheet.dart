import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';
import '../utils/date_utils.dart';
import 'app_sheet.dart';
import 'habit_calendar_grid.dart';
import 'habit_today_log_panel.dart';

/// Bảng nổi lên từ dưới (không phủ kín màn hình) để xác nhận thói quen hôm nay:
/// lịch 28 ngày chỉ để xem, ngay bên dưới là câu hỏi "Đã hoàn thành hôm nay
/// chưa?" với hai nút "Hoàn thành" / "Bỏ lỡ".
///
/// Trả về `true` khi bấm "Hoàn thành", `false` khi bấm "Bỏ lỡ" và `null` nếu
/// người dùng đóng bảng mà không chọn. Hàm này **không** ghi log — nơi gọi tự
/// xử lý kết quả.
///
/// [completedByDate] là trạng thái các ngày gần đây của thói quen (ngày vắng
/// mặt = chưa ghi nhận).
Future<bool?> showHabitLogSheet(
  BuildContext context, {
  required Habit habit,
  required Map<DateTime, bool> completedByDate,
  DateTime? today,
}) {
  final day = AppDateUtils.dateOnly(today ?? DateTime.now());
  return showAppSheet<bool>(
    context: context,
    builder: (ctx) => AppSheetScaffold(
      title: habit.title,
      bodyPadding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HabitCalendarGrid(
            habit: habit,
            completedByDate: completedByDate,
            today: day,
            surfaceColor: ctx.appBackground,
            showShadow: false,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: HabitTodayLogPanel(
              completed: completedByDate[day],
              onLog: (completed) {
                if (completed) {
                  AppHaptics.medium();
                } else {
                  AppHaptics.light();
                }
                Navigator.of(ctx).pop(completed);
              },
            ),
          ),
        ],
      ),
    ),
  );
}
