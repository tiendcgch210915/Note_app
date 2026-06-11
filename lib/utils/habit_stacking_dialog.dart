import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../theme/app_colors.dart';
import '../widgets/duration_picker_sheet.dart';
import 'date_utils.dart';

/// Shows next-todo suggestions returned by complete todo / local offline lookup.
Future<void> showHabitStackingDialog(
  BuildContext context,
  List<Todo> triggered,
  void Function(Todo) onOpen,
) async {
  if (triggered.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hoàn thành ✓'),
        duration: Duration(seconds: 1),
      ),
    );
    return;
  }

  final selected = await showModalBottomSheet<Todo>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.account_tree_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nên làm tiếp',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${triggered.length} việc được gợi ý sau bước vừa hoàn thành',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: triggered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final todo = triggered[index];
                  return ListTile(
                    leading: Icon(
                      todo.isFrog
                          ? Icons.flag_circle_outlined
                          : Icons.radio_button_unchecked,
                      color: todo.isFrog ? AppColors.frog : null,
                    ),
                    title: Text(
                      todo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_subtitle(todo)),
                    trailing: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(todo),
                      child: const Text('Mở'),
                    ),
                    onTap: () => Navigator.of(ctx).pop(todo),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Bỏ qua'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (selected != null) onOpen(selected);
}

String _subtitle(Todo todo) {
  final parts = <String>[todo.status.label];
  if (todo.estimatedMinutes != null) {
    parts.add(formatDurationMinutesShort(todo.estimatedMinutes!));
  }
  if (todo.scheduledDate != null) {
    parts.add(AppDateUtils.formatDate(todo.scheduledDate!));
  }
  return parts.join(' · ');
}
