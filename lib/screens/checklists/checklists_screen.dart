import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/checklist_category.dart';
import '../../models/run.dart';
import '../../models/template.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../widgets/empty_state.dart';
import 'run_detail_screen.dart';
import 'template_create_screen.dart';
import 'template_detail_screen.dart';

class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  List<Template> _templates = [];
  List<ChecklistCategory> _categories = [];
  List<Run> _runs = [];
  String? _selectedCategoryId;
  bool _showUncategorized = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final catFut = ChecklistsRepository.instance.listCategories(scope: 'all');
      final tplFut = ChecklistsRepository.instance.listTemplates(
        scope: 'all',
        categoryId: _selectedCategoryId,
        uncategorized: _showUncategorized,
      );
      final runsFut = ChecklistsRepository.instance.listRuns(limit: 20);
      final results = await Future.wait([catFut, tplFut, runsFut]);
      if (!mounted) return;
      final runsRes = results[2] as ({List<Run> items, String? nextCursor});
      setState(() {
        _categories = results[0] as List<ChecklistCategory>;
        _templates = results[1] as List<Template>;
        _runs = runsRes.items;
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectCategoryFilter(String? categoryId, {bool uncategorized = false}) {
    setState(() {
      _selectedCategoryId = categoryId;
      _showUncategorized = uncategorized;
    });
    _refresh();
  }

  Future<void> _openCategoryManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _ChecklistCategoriesScreen()),
    );
    if (mounted) _refresh();
  }

  void _reorderTemplates(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final previous = List<Template>.from(_templates);
    final next = List<Template>.from(_templates);
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final moved = next.removeAt(oldIndex);
    next.insert(targetIndex, moved);
    final ordered = [
      for (var i = 0; i < next.length; i++) next[i].copyWith(sortOrder: i + 1),
    ];
    setState(() => _templates = ordered);
    _persistTemplateOrder(ordered, previous);
  }

  Future<void> _persistTemplateOrder(
    List<Template> ordered,
    List<Template> previous,
  ) async {
    try {
      final saved = await ChecklistsRepository.instance.reorderTemplates(
        templates: ordered,
        categoryId: _selectedCategoryId,
        uncategorized: _showUncategorized,
      );
      if (!mounted) return;
      setState(() => _templates = saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _templates = previous);
      _showError(e.vnMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _templates = previous);
      _showError('Không thể lưu thứ tự checklist');
    }
  }

  Future<void> _deleteRun(Run run) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa khỏi lịch sử?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ChecklistsRepository.instance.deleteRun(run.id);
      setState(() => _runs.removeWhere((r) => r.id == run.id));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checklist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Quản lý danh mục',
            onPressed: _openCategoryManager,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Templates'),
            Tab(text: 'Lịch sử'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (ctx, _) => _tab.index == 0
            ? _SquareFab(
                tooltip: 'Tạo template',
                icon: Icons.add_rounded,
                onPressed: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const TemplateCreateScreen(),
                    ),
                  );
                  if (created == true && mounted) _refresh();
                },
              )
            : const SizedBox.shrink(),
      ),
      body: _loading && _templates.isEmpty && _runs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _TemplatesTab(
                  templates: _templates,
                  categories: _categories,
                  selectedCategoryId: _selectedCategoryId,
                  showUncategorized: _showUncategorized,
                  onFilterChanged: _selectCategoryFilter,
                  onReorder: _reorderTemplates,
                  onChanged: _refresh,
                ),
                _RunsTab(
                  runs: _runs,
                  onDelete: _deleteRun,
                  onChanged: _refresh,
                ),
              ],
            ),
    );
  }
}

