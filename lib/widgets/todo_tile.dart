import 'package:flutter/material.dart';
import '../models/todo.dart';
import '../theme/app_colors.dart';
import '../utils/date_utils.dart';

/// 1 hàng todo theo style Microsoft To Do.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;
    final done = todo.isDone;

    final subtitleChips = <Widget>[];
    if (todo.isFrog) {
      subtitleChips.add(_chip(Icons.eco, 'Frog', AppColors.frog));
    }
    if (todo.isImportant == true) {
      subtitleChips.add(_chip(Icons.star, 'Quan trọng', Colors.amber));
    }
    if (todo.dueAt != null) {
      subtitleChips.add(_chip(
        Icons.calendar_today,
        AppDateUtils.formatRelative(todo.dueAt!),
        textSecondary,
      ));
    }
    if (todo.estimatedMinutes != null) {
      subtitleChips.add(_chip(
        Icons.hourglass_empty,
        '${todo.estimatedMinutes}p',
        textSecondary,
      ));
    }
    if (todo.isRecurring) {
      subtitleChips.add(_chip(
        Icons.repeat,
        todo.isRecurrenceTemplate
            ? todo.recurrenceLabel
            : 'Lặp lại',
        AppColors.primary,
      ));
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 8 : 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: onToggleDone,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 24,
                  color: done ? AppColors.primary : textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todo.title,
                    style: TextStyle(
                      fontSize: 16,
                      color: done ? textSecondary : textPrimary,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitleChips.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: subtitleChips,
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: textSecondary, size: 20),
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
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
