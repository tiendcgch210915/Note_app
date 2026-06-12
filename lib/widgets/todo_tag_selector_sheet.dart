import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api_exception.dart';
import '../data/tags_repository.dart';
import '../models/tag.dart';
import '../theme/app_colors.dart';
import '../utils/featured_todo_tags.dart';
import 'tag_chip.dart';

Future<List<Tag>?> showTodoTagSelectorSheet(
  BuildContext context, {
  required List<Tag> initialTags,
}) {
  return showModalBottomSheet<List<Tag>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => TodoTagSelectorSheet(initialTags: initialTags),
  );
}

class TodoTagSelectorSheet extends StatefulWidget {
  final List<Tag> initialTags;

  const TodoTagSelectorSheet({super.key, required this.initialTags});

  @override
  State<TodoTagSelectorSheet> createState() => _TodoTagSelectorSheetState();
}

class _TodoTagSelectorSheetState extends State<TodoTagSelectorSheet> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  List<Tag> _selected = [];
  List<Tag> _items = [];
  bool _loading = false;
  bool _creating = false;
  String? _creatingPresetName;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selected = _dedupe(widget.initialTags);
    _load();
    _search.addListener(_scheduleLoad);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await TagsRepository.instance.list(
        scope: 'todo',
        q: _search.text,
      );
      if (!mounted) return;
      setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _load);
  }

  void _toggle(Tag tag) {
    setState(() {
      if (_selected.any((item) => item.id == tag.id)) {
        _selected = _selected.where((item) => item.id != tag.id).toList();
      } else {
        _selected = [..._selected, tag];
      }
    });
  }

  Future<void> _toggleFeatured(FeaturedTodoTag preset) async {
    if (_creating) return;
    final selected = _selectedTagForPreset(preset);
    if (selected != null) {
      final presetKey = normalizeFeaturedTodoTagName(preset.name);
      setState(() {
        _selected = _selected
            .where((tag) => normalizeFeaturedTodoTagName(tag.name) != presetKey)
            .toList();
      });
      return;
    }

    final existing = _tagForPreset(preset);
    if (existing != null) {
      _toggle(existing);
      return;
    }

    setState(() {
      _creating = true;
      _creatingPresetName = preset.name;
    });
    try {
      final tag = await TagsRepository.instance.create(
        name: preset.name,
        color: preset.color,
      );
      if (!mounted) return;
      setState(() {
        _selected = _dedupe([..._selected, tag]);
        _items = _dedupe([tag, ..._items]);
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
          _creatingPresetName = null;
        });
      }
    }
  }

  Future<void> _createFromSearch() async {
    final name = TagsRepository.normalizeTagName(_search.text);
    if (name.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      final tag = await TagsRepository.instance.create(
        name: name,
        color: _defaultTagColor(name),
      );
      if (!mounted) return;
      setState(() {
        _selected = _dedupe([..._selected, tag]);
        _items = _dedupe([tag, ..._items]);
        _search.clear();
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  bool get _canCreate {
    final name = TagsRepository.normalizeTagName(_search.text);
    if (name.isEmpty) return false;
    return !_items.any(
      (tag) =>
          TagsRepository.normalizeTagName(tag.name).toLowerCase() ==
          name.toLowerCase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Tags',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(() => _selected = []),
                    child: const Text('Xóa hết'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                focusNode: _focus,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Tìm hoặc tạo tag',
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  if (_canCreate) _createFromSearch();
                },
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 12),
                TodoTagWrap(
                  tags: _selected,
                  compact: false,
                  onDeleted: (tag) => _toggle(tag),
                ),
              ],
              const SizedBox(height: 12),
              if (_canCreate)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _creating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_circle_outline),
                  title: Text(
                    'Tạo "${TagsRepository.normalizeTagName(_search.text)}"',
                  ),
                  onTap: _creating ? null : _createFromSearch,
                ),
              const Text(
                'Nổi bật',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in featuredTodoTags)
                    _FeaturedTagButton(
                      preset: preset,
                      selected: _selectedTagForPreset(preset) != null,
                      loading: _creatingPresetName == preset.name,
                      onTap: () => _toggleFeatured(preset),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading && _items.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _normalItems.isEmpty
                    ? Center(
                        child: Text(
                          'Chưa có tag khác',
                          style: TextStyle(color: secondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _normalItems.length,
                        itemBuilder: (ctx, index) {
                          final tag = _normalItems[index];
                          final selected = _selected.any(
                            (item) => item.id == tag.id,
                          );
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (_) => _toggle(tag),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            title: Row(
                              children: [
                                Expanded(
                                  child: TodoTagChip(
                                    tag: tag,
                                    compact: false,
                                    onTap: () => _toggle(tag),
                                  ),
                                ),
                                if (tag.usageCount != null)
                                  Text(
                                    '${tag.usageCount}',
                                    style: TextStyle(color: secondary),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  icon: const Icon(Icons.check),
                  label: const Text('Áp dụng'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  List<Tag> _dedupe(List<Tag> tags) {
    final seen = <String>{};
    final result = <Tag>[];
    for (final tag in tags) {
      if (seen.contains(tag.id)) continue;
      seen.add(tag.id);
      result.add(tag);
    }
    return result;
  }

  List<Tag> get _normalItems {
    final featuredNames = featuredTodoTags
        .map((tag) => normalizeFeaturedTodoTagName(tag.name))
        .toSet();
    return _items
        .where(
          (tag) =>
              !featuredNames.contains(normalizeFeaturedTodoTagName(tag.name)),
        )
        .toList(growable: false);
  }

  Tag? _tagForPreset(FeaturedTodoTag preset) {
    final presetKey = normalizeFeaturedTodoTagName(preset.name);
    for (final tag in _items) {
      if (normalizeFeaturedTodoTagName(tag.name) == presetKey) return tag;
    }
    return null;
  }

  Tag? _selectedTagForPreset(FeaturedTodoTag preset) {
    final presetKey = normalizeFeaturedTodoTagName(preset.name);
    for (final tag in _selected) {
      if (normalizeFeaturedTodoTagName(tag.name) == presetKey) return tag;
    }
    return null;
  }

  Color _defaultTagColor(String name) {
    const colors = [
      AppColors.tagIndigo,
      AppColors.tagGreen,
      AppColors.tagAmber,
      AppColors.tagRed,
      AppColors.tagPink,
      AppColors.tagCyan,
      AppColors.tagPurple,
      AppColors.tagSlate,
    ];
    final index =
        name.runes.fold<int>(0, (sum, rune) => sum + rune) % colors.length;
    return colors[index];
  }
}

class _FeaturedTagButton extends StatelessWidget {
  final FeaturedTodoTag preset;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;

  const _FeaturedTagButton({
    required this.preset,
    required this.selected,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: FilterChip(
        selected: selected,
        onSelected: loading ? null : (_) => onTap(),
        avatar: loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: preset.color,
                ),
              )
            : Icon(preset.icon, size: 16, color: preset.color),
        label: Text(preset.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        labelStyle: TextStyle(
          color: selected ? preset.color : null,
          fontWeight: FontWeight.w700,
        ),
        selectedColor: preset.color.withValues(alpha: 0.16),
        checkmarkColor: preset.color,
        side: BorderSide(color: preset.color.withValues(alpha: 0.28)),
      ),
    );
  }
}