class _TemplatesTab extends StatelessWidget {
  final List<Template> templates;
  final List<ChecklistCategory> categories;
  final String? selectedCategoryId;
  final bool showUncategorized;
  final void Function(String? categoryId, {bool uncategorized}) onFilterChanged;
  final ReorderCallback onReorder;
  final VoidCallback onChanged;
  const _TemplatesTab({
    required this.templates,
    required this.categories,
    required this.selectedCategoryId,
    required this.showUncategorized,
    required this.onFilterChanged,
    required this.onReorder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final categoryById = {
      for (final category in categories) category.id: category,
    };
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: onReorder,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CategoryFilterBar(
              categories: categories,
              selectedCategoryId: selectedCategoryId,
              showUncategorized: showUncategorized,
              onChanged: onFilterChanged,
            ),
            const SizedBox(height: 12),
            if (templates.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: EmptyState(
                  icon: Icons.checklist,
                  title: 'Chưa có template nào',
                ),
              ),
          ],
        ),
        itemCount: templates.length,
        proxyDecorator: (child, index, animation) {
          return Material(
            color: Colors.transparent,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: child,
          );
        },
        itemBuilder: (ctx, i) {
          final t = templates[i];
          final category = t.categoryId == null
              ? null
              : categoryById[t.categoryId];
          final categoryLabel = category?.name ?? t.category;
          return Padding(
            key: ValueKey('checklist-template-${t.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: Icon(
                  Template.iconFor(t.icon),
                  color: AppColors.primary,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (t.isSystem)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Hệ thống',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: categoryLabel == null || categoryLabel.isEmpty
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: _TemplateCategoryChip(
                          template: t,
                          category: category,
                        ),
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Bắt đầu'),
                      onPressed: () async {
                        try {
                          final res = await ChecklistsRepository.instance
                              .startRun(templateId: t.id, name: t.title);
                          if (!ctx.mounted) return;
                          onChanged();
                          Navigator.of(ctx).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  RunDetailScreen(runId: res.run.id),
                            ),
                          );
                        } on ApiException catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(e.vnMessage)),
                            );
                          }
                        }
                      },
                    ),
                    _TemplateReorderHandle(index: i),
                  ],
                ),
                onTap: () async {
                  await Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => TemplateDetailScreen(templateId: t.id),
                    ),
                  );
                  onChanged();
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TemplateReorderHandle extends StatelessWidget {
  final int index;

  const _TemplateReorderHandle({required this.index});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).iconTheme.color?.withValues(alpha: 0.72);
    return ReorderableDragStartListener(
      index: index,
      child: Semantics(
        label: 'Kéo để sắp xếp checklist',
        button: true,
        child: SizedBox.square(
          dimension: 44,
          child: Center(child: Icon(Icons.drag_handle_rounded, color: color)),
        ),
      ),
    );
  }
}

