import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/checklist_category.dart';
import '../../models/run.dart';
import '../../models/template.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_snack.dart';
import '../../utils/checklist_local_events.dart';
import '../../utils/date_utils.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/pressable.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/run_status_chip.dart';
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

  /// Đã đọc xong cache Drift ít nhất một lần (kể cả khi cache rỗng).
  bool _localLoaded = false;

  /// Số lượt làm mới từ server đang chạy.
  int _inFlight = 0;

  bool get _refreshing => _inFlight > 0;
  bool get _hasData =>
      _templates.isNotEmpty || _runs.isNotEmpty || _categories.isNotEmpty;

  @override
  void initState() {
    super.initState();
    ChecklistLocalEvents.instance.addListener(_onLocalChanged);
    _refresh();
  }

  @override
  void dispose() {
    ChecklistLocalEvents.instance.removeListener(_onLocalChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onLocalChanged() => unawaited(_loadLocal());

  /// Hiện ngay dữ liệu đã lưu trong SQLite, sau đó mới hỏi server.
  Future<void> _refresh() async {
    await _loadLocal();
    await _revalidate();
  }

  Future<void> _loadLocal() async {
    final repo = ChecklistsRepository.instance;
    final categoryId = _selectedCategoryId;
    final uncategorized = _showUncategorized;
    final categories = await repo.listCategoriesLocal();
    final templates = await repo.listTemplatesLocal(
      categoryId: categoryId,
      uncategorized: uncategorized,
    );
    final runs = await repo.listRunsLocal(limit: 20);
    // Người dùng đã đổi bộ lọc trong lúc chờ → kết quả này không còn đúng.
    if (!mounted ||
        categoryId != _selectedCategoryId ||
        uncategorized != _showUncategorized) {
      return;
    }
    setState(() {
      _categories = categories;
      _templates = templates;
      _runs = runs.items;
      _localLoaded = true;
    });
  }

  /// Lấy dữ liệu mới nhất từ server (repository tự ghi vào Drift), rồi vẽ lại
  /// ngay khi có kết quả. Lỗi tạm thời không báo nếu đã có dữ liệu để xem.
  Future<void> _revalidate() async {
    if (!mounted) return;
    final categoryId = _selectedCategoryId;
    final uncategorized = _showUncategorized;
    setState(() => _inFlight++);
    try {
      final repo = ChecklistsRepository.instance;
      final results = await Future.wait([
        repo.listCategories(scope: 'all'),
        repo.listTemplates(
          scope: 'all',
          categoryId: categoryId,
          uncategorized: uncategorized,
        ),
        repo.listRuns(limit: 20),
      ]);
      if (!mounted ||
          categoryId != _selectedCategoryId ||
          uncategorized != _showUncategorized) {
        return;
      }
      final runsRes = results[2] as ({List<Run> items, String? nextCursor});
      setState(() {
        _categories = results[0] as List<ChecklistCategory>;
        _templates = results[1] as List<Template>;
        _runs = runsRes.items;
        _localLoaded = true;
      });
    } on ApiException catch (e) {
      if (mounted && (!_hasData || !e.isRetryable)) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _inFlight--);
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
    final confirm = await showAppConfirmDialog(
      context,
      title: 'Xóa khỏi lịch sử?',
      message: 'Hành động này không thể hoàn tác.',
      confirmLabel: 'Xóa',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    try {
      await ChecklistsRepository.instance.deleteRun(run.id);
      setState(() => _runs.removeWhere((r) => r.id == run.id));
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  void _showError(String msg) {
    showAppSnack(context, msg, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checklist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_rounded),
            tooltip: 'Quản lý danh mục',
            onPressed: _openCategoryManager,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Mẫu'),
            Tab(text: 'Lịch sử'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (ctx, _) => AnimatedScale(
          scale: _tab.index == 0 ? 1 : 0,
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          child: FloatingActionButton(
            heroTag: null,
            tooltip: 'Tạo template',
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const TemplateCreateScreen()),
              );
              if (created == true && mounted) _refresh();
            },
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
      ),
      body: !_localLoaded || (_refreshing && !_hasData)
          ? const AppSpinner()
          : Column(
              children: [
                if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: TabBarView(
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
        onReorderStart: (_) => AppHaptics.medium(),
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
                  icon: Icons.checklist_rounded,
                  title: 'Chưa có template nào',
                ),
              ),
          ],
        ),
        itemCount: templates.length,
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = Curves.easeOut.transform(animation.value);
              return Transform.scale(
                scale: 1 + 0.02 * t,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8 * t,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  shape: AppShape.squircle(AppRadius.lg),
                  child: child,
                ),
              );
            },
          );
        },
        itemBuilder: (ctx, i) {
          final t = templates[i];
          final category = t.categoryId == null
              ? null
              : categoryById[t.categoryId];
          final categoryLabel = category?.name ?? t.category;
          final hasCategory = categoryLabel != null && categoryLabel.isNotEmpty;
          return Padding(
            key: ValueKey('checklist-template-${t.id}'),
            padding: const EdgeInsets.only(bottom: 10),
            child: AppSurface(
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
              onTap: () async {
                await Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => TemplateDetailScreen(templateId: t.id),
                  ),
                );
                onChanged();
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: ShapeDecoration(
                      color: ctx.appPrimarySoft,
                      shape: AppShape.squircle(AppRadius.sm),
                    ),
                    child: Icon(
                      Template.iconFor(t.icon),
                      color: ctx.appPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  t.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                            ),
                            if (t.isSystem)
                              Container(
                                margin: const EdgeInsets.only(left: 6, top: 3),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: ShapeDecoration(
                                  color: ctx.appPrimarySoft,
                                  shape: AppShape.pill,
                                ),
                                child: Text(
                                  'Hệ thống',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: ctx.appPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (hasCategory)
                              Flexible(
                                child: _TemplateCategoryChip(
                                  template: t,
                                  category: category,
                                ),
                              ),
                            const Spacer(),
                            _StartRunButton(
                              templateId: t.id,
                              title: t.title,
                              onChanged: onChanged,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _TemplateReorderHandle(index: i),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Nút "Bắt đầu" tạo một lượt chạy mới từ template. Chặn nhấn đôi khi đang tạo.
class _StartRunButton extends StatefulWidget {
  final String templateId;
  final String title;
  final VoidCallback onChanged;

  const _StartRunButton({
    required this.templateId,
    required this.title,
    required this.onChanged,
  });

  @override
  State<_StartRunButton> createState() => _StartRunButtonState();
}

class _StartRunButtonState extends State<_StartRunButton> {
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppHaptics.light();
    try {
      final navigator = Navigator.of(context);
      // Bị chặn (đang làm việc khác) thì runId = null và người dùng đã được báo.
      final runId = await beginChecklistRun(
        context,
        templateId: widget.templateId,
        name: widget.title,
      );
      if (runId == null || !mounted) return;
      widget.onChanged();
      unawaited(openRunDetail(navigator, runId));
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.vnMessage, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      enabled: !_busy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : _start,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: ShapeDecoration(
              color: AppColors.accentFill,
              shape: AppShape.pill,
            ),
            child: _busy
                ? const AppSpinner(radius: 8, centered: false)
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Bắt đầu',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _TemplateReorderHandle extends StatelessWidget {
  final int index;

  const _TemplateReorderHandle({required this.index});

  @override
  Widget build(BuildContext context) {
    final color = context.appTextSecondary.withValues(alpha: 0.7);
    return ReorderableDragStartListener(
      index: index,
      child: Semantics(
        label: 'Kéo để sắp xếp checklist',
        button: true,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Icon(Icons.drag_indicator_rounded, color: color),
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
            context,
            label: 'Tất cả',
            selected: selectedCategoryId == null && !showUncategorized,
            onTap: () => onChanged(null),
          ),
          const SizedBox(width: 8),
          _filterChip(
            context,
            label: 'Chưa phân loại',
            selected: showUncategorized,
            onTap: () => onChanged(null, uncategorized: true),
          ),
          for (final category in categories) ...[
            const SizedBox(width: 8),
            _filterChip(
              context,
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

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? color,
  }) {
    final fillColor = color ?? AppColors.accentFill;
    final iconColor = color ?? context.appPrimary;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: selected ? Colors.white : iconColor),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      selected: selected,
      selectedColor: fillColor,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : null,
      ),
      onSelected: (_) {
        AppHaptics.selection();
        onTap();
      },
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
    final color = category?.color ?? context.appTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: AppShape.pill,
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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
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
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final categories = await ChecklistsRepository.instance.listCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_categories.isEmpty) {
        setState(() => _loadError = e.vnMessage);
      } else {
        _showError(e.vnMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createCategory() async {
    final draft = await showAppSheet<_CategoryDraft>(
      context: context,
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
    final draft = await showAppSheet<_CategoryDraft>(
      context: context,
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
    final confirm = await showAppConfirmDialog(
      context,
      title: 'Xóa danh mục?',
      message:
          'Các template đang dùng "${category.name}" sẽ chuyển về chưa phân loại.',
      confirmLabel: 'Xóa',
      destructive: true,
    );
    if (!confirm || !mounted) return;
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
    showAppSnack(context, msg, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final own = _categories.where((c) => !c.isSystem).toList();
    final system = _categories.where((c) => c.isSystem).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Danh mục checklist')),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: 'Tạo danh mục',
        onPressed: _createCategory,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: _loading && _categories.isEmpty
          ? const AppSpinner()
          : _loadError != null && _categories.isEmpty
          ? AppErrorState(message: _loadError!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 12, bottom: 96),
                children: [
                  if (own.isEmpty) ...[
                    _CategorySectionLabel('Của tôi'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
                      child: Text(
                        'Chưa có danh mục riêng. Bấm nút + để tạo danh mục đầu tiên.',
                        style: TextStyle(
                          color: context.appTextSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ] else
                    AppListSection(
                      header: 'Của tôi',
                      dividerIndent: AppListSection.iconIndent,
                      children: [
                        for (final category in own)
                          _CategoryRow(
                            category: category,
                            onEdit: () => _editCategory(category),
                            onDelete: () => _deleteCategory(category),
                          ),
                      ],
                    ),
                  AppListSection(
                    header: 'Hệ thống',
                    dividerIndent: AppListSection.iconIndent,
                    children: [
                      for (final category in system)
                        _CategoryRow(
                          category: category,
                          onEdit: null,
                          onDelete: null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _CategorySectionLabel extends StatelessWidget {
  final String label;

  const _CategorySectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: context.appTextSecondary,
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final ChecklistCategory category;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CategoryRow({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      icon: ChecklistCategory.iconFor(category.icon),
      iconColor: category.color,
      title: category.name,
      subtitle: category.isSystem ? 'Hệ thống' : 'Của tôi',
      onTap: onEdit,
      showChevron: false,
      trailing: category.isSystem
          ? Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: context.appTextSecondary,
            )
          : PopupMenuButton<String>(
              icon: Icon(
                Icons.more_horiz_rounded,
                color: context.appTextSecondary,
              ),
              onSelected: (value) {
                if (value == 'edit') onEdit?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Sửa')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Xóa', style: TextStyle(color: AppColors.danger)),
                ),
              ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thứ tự sắp xếp',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.appTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          decoration: ShapeDecoration(
            color: context.appTextSecondary.withValues(alpha: 0.08),
            shape: AppShape.squircle(AppRadius.md),
          ),
          child: Row(
            children: [
              _stepButton(
                context,
                icon: Icons.remove_rounded,
                onPressed: value <= 0 ? null : () => onChanged(value - 1),
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
                context,
                icon: Icons.add_rounded,
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        onPressed: onPressed == null
            ? null
            : () {
                AppHaptics.selection();
                onPressed();
              },
        icon: Icon(icon),
        color: context.appPrimary,
        disabledColor: context.appTextSecondary.withValues(alpha: 0.38),
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
    final accent = _parseColor(_color);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSheetHeader(
                title: widget.category == null
                    ? 'Tạo danh mục'
                    : 'Sửa danh mục',
                padding: const EdgeInsets.only(bottom: 14),
              ),
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
              Text(
                'Icon',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.appTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final icon in _icons)
                    Pressable(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          AppHaptics.selection();
                          setState(() => _icon = icon);
                        },
                        child: AnimatedContainer(
                          duration: AppMotion.normal,
                          curve: AppMotion.curve,
                          width: 48,
                          height: 48,
                          decoration: ShapeDecoration(
                            color: _icon == icon
                                ? accent.withValues(alpha: 0.16)
                                : context.appTextSecondary.withValues(
                                    alpha: 0.08,
                                  ),
                            shape: AppShape.squircle(
                              AppRadius.md,
                              side: _icon == icon
                                  ? BorderSide(color: accent, width: 1.6)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Icon(
                            ChecklistCategory.iconFor(icon),
                            size: 22,
                            color: _icon == icon
                                ? accent
                                : context.appTextSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Màu',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.appTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in _colors)
                    Pressable(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          AppHaptics.selection();
                          setState(() => _color = color);
                        },
                        child: SizedBox.square(
                          dimension: 48,
                          child: Center(
                            child: AnimatedContainer(
                              duration: AppMotion.normal,
                              curve: AppMotion.curve,
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _parseColor(color),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _color == color
                                      ? context.appTextPrimary
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: _color == color
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Lưu',
                icon: Icons.check_rounded,
                onPressed: _submit,
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
      // Vẫn cuộn được để kéo-làm-mới hoạt động ngay cả khi lịch sử rỗng.
      return LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: () async => onChanged(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: const Center(
                child: EmptyState(
                  icon: Icons.history_rounded,
                  title: 'Chưa có run nào',
                  subtitle: 'Bấm "Bắt đầu" ở một template để tạo lượt chạy.',
                ),
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: runs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final r = runs[i];
          return AppSurface(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            onTap: () async {
              await openChecklistRun(context, r);
              onChanged();
            },
            onLongPress: () {
              AppHaptics.medium();
              onDelete(r);
            },
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: ShapeDecoration(
                    color: ctx.appPrimarySoft,
                    shape: AppShape.squircle(AppRadius.sm),
                  ),
                  child: Icon(
                    Icons.checklist_rounded,
                    color: ctx.appPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _runSubtitle(r),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: ctx.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                RunStatusChip(status: r.status),
              ],
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
