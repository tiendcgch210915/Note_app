import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/notes_repository.dart';
import '../../models/note.dart';
import '../../theme/app_colors.dart';
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
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  String _query = '';
  List<Note> _notes = [];
  String? _nextCursor;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _fetch(initial: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollCtrl.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _nextCursor != null) {
      _fetch(initial: false);
    }
  }

  Future<void> _fetch({required bool initial}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final resp = await NotesRepository.instance.list(
        q: _query.isEmpty ? null : _query,
        cursor: initial ? null : _nextCursor,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        if (initial) {
          _notes = resp.items;
        } else {
          _notes = [..._notes, ...resp.items];
        }
        _nextCursor = resp.nextCursor;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.vnMessage);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _query = v.trim());
      _fetch(initial: true);
    });
  }

  Future<void> _refresh() => _fetch(initial: true);

  /// Sort: pinned first khi không search.
  List<Note> get _sortedNotes {
    if (_query.isNotEmpty) return _notes;
    final sorted = List.of(_notes);
    sorted.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.noteBackgroundDark : AppColors.noteBackground;
    final notes = _sortedNotes;

    return Container(
      color: bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: const [
                Text(
                  'Notes',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Tìm note',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _buildBody(notes)),
        ],
      ),
    );
  }

  Widget _buildBody(List<Note> notes) {
    if (_loading && notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && notes.isEmpty) {
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
    if (notes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
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
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: notes.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) {
          if (i >= notes.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final n = notes[i];
          return NoteCard(
            note: n,
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NoteDetailScreen(noteId: n.id),
                ),
              );
              if (mounted) _refresh();
            },
          );
        },
      ),
    );
  }
}
