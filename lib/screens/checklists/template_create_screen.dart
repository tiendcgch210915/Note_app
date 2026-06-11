import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/checklist_category.dart';
import '../../theme/app_colors.dart';
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
  final _desc = TextEditingController();
  final String _iconName = 'checklist';
  List<ChecklistCategory> _categories = [];
  String? _categoryId;
  bool _saving = false;

  final List<_DraftItem> _items = [
    _DraftItem(title: ''),
    _DraftItem(title: ''),
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
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
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
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
    } finally {
      if (mounted) setState(() => _saving = false);
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
                TextField(
                  controller: _desc,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Mô tả'),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(
                  'Các bước',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _items.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _items.removeAt(oldIndex);
                  _items.insert(newIndex, item);
                });
              },
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
                          initialValue: item.title,
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
                        onPressed: () => setState(() => _items.removeAt(i)),
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
              onPressed: () => setState(() => _items.add(_DraftItem())),
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
