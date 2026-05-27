import 'package:flutter/material.dart';
import '../models/todo.dart';

/// EXP 1 — Habit Stacking popup chain.
///
/// Sau khi F-T7 complete trả `triggered_todos[]` (depth 1, các todo có
/// `trigger_after_todo_id` = todo vừa hoàn thành), hiển thị popup cho user
/// mở từng item theo chuỗi.
Future<void> showHabitStackingDialog(
  BuildContext context,
  List<Todo> triggered,
  void Function(Todo) onOpen,
) async {
  if (triggered.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hoàn thành ✓'), duration: Duration(seconds: 1)),
    );
    return;
  }

  if (triggered.length == 1) {
    final next = triggered.first;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bước tiếp theo:'),
        content: Text(next.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('later'),
            child: const Text('Để sau'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('open'),
            child: const Text('Mở'),
          ),
        ],
      ),
    );
    if (action == 'open') onOpen(next);
    return;
  }

  // Multi-item chain
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text('Còn ${triggered.length} bước tiếp theo:'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: triggered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = triggered[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: TextButton(
                  child: const Text('Mở'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    onOpen(t);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      );
    },
  );
}
