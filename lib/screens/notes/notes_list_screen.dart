import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api_exception.dart';
import '../../data/notes_repository.dart';
import '../../models/note.dart';
import '../../theme/app_colors.dart';
import '../../utils/note_local_events.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/note_card.dart';
import 'note_detail_screen.dart';

class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key});

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  final _search = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  List<Note> _notes = const [];
  String _query = '';
  NoteType? _type;
  String? _nextCursor;
  String? _error;
  bool _loading = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    NoteLocalEvents.instance.addListener(_handleLocalChanged);
    unawaited(_loadLocal());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    NoteLocalEvents.instance.removeListener(_handleLocalChanged);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _handleLocalChanged() => unawaited(_loadLocal());

  void _handleScroll() {
    if (_nextCursor == null || _loadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadLocal() async {
    final notes = await NotesRepository.instance.listLocal(
      limit: 500,
      q: _query,
      type: _type?.backendValue,
    );
    if (!mounted) return;
    setState(() => _notes = notes);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await NotesRepository.instance.refreshList(
        limit: 20,
        q: _query,
        type: _type?.backendValue,
      );
      if (!mounted) return;
      _nextCursor = result.nextCursor;
      await _loadLocal();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final result = await NotesRepository.instance.refreshList(
        cursor: cursor,
        limit: 20,
        q: _query,
        type: _type?.backendValue,
      );
      _nextCursor = result.nextCursor;
      await _loadLocal();
    } on ApiException catch (error) {
      if (mounted && _notes.isEmpty) setState(() => _error = error.vnMessage);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _handleSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _query = value.trim();
      unawaited(_loadLocal());
      unawaited(_refresh());
    });
  }

  void _selectType(NoteType? type) {
    if (_type == type) return;
    setState(() => _type = type);
    unawaited(_loadLocal());
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? AppColors.noteBackgroundDark
        : AppColors.noteBackground;
    return ColoredBox(
      color: background,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Notes',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _search,
              onChanged: _handleSearch,
              decoration: const InputDecoration(
                hintText: 'Tìm trong Notes',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Tất cả')),
                ButtonSegment(value: 'free', label: Text('Thường')),
                ButtonSegment(value: 'cornell', label: Text('Cornell')),
              ],
              selected: {_type?.backendValue ?? 'all'},
              onSelectionChanged: (selection) {
                final value = selection.first;
                _selectType(value == 'all' ? null : NoteType.parse(value));
              },
            ),
          ),
          if (_loading && _notes.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notes.isEmpty && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _refresh, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }
    if (_notes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            SizedBox(height: 110),
            EmptyState(
              icon: Icons.sticky_note_2_outlined,
              title: 'Chưa có note nào',
              subtitle: 'Bấm dấu cộng để tạo note đầu tiên.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        itemCount: _notes.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _notes.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final note = _notes[index];
          return NoteCard(
            note: note,
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NoteDetailScreen(noteId: note.id),
                ),
              );
              await _loadLocal();
            },
          );
        },
      ),
    );
  }
}