class _SquareFab extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _SquareFab({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.primary,
        elevation: 6,
        shadowColor: AppColors.primary.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox.square(
            dimension: 56,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  final List<ChecklistCategory> categories;
  final String? selectedCategoryId;
  final bool showUncategorized;
  final void Function(String? categoryId, {bool uncategorized}) onChanged;

  const _CategoryFilterBar({
    required this.categories,
    required this.selectedCategoryId,
    required this.showUncategorized,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(
            label: 'Tất cả',
            selected: selectedCategoryId == null && !showUncategorized,
            onTap: () => onChanged(null),
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: 'Chưa phân loại',
            selected: showUncategorized,
            onTap: () => onChanged(null, uncategorized: true),
          ),
          for (final category in categories) ...[
            const SizedBox(width: 8),
            _filterChip(
              label: category.name,
              selected: selectedCategoryId == category.id,
              icon: ChecklistCategory.iconFor(category.icon),
              color: category.color,
              onTap: () => onChanged(category.id),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? color,
  }) {
    final chipColor = color ?? AppColors.primary;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: selected ? Colors.white : chipColor),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      selected: selected,
      selectedColor: chipColor,
      labelStyle: TextStyle(color: selected ? Colors.white : null),
      onSelected: (_) => onTap(),
    );
  }
}

class _TemplateCategoryChip extends StatelessWidget {
  final Template template;
  final ChecklistCategory? category;

  const _TemplateCategoryChip({required this.template, required this.category});

  @override
  Widget build(BuildContext context) {
    final label = category?.name ?? template.category;
    if (label == null || label.isEmpty) {
      return const SizedBox.shrink();
    }
    final color = category?.color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ChecklistCategory.iconFor(category?.icon),
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistCategoriesScreen extends StatefulWidget {
  const _ChecklistCategoriesScreen();

  @override
  State<_ChecklistCategoriesScreen> createState() =>
      _ChecklistCategoriesScreenState();
}

class _ChecklistCategoriesScreenState
    extends State<_ChecklistCategoriesScreen> {
  List<ChecklistCategory> _categories = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final categories = await ChecklistsRepository.instance.listCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createCategory() async {
    final draft = await showModalBottomSheet<_CategoryDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CategoryEditorSheet(),
    );
    if (draft == null) return;
    try {
      await ChecklistsRepository.instance.createCategory(
        name: draft.name,
        icon: draft.icon,
        color: draft.color,
        sortOrder: draft.sortOrder,
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showError(_categoryErrorMessage(e));
    } catch (_) {
      if (mounted) _showError('Không thể tạo danh mục');
    }
  }

  Future<void> _editCategory(ChecklistCategory category) async {
    if (category.isSystem) return;
    final draft = await showModalBottomSheet<_CategoryDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditorSheet(category: category),
    );
    if (draft == null) return;
    try {
      await ChecklistsRepository.instance.updateCategory(category, {
        'name': draft.name,
        'icon': draft.icon,
        'color': draft.color,
        'sort_order': draft.sortOrder,
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showError(_categoryErrorMessage(e));
    } catch (_) {
      if (mounted) _showError('Không thể lưu danh mục');
    }
  }

  Future<void> _deleteCategory(ChecklistCategory category) async {
    if (category.isSystem) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa danh mục?'),
        content: Text(
          'Các template đang dùng "${category.name}" sẽ chuyển về chưa phân loại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ChecklistsRepository.instance.deleteCategory(category);
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showError(_categoryErrorMessage(e));
    }
  }

  String _categoryErrorMessage(ApiException e) {
    if (e.code == 'duplicate') return 'Tên danh mục đã tồn tại';
    if (e.code == 'read_only') return 'Danh mục hệ thống chỉ có thể xem';
    if (e.code == 'not_found') return 'Không tìm thấy danh mục';
    return e.vnMessage;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final own = _categories.where((c) => !c.isSystem).toList();
    final system = _categories.where((c) => c.isSystem).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Danh mục checklist')),
      floatingActionButton: _SquareFab(
        tooltip: 'Tạo danh mục',
        icon: Icons.add_rounded,
        onPressed: _createCategory,
      ),
      body: _loading && _categories.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  const _CategorySectionHeader(label: 'Của tôi'),
                  if (own.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('Chưa có danh mục riêng'),
                    )
                  else
                    ...own.map(
                      (category) => _CategoryListTile(
                        category: category,
                        onEdit: () => _editCategory(category),
                        onDelete: () => _deleteCategory(category),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const _CategorySectionHeader(label: 'Hệ thống'),
                  ...system.map(
                    (category) => _CategoryListTile(
                      category: category,
                      onEdit: null,
                      onDelete: null,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CategorySectionHeader extends StatelessWidget {
  final String label;

  const _CategorySectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CategoryListTile extends StatelessWidget {
  final ChecklistCategory category;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CategoryListTile({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: category.color.withValues(alpha: 0.16),
          child: Icon(
            ChecklistCategory.iconFor(category.icon),
            color: category.color,
          ),
        ),
        title: Text(category.name),
        subtitle: Text(category.isSystem ? 'Hệ thống' : 'Của tôi'),
        trailing: category.isSystem
            ? const Icon(Icons.lock_outline, size: 18)
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Sửa')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Xóa',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
        onTap: onEdit,
      ),
    );
  }
}

class _CategoryDraft {
  final String name;
  final String? icon;
  final String color;
  final int sortOrder;

  const _CategoryDraft({
    required this.name,
    required this.icon,
    required this.color,
    required this.sortOrder,
  });
}

class _SortOrderStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _SortOrderStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: 0.24);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Thứ tự sắp xếp',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          height: 46,
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _stepButton(
                icon: Icons.add_rounded,
                onPressed: () => onChanged(value + 1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _stepButton(
                icon: Icons.remove_rounded,
                onPressed: value <= 0 ? null : () => onChanged(value - 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox.square(
      dimension: 46,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: AppColors.primary,
        disabledColor: AppColors.textSecondary.withValues(alpha: 0.38),
        splashRadius: 22,
      ),
    );
  }
}

class _CategoryEditorSheet extends StatefulWidget {
  final ChecklistCategory? category;

  const _CategoryEditorSheet({this.category});

  @override
  State<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<_CategoryEditorSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );
  late int _sortOrder = widget.category?.sortOrder ?? 0;
  late String _icon = widget.category?.icon ?? 'checklist';
  late String _color = _formatColor(
    widget.category?.color ?? AppColors.primary,
  );

  static const _icons = [
    'checklist',
    'code',
    'work',
    'health',
    'home',
    'fitness',
    'book',
    'money',
    'travel',
    'shopping',
  ];

  static const _colors = [
    '#4f46e5',
    '#3366ff',
    '#16a34a',
    '#dc2626',
    '#f59e0b',
    '#06b6d4',
    '#a855f7',
    '#64748b',
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(_color)) return;
    Navigator.of(context).pop(
      _CategoryDraft(
        name: name,
        icon: _icon,
        color: _color,
        sortOrder: _sortOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.category == null ? 'Tạo danh mục' : 'Sửa danh mục',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Tên'),
              ),
              const SizedBox(height: 14),
              _SortOrderStepper(
                value: _sortOrder,
                onChanged: (value) => setState(() => _sortOrder = value),
              ),
              const SizedBox(height: 14),
              const Text(
                'Icon',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final icon in _icons)
                    ChoiceChip(
                      label: Icon(ChecklistCategory.iconFor(icon), size: 18),
                      selected: _icon == icon,
                      onSelected: (_) => setState(() => _icon = icon),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Màu',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in _colors)
                    InkWell(
                      onTap: () => setState(() => _color = color),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _parseColor(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == color
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check),
                  label: const Text('Lưu'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _parseColor(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('ff$clean', radix: 16));
  }

  static String _formatColor(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }
}

class _RunsTab extends StatelessWidget {
  final List<Run> runs;
  final void Function(Run) onDelete;
  final VoidCallback onChanged;
  const _RunsTab({
    required this.runs,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return const EmptyState(icon: Icons.history, title: 'Chưa có run nào');
    }
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: runs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final r = runs[i];
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(r.displayName),
              subtitle: Text(_runSubtitle(r)),
              trailing: _RunStatusChip(status: r.status),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RunDetailScreen(runId: r.id),
                  ),
                );
                onChanged();
              },
              onLongPress: () => onDelete(r),
            ),
          );
        },
      ),
    );
  }
}

String _runSubtitle(Run run) {
  final started = 'Bắt đầu: ${AppDateUtils.formatRelative(run.startedAt)}';
  final durationMs = run.durationMs;
  if (durationMs == null) return started;
  return '$started - Thời lượng: ${_formatDurationMs(durationMs)}';
}

String _formatDurationMs(int durationMs) {
  final totalSeconds = Duration(milliseconds: durationMs).inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours == 0) return '$mm:$ss';
  final hh = hours.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

class _RunStatusChip extends StatelessWidget {
  final RunStatus status;
  const _RunStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
      case RunStatus.inProgress:
        c = AppColors.success;
        break;
      case RunStatus.completed:
        c = AppColors.textSecondary;
        break;
      case RunStatus.abandoned:
        c = AppColors.warning;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}
