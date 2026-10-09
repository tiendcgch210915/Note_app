import 'package:flutter/material.dart';
import '../models/todo.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import '../utils/date_utils.dart';
import 'duration_picker_sheet.dart';
import 'habit_link_chip.dart';
import 'tag_chip.dart';
import 'todo_timed_title.dart';

/// 1 hàng todo theo style Microsoft To Do / Reminders của iOS.
class TodoTile extends StatelessWidget {
  final Todo todo;
  final VoidCallback? onTap;
  final VoidCallback? onToggleDone;
  final bool compact;

  const TodoTile({
    super.key,
    required this.todo,
    this.onTap,
    this.onToggleDone,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = context.appTextPrimary;
    final textSecondary = context.appTextSecondary;
    final divider = context.appDivider;
    final done = todo.isDone;

    final subtitleChips = <Widget>[];
    if (todo.isFrog) {
      subtitleChips.add(_chip(Icons.eco, 'Frog', AppColors.frog));
    }
    if (todo.isImportant == true) {
      subtitleChips.add(_chip(Icons.star, 'Quan trọng', AppColors.warning));
    }
    final displayDate = todo.scheduledDate ?? todo.dueAt;
    if (displayDate != null) {
      subtitleChips.add(
        _chip(
          Icons.calendar_today,
          AppDateUtils.formatRelative(displayDate),
          textSecondary,
        ),
      );
    }
    if (todo.estimatedMinutes != null) {
      subtitleChips.add(
        _chip(
          Icons.hourglass_empty,
          formatDurationMinutesShort(todo.estimatedMinutes!),
          textSecondary,
        ),
      );
    }
    if (todo.isRecurring) {
      subtitleChips.add(
        _chip(
          Icons.repeat,
          todo.hasRecurrenceRule ? todo.recurrenceLabel : 'Lặp lại',
          context.appPrimary,
        ),
      );
    }
    if (todo.habitId != null) {
      subtitleChips.add(HabitLinkChip(habitId: todo.habitId));
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 6 : 10,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divider, width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: onToggleDone == null
                  ? null
                  : () {
                      if (!done) AppHaptics.medium();
                      onToggleDone!();
                    },
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: AppMotion.normal,
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      key: ValueKey(done),
                      size: 26,
                      color: done ? context.appPrimary : textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: AppMotion.normal,
                    style: TextStyle(
                      color: done ? textSecondary : textPrimary,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: textSecondary,
                    ),
                    child: TodoTimedTitle(
                      title: todo.title,
                      time: todo.time,
                      scheduledDate: todo.scheduledDate,
                      style: const TextStyle(fontSize: 16),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (subtitleChips.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 4, children: subtitleChips),
                  ],
                  if (todo.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    TodoTagWrap(tags: todo.tags),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: textSecondary.withValues(alpha: 0.6),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        // Nhãn dài / chữ lớn: cắt "…" thay vì tràn khỏi hàng chip.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }
}
