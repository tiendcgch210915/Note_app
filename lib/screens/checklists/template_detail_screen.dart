import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/checklist_category.dart';
import '../../models/template.dart';
import '../../models/template_item.dart';
import '../../theme/app_colors.dart';
import '../../utils/checklist_step_text_utils.dart';
import '../../utils/date_utils.dart';
import '../../widgets/checklist_paste_steps_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import 'run_detail_screen.dart';

/// TemplateDetailScreen — fetch template + items, start run.
/// EXP 7: Edit mode (chỉ template không phải system) với reorder + CRUD items.
class TemplateDetailScreen extends StatefulWidget {
  final String templateId;
  const TemplateDetailScreen({super.key, required this.templateId});

  @override
  State<TemplateDetailScreen> createState() => _TemplateDetailScreenState();
}

class _TemplateDetailScreenState extends State<TemplateDetailScreen> {
  Template? _template;
  List<TemplateItem> _items = [];
  List<ChecklistCategory> _categories = [];
  bool _loading = false;
  bool _editMode = false;
  bool _savingTitle = false;
  final _titleCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Hiện ngay bản đã lưu trong SQLite (nếu có), sau đó mới hỏi server.
  Future<void> _load() async {
    setState(() => _loading = true);
    await _loadLocal();
    if (mounted && _template != null) setState(() => _loading = false);
    await _revalidate();
  }

  Future<void> _loadLocal() async {
    final repo = ChecklistsRepository.instance;
    final local = await repo.getTemplateLocal(widget.templateId);
    final categories = await repo.listCategoriesLocal();
    if (!mounted || local == null) return;
    _applyTemplate(local.template, local.items, categories);
  }

