import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/json_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../widgets/repeat_picker_sheet.dart';

/// Form tạo todo mới. Submit gọi F-T1 POST /todos.
class TodoCreateScreen extends StatefulWidget {
  /// Optional parent_id để tạo subtask trực tiếp từ TodoDetailScreen.
  final String? parentId;
  const TodoCreateScreen({super.key, this.parentId});

  @override
  State<TodoCreateScreen> createState() => _TodoCreateScreenState();
}

class _TodoCreateScreenState extends State<TodoCreateScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  DateTime? _scheduledDate;
  DateTime? _dueAt;
  int? _estimated;
  bool _frog = false;
  bool _important = false;
  bool _urgent = false;
  final Set<String> _tagNames = {};
  String? _triggerTodoId;
  RepeatSettings _repeat = RepeatSettings.none;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tiêu đề')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'title': _title.text.trim(),
        if (_desc.text.trim().isNotEmpty) 'description': _desc.text.trim(),
        if (widget.parentId != null) 'parent_id': widget.parentId,
        if (_scheduledDate != null) 'scheduled_date': formatDateOnly(_scheduledDate!),
        'is_frog': _frog,
        if (_frog && _scheduledDate != null) 'frog_date': formatDateOnly(_scheduledDate!),
        'is_important': _important,
        'is_urgent': _urgent,
        if (_estimated != null) 'estimated_minutes': _estimated,
        if (_dueAt != null) 'due_at': formatIsoDate(_dueAt!),
        if (_triggerTodoId != null) 'trigger_after_todo_id': _triggerTodoId,
        if (_tagNames.isNotEmpty) 'tags': _tagNames.toList(),
        // Recurrence — only for top-level todos
        if (widget.parentId == null && _repeat.hasRepeat) ...{
          'recurrence_type': _repeat.type,
          'recurrence_interval': _repeat.interval,
          if (_repeat.daysOfWeek != null)
            'recurrence_days_of_week': _repeat.daysOfWeek,
          if (_repeat.endDate != null) 'recurrence_end_date': _repeat.endDate,
        },
      };
      await TodosRepository.instance.create(body);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'daily_limit_reached') {
        _showDailyLimitDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.vnMessage), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showDailyLimitDialog() async {
    final pickAnother = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đã đủ 6 việc'),
        content: Text(
          _scheduledDate == null
              ? 'Ngày này đã có 6 việc hôm nay. Chọn ngày khác?'
              : 'Ngày ${AppDateUtils.formatDate(_scheduledDate!)} đã có 6 việc. Chọn ngày khác?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Đổi ngày')),
        ],
      ),
    );
    if (pickAnother != true || !mounted) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _scheduledDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final qInfo = QuadrantUtils.info(
      QuadrantUtils.from(important: _important, urgent: _urgent),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.parentId == null ? 'Việc mới' : 'Việc con mới'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Lưu', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _title,
              autofocus: true,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Bạn cần làm gì?',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Mô tả thêm...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.calendar_today, size: 20),
            title: const Text('Ngày làm'),
            subtitle: Text(_scheduledDate == null ? 'Chưa chọn' : AppDateUtils.formatDate(_scheduledDate!)),
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _scheduledDate ?? now,
                firstDate: now.subtract(const Duration(days: 30)),
                lastDate: now.add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _scheduledDate = picked);
            },
          ),
          // Repeat — top-level todos only
          if (widget.parentId == null)
            ListTile(
              leading: Icon(
                Icons.repeat,
                size: 20,
                color: _repeat.hasRepeat ? AppColors.primary : null,
              ),
              title: const Text('Lặp lại'),
              subtitle: Text(_repeat.label),
              onTap: () async {
                final result = await showRepeatPicker(
                  context,
                  initial: _repeat,
                );
                if (result != null && mounted) {
                  setState(() => _repeat = result);
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.access_time, size: 20),
            title: const Text('Hạn chót'),
            subtitle: Text(_dueAt == null
                ? 'Chưa chọn'
                : '${AppDateUtils.formatDate(_dueAt!)} ${AppDateUtils.formatTime(_dueAt!)}'),
            onTap: _pickDueDateTime,
          ),
          ListTile(
            leading: const Icon(Icons.hourglass_empty, size: 20),
            title: const Text('Ước lượng'),
            subtitle: Text(_estimated == null ? 'Chưa chọn' : '$_estimated phút'),
            onTap: _pickEstimate,
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _frog,
            onChanged: (v) => setState(() => _frog = v),
            secondary: const Icon(Icons.eco, color: AppColors.frog),
            title: const Text('Đánh dấu là Frog'),
            subtitle: const Text('Việc quan trọng nhất hôm nay'),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _important,
            onChanged: (v) => setState(() => _important = v),
            title: const Text('Quan trọng'),
          ),
          SwitchListTile(
            value: _urgent,
            onChanged: (v) => setState(() => _urgent = v),
            title: const Text('Khẩn cấp'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: qInfo.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${qInfo.label} → ${qInfo.action}',
                  style: TextStyle(fontSize: 12, color: qInfo.color, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('Tags', style: TextStyle(fontSize: 13, color: secondary, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._tagNames.map((name) => Chip(
                      label: Text(name),
                      onDeleted: () => setState(() => _tagNames.remove(name)),
                    )),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Thêm tag'),
                  onPressed: _addTag,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Trigger sau khi xong việc khác'),
            subtitle: Text(_triggerTodoId == null ? 'Chưa chọn' : 'Đã chọn việc trigger'),
            trailing: _triggerTodoId == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _triggerTodoId = null),
                  ),
            onTap: _pickTriggerTodo,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _pickDueDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt ?? now),
    );
    if (!mounted || time == null) return;
    setState(() {
      _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _pickEstimate() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [15, 25, 45, 60, 90].map((m) {
            return ListTile(
              title: Text('$m phút'),
              onTap: () {
                setState(() => _estimated = m);
                Navigator.of(ctx).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _addTag() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm tag'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tên tag (1-64 ký tự)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _tagNames.add(name));
  }

  Future<void> _pickTriggerTodo() async {
    try {
      final resp = await TodosRepository.instance.list(parentId: 'null', limit: 30);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: resp.items
                .map((t) => ListTile(
                      title: Text(t.title),
                      subtitle: t.scheduledDate == null
                          ? null
                          : Text(AppDateUtils.formatDate(t.scheduledDate!)),
                      onTap: () {
                        setState(() => _triggerTodoId = t.id);
                        Navigator.of(ctx).pop();
                      },
                    ))
                .toList(),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.vnMessage)));
    }
  }
}
