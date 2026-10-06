import 'dart:async';

import 'package:flutter/material.dart';

import '../data/notes_repository.dart';
import '../data/tags_repository.dart';
import '../data/todos_repository.dart';
import '../models/note.dart';
import '../models/tag.dart';
import '../models/todo.dart';
import '../theme/app_colors.dart';

Future<List<Tag>?> showNoteTagSelector(
  BuildContext context, {
  required List<Tag> selected,
}) {
  return showModalBottomSheet<List<Tag>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NoteTagSelector(selected: selected),
  );
}

Future<Note?> showNotePicker(
  BuildContext context, {
  required String excludeId,
  required Set<String> excludedIds,
}) {
  return showModalBottomSheet<Note>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NotePicker(excludeId: excludeId, excludedIds: excludedIds),
  );
}

Future<Todo?> showNoteTodoPicker(
  BuildContext context, {
  required Set<String> excludedIds,
}) {
  return showModalBottomSheet<Todo>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TodoPicker(excludedIds: excludedIds),
  );
}

class _NoteTagSelector extends StatefulWidget {
  const _NoteTagSelector({required this.selected});

  final List<Tag> selected;

  @override
  State<_NoteTagSelector> createState() => _NoteTagSelectorState();
}

class _NoteTagSelectorState extends State<_NoteTagSelector> {
  final _search = TextEditingController();
  final _selected = <String, Tag>{};
  List<Tag> _tags = const [];
  bool _loading = false;

  static const _colors = [
    AppColors.tagIndigo,
    AppColors.tagGreen,
    AppColors.tagAmber,
    AppColors.tagRed,
    AppColors.tagPink,
    AppColors.tagCyan,
    AppColors.tagPurple,
    AppColors.tagSlate,
  ];

  @override
  void initState() {
    super.initState();
    _selected.addEntries(widget.selected.map((tag) => MapEntry(tag.id, tag)));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tags = await TagsRepository.instance.listLocal(
      scope: 'all',
      q: _search.text.trim(),
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final name = _search.text.trim();
    if (name.isEmpty || name.length > 64 || _selected.length >= 20) return;
    final normalized = TagsRepository.normalizeTagName(name).toLowerCase();
    final duplicate = [..._tags, ..._selected.values].any(
      (tag) =>
          TagsRepository.normalizeTagName(tag.name).toLowerCase() == normalized,
    );
    if (duplicate) return;

    final color = await showDialog<Color>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Chọn màu tag'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _colors
                  .map(
                    (color) => InkWell(
                      onTap: () => Navigator.of(context).pop(color),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (color == null) return;
    final tag = await TagsRepository.instance.createLocal(
      name: name,
      color: color,
    );
    if (!mounted) return;
    final mergedTags = {for (final item in _tags) item.id: item};
    mergedTags[tag.id] = tag;
    setState(() {
      _selected[tag.id] = tag;
      _tags = mergedTags.values.toList();
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade500,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => _load(),
                    decoration: const InputDecoration(
                      hintText: 'Tìm hoặc tạo tag',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Tạo tag mới',
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_selected.length}/20 tags'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading && _tags.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: scrollController,
                    itemCount: _tags.length,
                    itemBuilder: (context, index) {
                      final tag = _tags[index];
                      final checked = _selected.containsKey(tag.id);
                      return CheckboxListTile(
                        value: checked,
                        secondary: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: tag.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(tag.name),
                        onChanged: (value) {
                          setState(() {
                            if (value == true && _selected.length < 20) {
                              _selected[tag.id] = tag;
                            } else if (value == false) {
                              _selected.remove(tag.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selected.values.toList()),
                  child: const Text('Áp dụng'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotePicker extends StatefulWidget {
  const _NotePicker({required this.excludeId, required this.excludedIds});

  final String excludeId;
  final Set<String> excludedIds;

  @override
  State<_NotePicker> createState() => _NotePickerState();
}

class _NotePickerState extends State<_NotePicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Note> _notes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final notes = await NotesRepository.instance.listLocal(
      q: _search.text.trim(),
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _notes = notes
          .where(
            (note) =>
                note.id != widget.excludeId &&
                !widget.excludedIds.contains(note.id),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _PickerScaffold(
      title: 'Liên kết note',
      searchController: _search,
      searchHint: 'Tìm note',
      onChanged: (_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), _load);
      },
      child: ListView.builder(
        itemCount: _notes.length,
        itemBuilder: (context, index) {
          final note = _notes[index];
          return ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(note.title),
            subtitle: Text(
              note.previewBody,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).pop(note),
          );
        },
      ),
    );
  }
}

class _TodoPicker extends StatefulWidget {
  const _TodoPicker({required this.excludedIds});

  final Set<String> excludedIds;

  @override
  State<_TodoPicker> createState() => _TodoPickerState();
}

class _TodoPickerState extends State<_TodoPicker> {
  final _search = TextEditingController();
  List<Todo> _todos = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final query = _search.text.trim().toLowerCase();
    final todos = await TodosRepository.instance.listLocal(
      includeArchived: false,
    );
    if (!mounted) return;
    setState(() {
      _todos = todos
          .where(
            (todo) =>
                !widget.excludedIds.contains(todo.id) &&
                (query.isEmpty || todo.title.toLowerCase().contains(query)),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _PickerScaffold(
      title: 'Todo liên quan',
      searchController: _search,
      searchHint: 'Tìm Todo',
      onChanged: (_) => _load(),
      child: ListView.builder(
        itemCount: _todos.length,
        itemBuilder: (context, index) {
          final todo = _todos[index];
          return ListTile(
            leading: Icon(
              todo.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              color: todo.isDone ? AppColors.success : null,
            ),
            title: Text(todo.title),
            subtitle: Text(todo.status.backendValue),
            onTap: () => Navigator.of(context).pop(todo),
          );
        },
      ),
    );
  }
}

class _PickerScaffold extends StatelessWidget {
  const _PickerScaffold({
    required this.title,
    required this.searchController,
    required this.searchHint,
    required this.onChanged,
    required this.child,
  });

  final String title;
  final TextEditingController searchController;
  final String searchHint;
  final ValueChanged<String> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.45,
      builder: (context, _) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade500,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: searchController,
              autofocus: true,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: searchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
