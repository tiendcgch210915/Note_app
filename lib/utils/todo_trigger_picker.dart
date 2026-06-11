import 'package:flutter/material.dart';

import '../data/api_exception.dart';
import '../data/todos_repository.dart';
import '../models/todo.dart';
import '../theme/app_colors.dart';
import '../widgets/duration_picker_sheet.dart';
import 'date_utils.dart';

Future<Todo?> showTodoTriggerPicker(
  BuildContext context, {
  String? excludeTodoId,
}) async {
  try {
    final candidates = await TodosRepository.instance.listTriggerCandidates(
      excludeId: excludeTodoId,
    );
    if (!context.mounted) return null;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có việc phù hợp để chọn')),
      );
      return null;
    }

    return showModalBottomSheet<Todo>(
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.account_tree_outlined, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Làm sau khi hoàn thành...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final todo = candidates[index];
                    return ListTile(
                      leading: Icon(
                        Icons.radio_button_unchecked,
                        color: _statusColor(todo),
                      ),
                      title: Text(
                        todo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_candidateSubtitle(todo)),
                      onTap: () => Navigator.of(ctx).pop(todo),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.vnMessage), backgroundColor: AppColors.danger),
    );
    return null;
  }
}

String _candidateSubtitle(Todo todo) {
  final parts = <String>[todo.status.label];
  if (todo.estimatedMinutes != null) {
    parts.add(formatDurationMinutesShort(todo.estimatedMinutes!));
  }
  if (todo.scheduledDate != null) {
    parts.add(AppDateUtils.formatDate(todo.scheduledDate!));
  }
  return parts.join(' · ');
}

Color _statusColor(Todo todo) {
  if (todo.status == TodoStatus.inProgress) return AppColors.primary;
  if (todo.isFrog) return AppColors.frog;
  return AppColors.textSecondary;
}
