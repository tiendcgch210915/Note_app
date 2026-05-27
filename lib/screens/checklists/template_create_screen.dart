import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
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
  final String _category = 'personal';
  final String _iconName = 'checklist';
  bool _saving = false;

  final List<_DraftItem> _items = [
    _DraftItem(title: ''),
    _DraftItem(title: ''),
  ];

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
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
          .map((i) => {
                'title': i.title.trim(),
                'is_required': i.isRequired,
              })
          .toList();
      await ChecklistsRepository.instance.createTemplate(
        title: _title.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        icon: _iconName,
        category: _category,
        items: items,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã tạo template')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.vnMessage), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Lưu',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
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
              ],
            ),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text('Các bước', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                          decoration: InputDecoration(hintText: 'Bước ${i + 1}'),
                        ),
                      ),
                      Checkbox(
                        value: item.isRequired,
                        onChanged: (v) => setState(() => item.isRequired = v ?? true),
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
              child: PrimaryButton(label: 'Tạo template', icon: Icons.check, onPressed: _save),
            ),
          ),
        ],
      ),
    );
  }
}
