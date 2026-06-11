import 'package:flutter/material.dart';
import '../../models/dashboard.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../widgets/empty_state.dart';
import '../todos/todo_detail_screen.dart';

/// EXP 10 — Hiển thị full list todos của 1 quadrant khi tap ô Dashboard.
class QuadrantTodosScreen extends StatelessWidget {
  final Quadrant quadrant;
  final List<DashboardEisenhowerTodo> todos;

  const QuadrantTodosScreen({
    super.key,
    required this.quadrant,
    required this.todos,
  });

  @override
  Widget build(BuildContext context) {
    final info = QuadrantUtils.info(quadrant);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(info.label),
        backgroundColor: Color.alphaBlend(
          info.color.withValues(alpha: 0.12),
          background,
        ),
      ),
      body: todos.isEmpty
          ? EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Không có việc nào trong ${info.label}',
              subtitle: 'Action gợi ý: ${info.action}',
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  color: Color.alphaBlend(
                    info.color.withValues(alpha: isDark ? 0.14 : 0.08),
                    background,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 32,
                        decoration: BoxDecoration(
                          color: info.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${todos.length} việc',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Gợi ý: ${info.action}',
                              style: TextStyle(
                                fontSize: 12,
                                color: info.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: todos.length,
                    itemBuilder: (ctx, i) {
                      final t = todos[i];
                      return _DashboardTodoTile(
                        todo: t,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TodoDetailScreen(todoId: t.id),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      backgroundColor: background,
    );
  }
}

class _DashboardTodoTile extends StatelessWidget {
  final DashboardEisenhowerTodo todo;
  final VoidCallback onTap;

  const _DashboardTodoTile({required this.todo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return ListTile(
      onTap: todo.id.isEmpty ? null : onTap,
      leading: Icon(
        todo.isFrog ? Icons.eco : Icons.radio_button_unchecked,
        color: todo.isFrog ? AppColors.frog : secondary,
      ),
      title: Text(
        todo.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _subtitle(todo),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: secondary),
      ),
      trailing: todo.id.isEmpty
          ? null
          : Icon(Icons.chevron_right, color: secondary),
    );
  }

  String _subtitle(DashboardEisenhowerTodo todo) {
    final parts = <String>[_statusLabel(todo.status)];
    if (todo.scheduledDate != null) {
      parts.add(AppDateUtils.formatDate(todo.scheduledDate!));
    }
    if (todo.isFrog) parts.add('Frog');
    return parts.join(' · ');
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'Đang làm';
      case 'done':
        return 'Hoàn thành';
      case 'archived':
        return 'Lưu trữ';
      default:
        return 'Mở';
    }
  }
}
