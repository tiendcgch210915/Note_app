import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/template.dart';
import '../../models/template_item.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
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
  bool _loading = false;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ChecklistsRepository.instance.getTemplate(widget.templateId);
      if (!mounted) return;
      setState(() {
        _template = res.template;
        _items = res.items;
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      await ChecklistsRepository.instance.reorderItems(
        widget.templateId,
        _items.map((i) => i.id).toList(),
      );
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
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

  Future<void> _deleteItem(TemplateItem item) async {
    try {
      await ChecklistsRepository.instance.deleteItem(widget.templateId, item.id);
      setState(() => _items.removeWhere((i) => i.id == item.id));
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
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
    final secondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final template = _template!;
    final canEdit = !template.isSystem;

    return Scaffold(
      appBar: AppBar(
        title: Text(template.title),
        actions: [
          if (canEdit)
            IconButton(
              icon: Icon(_editMode ? Icons.check : Icons.edit_outlined),
              onPressed: () => setState(() => _editMode = !_editMode),
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
                  child: Icon(Template.iconFor(template.icon), color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(template.title,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      if (template.description != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(template.description!,
                              style: TextStyle(fontSize: 13, color: secondary)),
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
                _chip('Dùng ${template.timesUsed} lần'),
                if (template.lastUsedAt != null)
                  _chip('Cập nhật: ${AppDateUtils.formatRelative(template.lastUsedAt!)}'),
              ],
            ),
          ),
          const SectionHeader(label: 'Các bước'),
          if (_editMode) _editList(secondary) else _readList(secondary),
          if (_editMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: const Text('Thêm bước'),
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
            child: Text('${it.position}',
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          title: Text(it.title),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (it.isRequired ? AppColors.danger : secondary).withValues(alpha: 0.15),
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
              Expanded(child: Text(it.title)),
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
      child: Text(label,
          style: const TextStyle(
              fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
    );
  }
}
