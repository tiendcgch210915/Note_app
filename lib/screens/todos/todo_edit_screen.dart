import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../widgets/section_header.dart';
import '../../widgets/repeat_picker_sheet.dart';

/// Màn hình "chỉnh sửa" — chỉnh tất cả properties của todo:
/// meta (ngày làm, hạn chót, ước lượng), classify Eisenhower, frog, tags,
/// linked notes. KHÔNG có subtask list (subtask quản lý ở TodoDetailScreen).
class TodoEditScreen extends StatefulWidget {
  final String todoId;
  const TodoEditScreen({super.key, required this.todoId});

  @override
  State<TodoEditScreen> createState() => _TodoEditScreenState();
}

class _TodoEditScreenState extends State<TodoEditScreen> {
  TodoWithRelations? _detail;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail = await TodosRepository.instance.getDetail(widget.todoId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // EXP 2 — Classify Eisenhower
  Future<void> _classify(bool? important, bool? urgent) async {
    try {
      final newTodo = await TodosRepository.instance.classify(
        widget.todoId,
        important: important,
        urgent: urgent,
      );
      if (!mounted) return;
      setState(() {
        _detail = TodoWithRelations(
          todo: newTodo,
          tags: _detail!.tags,
          subtasks: _detail!.subtasks,
          linkedNotes: _detail!.linkedNotes,
        );
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  // EXP 3 — Move to Day
  Future<void> _moveToDay() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Đổi ngày'),
              onTap: () => Navigator.of(ctx).pop('pick'),
            ),
            if (todo.scheduledDate != null)
              ListTile(
                leading: const Icon(Icons.event_busy),
                title: const Text('Bỏ ngày (floating)'),
                onTap: () => Navigator.of(ctx).pop('clear'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'clear') {
      _doMove(null);
    } else if (action == 'pick') {
      final picked = await showDatePicker(
        context: context,
        initialDate: todo.scheduledDate ?? DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null && mounted) _doMove(picked);
    }
  }

  Future<void> _doMove(DateTime? date) async {
    try {
      final newTodo = await TodosRepository.instance.moveToDay(widget.todoId, date);
      if (!mounted) return;
      setState(() {
        _detail = TodoWithRelations(
          todo: newTodo,
          tags: _detail!.tags,
          subtasks: _detail!.subtasks,
          linkedNotes: _detail!.linkedNotes,
        );
      });
    } on ApiException catch (e) {
      if (e.code == 'daily_limit_reached' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ngày đích đã đủ 6 việc')),
        );
      } else if (mounted) {
        _showError(e.vnMessage);
      }
    }
  }

  Future<void> _toggleFrog() async {
    final todo = _detail?.todo;
    if (todo == null) return;
    try {
      final newTodo = todo.isFrog
          ? await TodosRepository.instance.unmarkFrog(widget.todoId)
          : await TodosRepository.instance.markFrog(
              widget.todoId,
              todo.scheduledDate ?? DateTime.now(),
            );
      if (!mounted) return;
      setState(() {
        _detail = TodoWithRelations(
          todo: newTodo,
          tags: _detail!.tags,
          subtasks: _detail!.subtasks,
          linkedNotes: _detail!.linkedNotes,
        );
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Không tìm thấy todo')),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final todo = _detail!.todo;
    final qInfo = QuadrantUtils.info(
      QuadrantUtils.from(important: todo.isImportant, urgent: todo.isUrgent),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                todo.title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            if (todo.description != null && todo.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  todo.description!,
                  style: TextStyle(fontSize: 15, color: secondary, height: 1.4),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _badge(todo.status.label, AppColors.primary),
                  _badge(qInfo.label, qInfo.color),
                  if (todo.isFrog) _badge('🐸 Frog', AppColors.frog),
                  if (todo.estimatedMinutes != null)
                    _badge('${todo.estimatedMinutes} phút', secondary),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _MetaList(
              todo: todo,
              tags: _detail!.tags,
              secondary: secondary,
              onMoveToDay: _moveToDay,
              onToggleFrog: _toggleFrog,
            ),
            const SectionHeader(label: 'Phân loại Eisenhower'),
            _ClassifyCard(todo: todo, qInfo: qInfo, onClassify: _classify),
            const SectionHeader(label: 'Note liên quan'),
            if (_detail!.linkedNotes.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('Chưa có note liên kết', style: TextStyle(color: secondary)),
              )
            else
              ..._detail!.linkedNotes.map((n) => ListTile(
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mở note (TODO)')),
                      );
                    },
                  )),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _MetaList extends StatelessWidget {
  final Todo todo;
  final List tags;
  final Color secondary;
  final VoidCallback onMoveToDay;
  final VoidCallback onToggleFrog;
  const _MetaList({
    required this.todo,
    required this.tags,
    required this.secondary,
    required this.onMoveToDay,
    required this.onToggleFrog,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.calendar_today, size: 20),
          title: const Text('Ngày làm'),
          subtitle: Text(todo.scheduledDate == null
              ? 'Chưa chọn (floating)'
              : AppDateUtils.formatDate(todo.scheduledDate!)),
          trailing: IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: onMoveToDay,
          ),
        ),
        if (todo.dueAt != null)
          ListTile(
            leading: const Icon(Icons.access_time, size: 20),
            title: Text(
                'Hạn chót: ${AppDateUtils.formatDate(todo.dueAt!)} ${AppDateUtils.formatTime(todo.dueAt!)}'),
          ),
        ListTile(
          leading: Icon(Icons.eco, size: 20, color: todo.isFrog ? AppColors.frog : null),
          title: const Text('Đánh dấu Frog'),
          subtitle: Text(todo.isFrog ? 'Đang là Frog hôm nay' : 'Tắt'),
          trailing: Switch(value: todo.isFrog, onChanged: (_) => onToggleFrog()),
        ),
        if (todo.isRecurring)
          ListTile(
            leading: Icon(Icons.repeat, size: 20,
                color: AppColors.primary),
            title: const Text('Lặp lại'),
            subtitle: Text(todo.isRecurrenceTemplate
                ? todo.recurrenceLabel
                : 'Instance của lịch lặp'),
          ),
        if (tags.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.local_offer_outlined, size: 20),
            title: Wrap(
              spacing: 6,
              children: tags.map<Widget>((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tag.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(tag.name,
                      style: TextStyle(
                          fontSize: 11, color: tag.color, fontWeight: FontWeight.w600)),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

/// EXP 2 — 5 chip Q1-Q4 + Unclassified.
class _ClassifyCard extends StatelessWidget {
  final Todo todo;
  final QuadrantInfo qInfo;
  final void Function(bool?, bool?) onClassify;
  const _ClassifyCard(
      {required this.todo, required this.qInfo, required this.onClassify});

  bool _isSelected(Quadrant q) {
    final current =
        QuadrantUtils.from(important: todo.isImportant, urgent: todo.isUrgent);
    return current == q;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('Q1 Khẩn+Quan trọng', Quadrant.q1, () => onClassify(true, true)),
                _chip('Q2 Quan trọng', Quadrant.q2, () => onClassify(true, false)),
                _chip('Q3 Khẩn', Quadrant.q3, () => onClassify(false, true)),
                _chip('Q4 Bỏ qua', Quadrant.q4, () => onClassify(false, false)),
                _chip('Chưa phân loại', Quadrant.unclassified,
                    () => onClassify(null, null)),
              ],
            ),
            const SizedBox(height: 8),
            Text('→ ${qInfo.action}',
                style: TextStyle(
                    fontSize: 12, color: qInfo.color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Quadrant q, VoidCallback onTap) {
    final info = QuadrantUtils.info(q);
    final selected = _isSelected(q);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? info.color.withValues(alpha: 0.18) : Colors.transparent,
          border: Border.all(color: info.color, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, color: info.color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
