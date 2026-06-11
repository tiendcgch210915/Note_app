import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../utils/json_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../utils/todo_trigger_picker.dart';
import '../../widgets/duration_picker_sheet.dart';
import '../../widgets/repeat_picker_sheet.dart';
import '../../widgets/todo_flag_button.dart';

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
  DateTime _scheduledDate = AppDateUtils.dateOnly(DateTime.now());
  int? _estimated;
  bool _frog = false;
  bool _important = false;
  bool _urgent = false;
  final Set<String> _tagNames = {};
  String? _triggerTodoId;
  String? _triggerTodoTitle;
  RepeatSettings _repeat = RepeatSettings.none;
  bool _saving = false;

  bool get _isSubtask => widget.parentId != null;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tiêu đề')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = _isSubtask
          ? <String, dynamic>{
              'title': _title.text.trim(),
              'parent_id': widget.parentId,
            }
          : <String, dynamic>{
              'title': _title.text.trim(),
              if (_desc.text.trim().isNotEmpty)
                'description': _desc.text.trim(),
              'scheduled_date': formatDateOnly(_scheduledDate),
              'is_frog': _frog,
              if (_frog) 'frog_date': formatDateOnly(_scheduledDate),
              'is_important': _important,
              'is_urgent': _urgent,
              if (_estimated != null) 'estimated_minutes': _estimated,
              if (_triggerTodoId != null)
                'trigger_after_todo_id': _triggerTodoId,
              if (_tagNames.isNotEmpty) 'tags': _tagNames.toList(),
              if (_repeat.hasRepeat) ...{
                'recurrence_type': _repeat.type,
                'recurrence_interval': _repeat.interval,
                if (_repeat.daysOfWeek != null)
                  'recurrence_days_of_week': _repeat.daysOfWeek,
                if (_repeat.endDate != null)
                  'recurrence_end_date': _repeat.endDate,
              },
            };
      final result = !_isSubtask
          ? await TodosRepository.instance.create(body)
          : await TodosRepository.instance.createLocalFirst(body);
      if (!mounted) return;
      Navigator.of(context).pop(!_isSubtask ? true : result.todo);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã lưu')));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'daily_limit_reached') {
        _showDailyLimitDialog();
      } else if (e.code == 'invalid_trigger') {
        setState(() {
          _triggerTodoId = null;
          _triggerTodoTitle = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Việc trigger không còn hợp lệ. Vui lòng chọn lại.'),
            backgroundColor: AppColors.danger,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.vnMessage),
            backgroundColor: AppColors.danger,
          ),
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
          'Ngày ${AppDateUtils.formatDate(_scheduledDate)} đã có 6 việc. Chọn ngày khác?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Đổi ngày'),
          ),
        ],
      ),
    );
    if (pickAnother != true || !mounted) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _scheduledDate = AppDateUtils.dateOnly(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final qInfo = QuadrantUtils.info(
      QuadrantUtils.from(important: _important, urgent: _urgent),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(!_isSubtask ? 'Việc mới' : 'Việc con mới'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Lưu',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
          if (!_isSubtask) ...[
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
              subtitle: Text(AppDateUtils.formatDate(_scheduledDate)),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _scheduledDate,
                  firstDate: now.subtract(const Duration(days: 30)),
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(
                    () => _scheduledDate = AppDateUtils.dateOnly(picked),
                  );
                }
              },
            ),
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
              leading: const Icon(Icons.hourglass_empty, size: 20),
              title: const Text('Ước lượng'),
              subtitle: Text(
                _estimated == null
                    ? 'Chưa chọn'
                    : formatDurationMinutes(_estimated!),
              ),
              onTap: _pickEstimate,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TodoFlagButton(
                      selected: _frog,
                      selectedColor: AppColors.frog,
                      label: 'Frog',
                      emoji: '🐸',
                      onTap: () => setState(() => _frog = !_frog),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TodoFlagButton(
                      selected: _important,
                      selectedColor: const Color(0xFFB91C1C),
                      label: 'Quan trọng',
                      icon: Icons.star_rounded,
                      onTap: () => setState(() => _important = !_important),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TodoFlagButton(
                      selected: _urgent,
                      selectedColor: AppColors.warning,
                      selectedForeground: AppColors.textPrimary,
                      label: 'Khẩn cấp',
                      icon: Icons.bolt_rounded,
                      onTap: () => setState(() => _urgent = !_urgent),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: qInfo.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${qInfo.label} → ${qInfo.action}',
                    style: TextStyle(
                      fontSize: 12,
                      color: qInfo.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Tags',
                style: TextStyle(
                  fontSize: 13,
                  color: secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._tagNames.map(
                    (name) => Chip(
                      label: Text(name),
                      onDeleted: () => setState(() => _tagNames.remove(name)),
                    ),
                  ),
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
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('Làm sau khi hoàn thành...'),
              subtitle: Text(
                _triggerTodoId == null
                    ? 'Chưa chọn'
                    : _triggerTodoTitle ?? 'Đã chọn việc trigger',
              ),
              trailing: _triggerTodoId == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _triggerTodoId = null;
                        _triggerTodoTitle = null;
                      }),
                    ),
              onTap: _pickTriggerTodo,
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _pickEstimate() async {
    const customEstimate = -1;
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...[15, 25, 45, 60].map((m) {
              return ListTile(
                leading: const Icon(Icons.hourglass_empty),
                title: Text('$m phút'),
                onTap: () => Navigator.of(ctx).pop(m),
              );
            }),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Tùy chỉnh'),
              subtitle: _estimated == null
                  ? null
                  : Text('Hiện tại: ${formatDurationMinutes(_estimated!)}'),
              onTap: () => Navigator.of(ctx).pop(customEstimate),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected != customEstimate) {
      setState(() => _estimated = selected);
      return;
    }

    final custom = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DurationPickerSheet(
        initialMinutes: _estimated ?? 25,
        title: 'Bạn muốn ước lượng bao nhiêu thời gian cho việc này?',
        actionLabel: 'Lưu',
        actionIcon: Icons.check_rounded,
      ),
    );
    if (custom == null || !mounted) return;
    setState(() => _estimated = custom);
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
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
    final picked = await showTodoTriggerPicker(context);
    if (picked == null || !mounted) return;
    setState(() {
      _triggerTodoId = picked.id;
      _triggerTodoTitle = picked.title;
    });
  }
}
