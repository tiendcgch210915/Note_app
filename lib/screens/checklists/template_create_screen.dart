import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/checklist_category.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_snack.dart';
import '../../utils/checklist_step_text_utils.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/checklist_category_picker.dart';
import '../../widgets/checklist_paste_steps_sheet.dart';
import '../../widgets/pressable.dart';
import '../../widgets/primary_button.dart';

class _DraftItem {
  String title;
  bool isRequired = true;
  _DraftItem({this.title = ''});
}

class TemplateCreateScreen extends StatefulWidget {
  const TemplateCreateScreen({super.key});

  @override
  State<TemplateCreateScreen> createState() => _TemplateCreateScreenState();
}

class _TemplateCreateScreenState extends State<TemplateCreateScreen> {
  final _title = TextEditingController();
  final String _iconName = 'checklist';
  List<ChecklistCategory> _categories = [];
  String? _categoryId;
  bool _saving = false;
  String? _titleError;

  final List<_DraftItem> _items = [
    _DraftItem(title: ''),
    _DraftItem(title: ''),
  ];
  final List<TextEditingController> _itemControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<FocusNode> _itemFocusNodes = [FocusNode(), FocusNode()];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _title.dispose();
    for (final controller in _itemControllers) {
      controller.dispose();
    }
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ChecklistsRepository.instance.listCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      AppHaptics.heavy();
      setState(() => _titleError = 'Vui lòng nhập tên template');
      return;
    }
    final validItems = _items.where((i) => i.title.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      AppHaptics.heavy();
      showAppSnack(context, 'Vui lòng nhập ít nhất 1 bước', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final items = validItems
          .map((i) => {'title': i.title.trim(), 'is_required': i.isRequired})
          .toList();
      await ChecklistsRepository.instance.createTemplate(
        title: _title.text.trim(),
        description: null,
        icon: _iconName,
        categoryId: _categoryId,
        items: items,
      );
      if (!mounted) return;
      AppHaptics.medium();
      Navigator.of(context).pop(true);
      showAppSnack(context, 'Đã tạo template');
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } catch (_) {
      if (mounted) _showError('Không thể tạo template');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addStep() {
    setState(() {
      _items.add(_DraftItem());
      _itemControllers.add(TextEditingController());
      _itemFocusNodes.add(FocusNode());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _itemFocusNodes.last.requestFocus();
    });
  }

  void _removeStep(int index) {
    AppHaptics.light();
    setState(() {
      _items.removeAt(index);
      _itemControllers.removeAt(index).dispose();
      _itemFocusNodes.removeAt(index).dispose();
    });
  }

  void _reorderSteps(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _items.removeAt(oldIndex);
      final controller = _itemControllers.removeAt(oldIndex);
      final focusNode = _itemFocusNodes.removeAt(oldIndex);
      _items.insert(newIndex, item);
      _itemControllers.insert(newIndex, controller);
      _itemFocusNodes.insert(newIndex, focusNode);
    });
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
      _insertPastedSteps(titles);
    });
  }

  void _insertPastedSteps(List<String> titles) {
    if (titles.isEmpty) {
      _showError('Không tìm thấy bước hợp lệ');
      return;
    }
    final insertIndex = _nextAppendIndex();
    setState(() {
      var index = insertIndex;
      for (final title in titles) {
        if (index < _items.length && _items[index].title.trim().isEmpty) {
          _items[index].title = title;
          _itemControllers[index].text = title;
        } else {
          _items.insert(index, _DraftItem(title: title));
          _itemControllers.insert(index, TextEditingController(text: title));
          _itemFocusNodes.insert(index, FocusNode());
        }
        index++;
      }
      if (_items.every((item) => item.title.trim().isNotEmpty)) {
        _items.add(_DraftItem());
        _itemControllers.add(TextEditingController());
        _itemFocusNodes.add(FocusNode());
      }
    });
  }

  int _nextAppendIndex() {
    for (var i = _items.length - 1; i >= 0; i--) {
      if (_items[i].title.trim().isNotEmpty) return i + 1;
    }
    return 0;
  }

  void _showError(String msg) {
    showAppSnack(context, msg, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    // Ẩn thanh nút dưới khi bàn phím mở để danh sách bước không bị ép bẹp.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Template mới'),
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
      body: Column(
        children: [
          // Toàn bộ nội dung (thẻ tên, tiêu đề "CÁC BƯỚC", danh sách bước, nút
          // "Thêm bước") nằm trong MỘT vùng cuộn: màn thấp, chữ lớn hay bàn
          // phím mở đều không gây tràn đáy.
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              buildDefaultDragHandles: false,
              itemCount: _items.length,
              onReorder: _reorderSteps,
              onReorderStart: (_) => AppHaptics.medium(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                elevation: 6,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                shape: AppShape.squircle(AppRadius.md),
                child: child,
              ),
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  AppSurface(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _title,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) {
                              if (_titleError != null) {
                                setState(() => _titleError = null);
                              }
                            },
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Tên template',
                              errorText: _titleError,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        Divider(height: 0.5, color: context.appDivider),
                        _CategoryPickerTile(
                          categories: _categories,
                          selectedId: _categoryId,
                          onSelected: (id) => setState(() => _categoryId = id),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 0, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'CÁC BƯỚC',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showPasteStepsSheet,
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 18,
                          ),
                          label: const Text('Dán bước'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              footer: PrimaryButton(
                label: 'Thêm bước',
                icon: Icons.add_rounded,
                variant: PrimaryButtonVariant.tonal,
                onPressed: _addStep,
              ),
              itemBuilder: (ctx, i) {
                final item = _items[i];
                return Padding(
                  key: ValueKey(item),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppSurface(
                    radius: AppRadius.md,
                    showShadow: false,
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: SizedBox.square(
                            dimension: 44,
                            child: Center(
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                color: ctx.appTextSecondary.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _itemControllers[i],
                                focusNode: _itemFocusNodes[i],
                                onChanged: (v) => item.title = v,
                                decoration: InputDecoration(
                                  hintText: 'Bước ${i + 1}',
                                  isDense: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                              ),
                              _RequiredToggle(
                                required: item.isRequired,
                                onTap: () => setState(
                                  () => item.isRequired = !item.isRequired,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Xóa bước',
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 22,
                            color: ctx.appTextSecondary,
                          ),
                          onPressed: () => _removeStep(i),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (!keyboardOpen)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: PrimaryButton(
                  label: 'Tạo template',
                  icon: Icons.check_rounded,
                  loading: _saving,
                  onPressed: _save,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Viên thuốc bật/tắt "Bắt buộc" của một bước (chạm cả nhãn để đổi).
class _RequiredToggle extends StatelessWidget {
  final bool required;
  final VoidCallback onTap;

  const _RequiredToggle({required this.required, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = required ? context.appPrimary : context.appTextSecondary;
    return Pressable(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: ShapeDecoration(
              color: color.withValues(alpha: 0.14),
              shape: AppShape.pill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  required
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Bắt buộc',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
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

class _CategoryPickerTile extends StatelessWidget {
  final List<ChecklistCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  const _CategoryPickerTile({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    ChecklistCategory? selected;
    for (final category in categories) {
      if (category.id == selectedId) {
        selected = category;
        break;
      }
    }
    return AppListTile(
      icon: selected == null
          ? Icons.category_rounded
          : ChecklistCategory.iconFor(selected.icon),
      iconColor: selected?.color ?? AppColors.tagSlate,
      title: 'Danh mục',
      value: selected?.name ?? 'Chưa phân loại',
      onTap: () async {
        final picked = await showChecklistCategorySheet(
          context,
          categories: categories,
          selectedId: selectedId,
        );
        if (picked == null) return;
        final next = picked == kUncategorizedCategory ? null : picked;
        if (next != selectedId) onSelected(next);
      },
    );
  }
}
