import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/checklist_category.dart';
import '../../models/template.dart';
import '../../models/template_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_snack.dart';
import '../../utils/checklist_step_text_utils.dart';
import '../../utils/date_utils.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/checklist_category_picker.dart';
import '../../widgets/checklist_paste_steps_sheet.dart';
import '../../widgets/empty_state.dart';
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
  String? _loadError;
  bool _editMode = false;
  bool _savingTitle = false;
  bool _starting = false;
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
    setState(() {
      _loading = true;
      _loadError = null;
    });
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
      if (!mounted) return;
      if (_template == null) {
        setState(() => _loadError = e.vnMessage);
      } else if (!e.isRetryable) {
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
    if (_starting) return;
    _starting = true;
    var opened = false;
    try {
      final navigator = Navigator.of(context);
      // Bị chặn (đang làm việc khác) thì runId = null và người dùng đã được báo.
      final runId = await beginChecklistRun(
        context,
        templateId: widget.templateId,
        name: _template?.title,
      );
      if (runId == null || !mounted) return;
      opened = true;
      unawaited(openRunDetail(navigator, runId, replace: true));
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      // Mở được run thì giữ cờ cho tới khi màn hình này bị thay thế, để bấm đúp
      // không đẩy hai màn hình run chồng lên nhau.
      if (!opened) _starting = false;
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
    final title = await showAppTextInputDialog(
      context,
      title: 'Thêm bước',
      hintText: 'Tên bước',
      confirmLabel: 'Thêm',
    );
    if (!mounted || title == null || title.isEmpty) return;
    try {
      final item = await ChecklistsRepository.instance.addItem(
        widget.templateId,
        title: title,
        isRequired: true,
      );
      if (!mounted) return;
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
    final title = await showAppTextInputDialog(
      context,
      title: 'Sửa bước',
      hintText: 'Tên bước',
      initialText: item.title,
    );
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
    final picked = await showChecklistCategorySheet(
      context,
      categories: _categories,
      selectedId: template.categoryId,
    );
    if (picked == null) return;
    final categoryId = picked == kUncategorizedCategory ? null : picked;
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
      showAppSnack(context, 'Đã lưu tiêu đề');
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
    AppHaptics.selection();
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
    showAppSnack(context, msg, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _template == null) {
      return Scaffold(appBar: AppBar(), body: const AppSpinner());
    }
    if (_template == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _loadError != null
            ? AppErrorState(message: _loadError!, onRetry: _load)
            : const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Không tìm thấy template',
              ),
      );
    }
    final secondary = context.appTextSecondary;
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
              tooltip: _editMode ? 'Xong' : 'Chỉnh sửa',
              icon: AnimatedSwitcher(
                duration: AppMotion.fast,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  _editMode ? Icons.check_rounded : Icons.edit_rounded,
                  key: ValueKey(_editMode),
                ),
              ),
              onPressed: _savingTitle ? null : _toggleEditMode,
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: _editMode ? 32 : 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: ShapeDecoration(
                    color: context.appPrimarySoft,
                    shape: AppShape.squircle(AppRadius.lg),
                  ),
                  child: Icon(
                    Template.iconFor(template.icon),
                    color: context.appPrimary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: AppMotion.normal,
                        child: _editMode
                            ? TextField(
                                key: const ValueKey('template-title-edit'),
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
                                          width: 36,
                                          height: 36,
                                          child: AppSpinner(radius: 8),
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.check_rounded),
                                          tooltip: 'Lưu tiêu đề',
                                          onPressed: _saveTemplateTitle,
                                        ),
                                ),
                                onSubmitted: (_) => _saveTemplateTitle(),
                              )
                            : Align(
                                key: const ValueKey('template-title-read'),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  template.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
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
                _chip(context, '${_items.length} bước'),
                _TemplateDetailCategoryChip(
                  template: template,
                  category: category,
                ),
                if (template.lastUsedAt != null)
                  _chip(
                    context,
                    'Dùng gần nhất: ${AppDateUtils.formatRelative(template.lastUsedAt!)}',
                  ),
              ],
            ),
          ),
          const SectionHeader(label: 'Các bước'),
          if (_editMode)
            AppListSection(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              dividerIndent: AppListSection.iconIndent,
              children: [
                AppListTile(
                  icon: Icons.category_rounded,
                  iconColor: category?.color ?? AppColors.tagSlate,
                  title: 'Danh mục',
                  value:
                      category?.name ?? template.category ?? 'Chưa phân loại',
                  onTap: _changeCategory,
                ),
              ],
            ),
          AnimatedSwitcher(
            duration: AppMotion.normal,
            child: _editMode
                ? KeyedSubtree(
                    key: const ValueKey('steps-edit'),
                    child: _editList(secondary),
                  )
                : KeyedSubtree(
                    key: const ValueKey('steps-read'),
                    child: _readList(secondary),
                  ),
          ),
          if (_editMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'Dán bước',
                      icon: Icons.content_paste_rounded,
                      variant: PrimaryButtonVariant.tonal,
                      onPressed: _showPasteStepsSheet,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Thêm bước',
                      icon: Icons.add_rounded,
                      variant: PrimaryButtonVariant.tonal,
                      onPressed: _addItem,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _editMode
          ? null
          : Container(
              decoration: BoxDecoration(
                color: context.appBackground,
                border: Border(
                  top: BorderSide(color: context.appDivider, width: 0.5),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: PrimaryButton(
                    label: 'Bắt đầu ngay',
                    icon: Icons.play_arrow_rounded,
                    onPressed: _startRun,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _readList(Color secondary) {
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
        child: Text('Chưa có bước nào', style: TextStyle(color: secondary)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppSurface(
        clipBehavior: Clip.antiAlias,
        showShadow: false,
        child: Column(
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0)
                Divider(height: 0.5, indent: 56, color: context.appDivider),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: context.appPrimarySoft,
                        shape: AppShape.squircle(AppRadius.xs),
                      ),
                      child: Text(
                        '${_items[i].position}',
                        style: TextStyle(
                          color: context.appPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _items[i].title,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RequiredBadge(required: _items[i].isRequired),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _editList(Color secondary) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _items.length,
      onReorder: _reorder,
      onReorderStart: (_) => AppHaptics.medium(),
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: AppShape.squircle(AppRadius.md),
        child: child,
      ),
      itemBuilder: (ctx, i) {
        final it = _items[i];
        return Padding(
          key: ValueKey(it.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: AppSurface(
            radius: AppRadius.md,
            showShadow: false,
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: i,
                  child: SizedBox.square(
                    dimension: 44,
                    child: Center(
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: secondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    onTap: () => _editItemTitle(it),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
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
                  tooltip: it.isRequired ? 'Bỏ bắt buộc' : 'Đặt bắt buộc',
                  icon: Icon(
                    it.isRequired
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: it.isRequired ? AppColors.warning : secondary,
                    size: 22,
                  ),
                  onPressed: () {
                    AppHaptics.selection();
                    _toggleRequired(it);
                  },
                ),
                IconButton(
                  tooltip: 'Xóa bước',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 22,
                    color: secondary,
                  ),
                  onPressed: () => _deleteItem(it),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: context.appPrimarySoft,
        shape: AppShape.pill,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: context.appPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Huy hiệu "Bắt buộc"/"Tùy chọn" của một bước (tông trung tính, không dùng đỏ
/// cho trạng thái bình thường).
class _RequiredBadge extends StatelessWidget {
  final bool required;

  const _RequiredBadge({required this.required});

  @override
  Widget build(BuildContext context) {
    final color = required ? context.appPrimary : context.appTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: AppShape.pill,
      ),
      child: Text(
        required ? 'Bắt buộc' : 'Tùy chọn',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
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
      return _plainChip(context, 'Chưa phân loại');
    }
    final color = category?.color ?? context.appTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: AppShape.pill,
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

  Widget _plainChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: context.appPrimarySoft,
        shape: AppShape.pill,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: context.appPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
