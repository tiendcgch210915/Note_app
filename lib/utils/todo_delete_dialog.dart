import 'package:flutter/material.dart';

import '../models/recurring_todo_delete_scope.dart';
import '../models/todo.dart';
import '../theme/app_colors.dart';

Future<RecurringTodoDeleteScope?> showTodoDeleteScopeDialog(
  BuildContext context,
  Todo todo,
) {
  if (!todo.isRecurring) {
    return showDialog<RecurringTodoDeleteScope>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa việc?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(RecurringTodoDeleteScope.thisOccurrence),
            child: const Text('Xóa', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  return showDialog<RecurringTodoDeleteScope>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Xóa lịch lặp?'),
      content: const Text('Chọn phạm vi xóa:'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Hủy'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(RecurringTodoDeleteScope.thisOccurrence),
          child: const Text('Lần này thôi'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(RecurringTodoDeleteScope.thisAndFuture),
          child: const Text('Lần này và sau'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(RecurringTodoDeleteScope.all),
          child: const Text(
            'Tất cả',
            style: TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    ),
  );
}
