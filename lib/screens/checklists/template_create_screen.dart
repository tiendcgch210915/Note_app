import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/checklist_category.dart';
import '../../theme/app_colors.dart';
import '../../utils/checklist_step_text_utils.dart';
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
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên template')),
      );
      return;
    }
    final validItems = _items.where((i) => i.title.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập ít nhất 1 bước')),
      );
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
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã tạo template')));
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
    final ctrl = TextEditingController(text: clipboard?.text ?? '');
    final raw = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dán nhiều bước',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    hintText: 'Mỗi dòng là một bước',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                    icon: const Icon(Icons.content_paste_go_outlined),
                    label: const Text('Thêm vào checklist'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    if (raw == null) return;
    _insertPastedSteps(parseChecklistStepLines(raw));
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Template mới'),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(hintText: 'Tên template'),
                ),
                const SizedBox(height: 12),
                _CategoryPickerTile(
                  categories: _categories,
                  selectedId: _categoryId,
                  onSelected: (id) => setState(() => _categoryId = id),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Text(
                  'Các bước',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showPasteStepsSheet,
                  icon: const Icon(Icons.content_paste_outlined, size: 18),
                  label: const Text('Dán bước'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _items.length,
              onReorder: _reorderSteps,
              itemBuilder: (ctx, i) {
                final item = _items[i];
                return Padding(
                  key: ValueKey(item),
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ),
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
                        child: TextFormField(
                          controller: _itemControllers[i],
                          focusNode: _itemFocusNodes[i],
                          onChanged: (v) => item.title = v,
                          decoration: InputDecoration(
                            hintText: 'Bước ${i + 1}',
                          ),
                        ),
                      ),
                      Checkbox(
                        value: item.isRequired,
                        onChanged: (v) =>
                            setState(() => item.isRequired = v ?? true),
                      ),
                      const Text('Bắt buộc', style: TextStyle(fontSize: 12)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _removeStep(i),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _addStep,
              icon: const Icon(Icons.add),
              label: const Text('Thêm bước'),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PrimaryButton(
                label: 'Tạo template',
                icon: Icons.check,
                onPressed: _save,
              ),
            ),
          ),
        ],
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected == null
            ? Icons.category_outlined
            : ChecklistCategory.iconFor(selected.icon),
        color: selected?.color ?? AppColors.textSecondary,
      ),
      title: const Text('Danh mục'),
      subtitle: Text(selected?.name ?? 'Chưa phân loại'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
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
                  trailing: selectedId == null
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.of(ctx).pop('__uncategorized__'),
                ),
                ...categories.map(
                  (category) => ListTile(
                    title: Text(category.name),
                    subtitle: category.isSystem
                        ? const Text('Hệ thống')
                        : const Text('Của tôi'),
                    leading: Icon(
                      ChecklistCategory.iconFor(category.icon),
                      color: category.color,
                    ),
                    trailing: selectedId == category.id
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
        final next = picked == '__uncategorized__' ? null : picked;
        if (next != selectedId) onSelected(next);
      },
    );
  }
}
