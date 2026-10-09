import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/todos_repository.dart';
import '../../models/habit.dart';
import '../../models/tag.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_snack.dart';
import '../../utils/date_utils.dart';
import '../../utils/json_utils.dart';
import '../../utils/quadrant_utils.dart';
import '../../utils/todo_trigger_picker.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/duration_picker_sheet.dart';
import '../../widgets/habit_selector_sheet.dart';
import '../../widgets/repeat_picker_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tag_chip.dart';
import '../../widgets/todo_flag_button.dart';
import '../../widgets/todo_tag_selector_sheet.dart';

/// Form tạo todo mới. Submit gọi F-T1 POST /todos.
class TodoCreateScreen extends StatefulWidget {
  /// Optional parent_id để tạo subtask trực tiếp từ TodoDetailScreen.
  final String? parentId;
  final DateTime? initialScheduledDate;

  const TodoCreateScreen({super.key, this.parentId, this.initialScheduledDate});

  @override
  State<TodoCreateScreen> createState() => _TodoCreateScreenState();
}

class _TodoCreateScreenState extends State<TodoCreateScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  late DateTime _scheduledDate;
  String? _time;
  int? _estimated;
  bool _frog = false;
  bool _important = false;
  bool _urgent = false;
  List<Tag> _tags = [];
  Habit? _habit;
  String? _triggerTodoId;
  String? _triggerTodoTitle;
  RepeatSettings _repeat = RepeatSettings.none;
  bool _saving = false;
  String? _titleError;

  bool get _isSubtask => widget.parentId != null;

  @override
  void initState() {
    super.initState();
    _scheduledDate = AppDateUtils.dateOnly(
      widget.initialScheduledDate ?? DateTime.now(),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      AppHaptics.heavy();
      setState(() => _titleError = 'Vui lòng nhập tiêu đề');
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
              if (_time != null) 'time': _time,
              'due_at': formatEndOfDayIso(_scheduledDate),
              'is_frog': _frog,
              if (_frog) 'frog_date': formatDateOnly(_scheduledDate),
              'is_important': _frog || _important,
              'is_urgent': _frog || _urgent,
              if (_estimated != null) 'estimated_minutes': _estimated,
              if (_triggerTodoId != null)
                'trigger_after_todo_id': _triggerTodoId,
              if (_habit != null) 'habit_id': _habit!.id,
              if (_tags.isNotEmpty)
                'tag_ids': _tags.map((tag) => tag.id).toList(),
              if (_repeat.hasRepeat) ...{
                'recurrence_type': _repeat.type,
                'recurrence_interval': _repeat.interval,
                if (_repeat.daysOfWeek != null)
                  'recurrence_days_of_week': _repeat.daysOfWeek,
                if (_repeat.endDate != null)
                  'recurrence_end_date': _repeat.endDate,
              },
            };
      final result = await TodosRepository.instance.createLocalFirst(body);
      if (!mounted) return;
      AppHaptics.medium();
      Navigator.of(context).pop(!_isSubtask ? true : result.todo);
      showAppSnack(context, 'Đã lưu');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'daily_limit_reached') {
        _showDailyLimitDialog();
      } else if (e.code == 'invalid_trigger') {
        setState(() {
          _triggerTodoId = null;
          _triggerTodoTitle = null;
        });
        showAppSnack(
          context,
          'Việc trigger không còn hợp lệ. Vui lòng chọn lại.',
          isError: true,
        );
      } else {
        showAppSnack(context, e.vnMessage, isError: true);
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
    final primary = context.appPrimary;
    final qInfo = QuadrantUtils.info(
      QuadrantUtils.from(
        important: _frog || _important,
        urgent: _frog || _urgent,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Đóng',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(!_isSubtask ? 'Việc mới' : 'Việc con mới'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: SizedBox(
              width: 36,
              child: Center(
                child: _saving
                    ? const AppSpinner(radius: 9, centered: false)
                    : const Text(
                        'Lưu',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: AppSurface(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _title,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_titleError != null) {
                        setState(() => _titleError = null);
                      }
                    },
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Bạn cần làm gì?',
                      errorText: _titleError,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  if (!_isSubtask) ...[
                    Divider(height: 1, color: context.appDivider),
                    TextField(
                      controller: _desc,
                      maxLines: 3,
                      minLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Mô tả thêm...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!_isSubtask) ...[
            AppListSection(
              dividerIndent: AppListSection.iconIndent,
              children: [
                AppListTile(
                  icon: Icons.calendar_today_rounded,
                  title: 'Ngày làm',
                  value: AppDateUtils.formatDate(_scheduledDate),
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
                AppListTile(
                  icon: Icons.schedule_rounded,
                  iconColor: _time == null ? AppColors.tagSlate : primary,
                  title: 'Giờ nhắc',
                  value: _time ?? 'Không đặt giờ',
                  trailing: _time == null
                      ? null
                      : AppClearButton(
                          tooltip: 'Bỏ giờ nhắc',
                          onTap: () => setState(() => _time = null),
                        ),
                  showChevron: _time == null,
                  onTap: _pickTime,
                ),
                AppListTile(
                  icon: Icons.repeat_rounded,
                  iconColor: _repeat.hasRepeat ? primary : AppColors.tagSlate,
                  title: 'Lặp lại',
                  value: _repeat.label,
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
                AppListTile(
                  icon: Icons.hourglass_empty_rounded,
                  iconColor: AppColors.tagAmber,
                  title: 'Ước lượng',
                  value: _estimated == null
                      ? 'Chưa chọn'
                      : formatDurationMinutes(_estimated!),
                  onTap: _pickEstimate,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TodoFlagButton(
                      selected: _frog,
                      selectedColor: AppColors.frog,
                      label: 'Frog',
                      emoji: '🐸',
                      onTap: () => setState(() {
                        _frog = !_frog;
                        if (_frog) {
                          _important = true;
                          _urgent = true;
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TodoFlagButton(
                      selected: _frog || _important,
                      selectedColor: const Color(0xFFB91C1C),
                      label: 'Quan trọng',
                      icon: Icons.star_rounded,
                      onTap: _frog
                          ? null
                          : () => setState(() => _important = !_important),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TodoFlagButton(
                      selected: _frog || _urgent,
                      selectedColor: AppColors.warning,
                      selectedForeground: AppColors.textPrimary,
                      label: 'Khẩn cấp',
                      icon: Icons.bolt_rounded,
                      onTap: _frog
                          ? null
                          : () => setState(() => _urgent = !_urgent),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: AppMotion.normal,
                  curve: AppMotion.curve,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: ShapeDecoration(
                    color: qInfo.color.withValues(alpha: 0.15),
                    shape: AppShape.pill,
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
            const SectionHeader(label: 'Tags'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_tags.isNotEmpty)
                    TodoTagWrap(
                      tags: _tags,
                      compact: false,
                      onDeleted: (tag) => setState(
                        () => _tags = _tags
                            .where((item) => item.id != tag.id)
                            .toList(),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.local_offer_outlined, size: 16),
                    label: Text(_tags.isEmpty ? 'Chọn tag' : 'Sửa tag'),
                    onPressed: _pickTags,
                  ),
                ],
              ),
            ),
            AppListSection(
              dividerIndent: AppListSection.iconIndent,
              children: [
                AppListTile(
                  icon: _habit?.icon ?? Icons.flag_rounded,
                  iconColor: _habit?.color ?? AppColors.tagSlate,
                  title: 'Habit liên kết',
                  value: _habit?.title ?? 'Không liên kết',
                  trailing: _habit == null
                      ? null
                      : AppClearButton(
                          tooltip: 'Bỏ liên kết',
                          onTap: () => setState(() => _habit = null),
                        ),
                  showChevron: _habit == null,
                  onTap: _pickHabit,
                ),
                AppListTile(
                  icon: Icons.account_tree_rounded,
                  iconColor: AppColors.tagCyan,
                  title: 'Làm sau khi hoàn thành...',
                  value: _triggerTodoId == null
                      ? 'Chưa chọn'
                      : _triggerTodoTitle ?? 'Đã chọn việc trigger',
                  trailing: _triggerTodoId == null
                      ? null
                      : AppClearButton(
                          tooltip: 'Bỏ việc trigger',
                          onTap: () => setState(() {
                            _triggerTodoId = null;
                            _triggerTodoTitle = null;
                          }),
                        ),
                  showChevron: _triggerTodoId == null,
                  onTap: _pickTriggerTodo,
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _pickEstimate() async {
    const customEstimate = -1;
    final selected = await showAppSheet<int>(
      context: context,
      builder: (ctx) => AppSheetScaffold(
        title: 'Ước lượng thời gian',
        child: AppListSection(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          dividerIndent: AppListSection.iconIndent,
          children: [
            ...[15, 25, 45, 60].map((m) {
              return AppListTile(
                icon: Icons.hourglass_empty_rounded,
                iconColor: AppColors.tagAmber,
                title: '$m phút',
                showChevron: false,
                trailing: _estimated == m
                    ? Icon(Icons.check_rounded, color: ctx.appPrimary, size: 22)
                    : null,
                onTap: () => Navigator.of(ctx).pop(m),
              );
            }),
            AppListTile(
              icon: Icons.tune_rounded,
              iconColor: AppColors.tagPurple,
              title: 'Tùy chỉnh',
              subtitle: _estimated == null
                  ? null
                  : 'Hiện tại: ${formatDurationMinutes(_estimated!)}',
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

    final custom = await showAppSheet<int>(
      context: context,
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time == null
          ? TimeOfDay.now()
          : _timeOfDayFromString(_time!),
    );
    if (picked == null || !mounted) return;
    setState(() => _time = _formatTimeOfDay(picked));
  }

  TimeOfDay _timeOfDayFromString(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTimeOfDay(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickTags() async {
    final selected = await showTodoTagSelectorSheet(
      context,
      initialTags: _tags,
    );
    if (selected == null || !mounted) return;
    setState(() => _tags = selected);
  }

  Future<void> _pickHabit() async {
    final selected = await showHabitSelectorSheet(
      context,
      selectedHabitId: _habit?.id,
    );
    if (selected == null || !mounted) return;
    setState(() => _habit = selected.habit);
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