  Future<void> _revalidate() async {
    if (!mounted) return;
    try {
      final results = await Future.wait([
        ChecklistsRepository.instance.getTemplate(widget.templateId),
        ChecklistsRepository.instance.listCategories(),
      ]);
      final res = results[0] as ({Template template, List<TemplateItem> items});
      if (!mounted) return;
      _applyTemplate(
        res.template,
        res.items,
        results[1] as List<ChecklistCategory>,
      );
    } on ApiException catch (e) {
      // Đã có bản cache để xem thì lỗi mạng tạm thời không đáng báo.
      if (mounted && (_template == null || !e.isRetryable)) {
        _showError(e.vnMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyTemplate(
    Template template,
    List<TemplateItem> items,
    List<ChecklistCategory> categories,
  ) {
    setState(() {
      _template = template;
      _items = items;
      _categories = categories;
      // Không đè tiêu đề người dùng đang gõ dở.
      if (!_editMode) _titleCtrl.text = template.title;
    });
  }

  Future<void> _startRun() async {
    try {
      final res = await ChecklistsRepository.instance.startRun(
        templateId: widget.templateId,
        name: _template?.title,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RunDetailScreen(runId: res.run.id)),
      );
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  // EXP 7 — Edit mode helpers
  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    try {
      final items = await ChecklistsRepository.instance.reorderItems(
        widget.templateId,
        _items.map((i) => i.id).toList(),
      );
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) {
        _showError(e.vnMessage);
        _load();
      }
    }
  }

  Future<void> _addItem() async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm bước'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tên bước'),
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
    if (title == null || title.isEmpty) return;
    try {
      final item = await ChecklistsRepository.instance.addItem(
        widget.templateId,
        title: title,
        isRequired: true,
      );
      setState(() => _items = [..._items, item]);
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _showPasteStepsSheet() async {
    final clipboard = await Clipboard.getData('text/plain');
    if (!mounted) return;
    final raw = await showChecklistPasteStepsSheet(
      context,
      initialText: clipboard?.text ?? '',
    );
    if (!mounted || raw == null) return;
    final titles = parseChecklistStepLines(raw);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appendPastedSteps(titles);
    });
  }

  Future<void> _appendPastedSteps(List<String> titles) async {
    if (titles.isEmpty) {
      _showError('Không tìm thấy bước hợp lệ');
      return;
    }
    try {
      final created = <TemplateItem>[];
      for (final title in titles) {
        created.add(
          await ChecklistsRepository.instance.addItem(
            widget.templateId,
            title: title,
            isRequired: true,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _items = [..._items, ...created]);
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _deleteItem(TemplateItem item) async {
    try {
      await ChecklistsRepository.instance.deleteItem(
        widget.templateId,
        item.id,
      );
      setState(() => _items.removeWhere((i) => i.id == item.id));
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _editItemTitle(TemplateItem item) async {
    final ctrl = TextEditingController(text: item.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa bước'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Tên bước'),
          onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted) return;
    if (title == null) return;
    if (title.isEmpty) {
      _showError('Tên bước không được để trống');
      return;
    }
    if (title == item.title) return;

    final previousItems = List<TemplateItem>.of(_items);
    final optimistic = item.copyWith(title: title);
    setState(() {
      _items = _items.map((i) => i.id == item.id ? optimistic : i).toList();
    });

    try {
      final updated = await ChecklistsRepository.instance.patchItem(
        widget.templateId,
        item.id,
        {'title': title},
      );
      if (!mounted) return;
      setState(() {
        _items = _items.map((i) => i.id == item.id ? updated : i).toList();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _items = previousItems);
      _showError(e.vnMessage);
    }
  }

  Future<void> _toggleRequired(TemplateItem item) async {
    try {
      final updated = await ChecklistsRepository.instance.patchItem(
        widget.templateId,
        item.id,
        {'is_required': !item.isRequired},
      );
      setState(() {
        _items = _items.map((i) => i.id == item.id ? updated : i).toList();
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _changeCategory() async {
    final template = _template;
    if (template == null || template.isSystem) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Chưa phân loại'),
              leading: const Icon(Icons.block_outlined),
              trailing: template.categoryId == null
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.of(ctx).pop('__uncategorized__'),
            ),
            ..._categories.map(
              (category) => ListTile(
                title: Text(category.name),
                subtitle: category.isSystem
                    ? const Text('Hệ thống')
                    : const Text('Của tôi'),
                leading: Icon(
                  ChecklistCategory.iconFor(category.icon),
                  color: category.color,
                ),
                trailing: template.categoryId == category.id
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(category.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final categoryId = picked == '__uncategorized__' ? null : picked;
    try {
      final updated = await ChecklistsRepository.instance.updateTemplate(
        template.id,
        {'category_id': categoryId},
      );
      if (!mounted) return;
      setState(() => _template = updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'invalid_category') {
        await ChecklistsRepository.instance.listCategories();
      }
      _showError(e.vnMessage);
    }
  }

  Future<bool> _saveTemplateTitle() async {
    final template = _template;
    if (template == null || template.isSystem || _savingTitle) return false;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showError('Vui lòng nhập tiêu đề checklist');
      return false;
    }
    if (title == template.title) return true;

    final previous = template;
    setState(() {
      _savingTitle = true;
      _template = template.copyWith(title: title, updatedAt: DateTime.now());
    });
    try {
      final updated = await ChecklistsRepository.instance.updateTemplate(
        template.id,
        {'title': title},
      );
      if (!mounted) return false;
      setState(() {
        _template = updated;
        _titleCtrl.text = updated.title;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã lưu tiêu đề')));
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() {
        _template = previous;
        _titleCtrl.text = previous.title;
      });
      _showError(e.vnMessage);
      return false;
    } finally {
      if (mounted) setState(() => _savingTitle = false);
    }
  }

  Future<void> _toggleEditMode() async {
    if (!_editMode) {
      setState(() {
        _titleCtrl.text = _template?.title ?? '';
        _editMode = true;
      });
      return;
    }
    final saved = await _saveTemplateTitle();
    if (!mounted || !saved) return;
    setState(() => _editMode = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _template == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_template == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Không tìm thấy template')),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final template = _template!;
    final canEdit = !template.isSystem;
    final categoryById = {for (final c in _categories) c.id: c};
    final category = template.categoryId == null
        ? null
        : categoryById[template.categoryId];

    return Scaffold(
      appBar: AppBar(
        title: Text(template.title),
        actions: [
          if (canEdit)
            IconButton(
              icon: Icon(_editMode ? Icons.check : Icons.edit_outlined),
              onPressed: _savingTitle ? null : _toggleEditMode,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Template.iconFor(template.icon),
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_editMode)
                        TextField(
                          controller: _titleCtrl,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Tiêu đề checklist',
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            suffixIcon: _savingTitle
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.check_rounded),
                                    tooltip: 'Lưu tiêu đề',
                                    onPressed: _saveTemplateTitle,
                                  ),
                          ),
                          onSubmitted: (_) => _saveTemplateTitle(),
                        )
                      else
                        Text(
                          template.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (template.description != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            template.description!,
                            style: TextStyle(fontSize: 13, color: secondary),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('${_items.length} bước'),
                _TemplateDetailCategoryChip(
                  template: template,
                  category: category,
                ),
                if (template.lastUsedAt != null)
                  _chip(
                    'Cập nhật: ${AppDateUtils.formatRelative(template.lastUsedAt!)}',
                  ),
              ],
            ),
          ),
          const SectionHeader(label: 'Các bước'),
          if (_editMode)
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Danh mục'),
              subtitle: Text(
                category?.name ?? template.category ?? 'Chưa phân loại',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changeCategory,
            ),
          if (_editMode) _editList(secondary) else _readList(secondary),
          if (_editMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showPasteStepsSheet,
                      icon: const Icon(Icons.content_paste_outlined),
                      label: const Text('Dán bước'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm bước'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _editMode
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PrimaryButton(
                  label: 'Bắt đầu ngay',
                  icon: Icons.play_arrow,
                  onPressed: _startRun,
                ),
              ),
            ),
    );
  }

  Widget _readList(Color secondary) {
    return Column(
      children: _items.map((it) {
        return ListTile(
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              '${it.position}',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          title: Text(it.title),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (it.isRequired ? AppColors.danger : secondary).withValues(
                alpha: 0.15,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              it.isRequired ? 'Bắt buộc' : 'Tùy chọn',
              style: TextStyle(
                fontSize: 11,
                color: it.isRequired ? AppColors.danger : secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _editList(Color secondary) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      onReorder: _reorder,
      itemBuilder: (ctx, i) {
        final it = _items[i];
        return Padding(
          key: ValueKey(it.id),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.drag_handle),
                ),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _editItemTitle(it),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Text(
                      it.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  it.isRequired ? Icons.star : Icons.star_outline,
                  color: it.isRequired ? AppColors.danger : secondary,
                  size: 20,
                ),
                onPressed: () => _toggleRequired(it),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _deleteItem(it),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _TemplateDetailCategoryChip extends StatelessWidget {
  final Template template;
  final ChecklistCategory? category;

  const _TemplateDetailCategoryChip({
    required this.template,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final label = category?.name ?? template.category;
    if (label == null || label.isEmpty) {
      return _plainChip('Chưa phân loại');
    }
    final color = category?.color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ChecklistCategory.iconFor(category?.icon),
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _plainChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
