import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/tag.dart';
import '../theme/app_colors.dart';
import 'section_header.dart';

class NoteRelationsSection extends StatelessWidget {
  const NoteRelationsSection({
    super.key,
    required this.tags,
    required this.outgoing,
    required this.incoming,
    required this.todos,
    required this.onEditTags,
    required this.onAddLink,
    required this.onRemoveLink,
    required this.onOpenNote,
    required this.onAddTodo,
    required this.onRemoveTodo,
    required this.onOpenTodo,
  });

  final List<Tag> tags;
  final List<OutgoingLink> outgoing;
  final List<IncomingLink> incoming;
  final List<LinkedTodo> todos;
  final VoidCallback onEditTags;
  final VoidCallback onAddLink;
  final ValueChanged<OutgoingLink> onRemoveLink;
  final ValueChanged<String> onOpenNote;
  final VoidCallback onAddTodo;
  final ValueChanged<LinkedTodo> onRemoveTodo;
  final ValueChanged<String> onOpenTodo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: 'Tags',
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          trailing: IconButton(
            tooltip: 'Chỉnh sửa tags',
            onPressed: onEditTags,
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
        ),
        if (tags.isEmpty)
          const _EmptyRelation(text: 'Chưa có tag')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (tag) => Chip(
                    avatar: CircleAvatar(backgroundColor: tag.color),
                    label: Text(tag.name),
                  ),
                )
                .toList(),
          ),
        SectionHeader(
          label: 'Liên kết',
          padding: const EdgeInsets.only(top: 20, bottom: 4),
          trailing: IconButton(
            tooltip: 'Thêm liên kết',
            onPressed: onAddLink,
            icon: const Icon(Icons.add_link, size: 20),
          ),
        ),
        if (outgoing.isEmpty)
          const _EmptyRelation(text: 'Chưa liên kết tới note nào')
        else
          ...outgoing.map(
            (link) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_outward, size: 19),
              title: Text(link.targetTitle),
              subtitle: link.label == null ? null : Text(link.label!),
              trailing: IconButton(
                tooltip: 'Gỡ liên kết',
                onPressed: () => onRemoveLink(link),
                icon: const Icon(Icons.link_off, size: 19),
              ),
              onTap: () => onOpenNote(link.targetNoteId),
            ),
          ),
        const SectionHeader(
          label: 'Backlinks',
          padding: EdgeInsets.only(top: 20, bottom: 4),
        ),
        if (incoming.isEmpty)
          const _EmptyRelation(text: 'Chưa có backlink')
        else
          ...incoming.map(
            (link) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.subdirectory_arrow_left, size: 19),
              title: Text(link.sourceTitle),
              subtitle: link.label == null ? null : Text(link.label!),
              onTap: () => onOpenNote(link.sourceNoteId),
            ),
          ),
        SectionHeader(
          label: 'Todos liên quan',
          padding: const EdgeInsets.only(top: 20, bottom: 4),
          trailing: IconButton(
            tooltip: 'Thêm Todo liên quan',
            onPressed: onAddTodo,
            icon: const Icon(Icons.playlist_add, size: 21),
          ),
        ),
        if (todos.isEmpty)
          const _EmptyRelation(text: 'Chưa có Todo liên quan')
        else
          ...todos.map(
            (todo) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                todo.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 19,
                color: todo.isDone ? AppColors.success : null,
              ),
              title: Text(
                todo.title,
                style: TextStyle(
                  decoration: todo.isDone ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(todo.status),
              trailing: IconButton(
                tooltip: 'Gỡ Todo khỏi note',
                onPressed: () => onRemoveTodo(todo),
                icon: const Icon(Icons.link_off, size: 19),
              ),
              onTap: () => onOpenTodo(todo.id),
            ),
          ),
      ],
    );
  }
}

class _EmptyRelation extends StatelessWidget {
  const _EmptyRelation({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: TextStyle(fontSize: 13, color: color)),
    );
  }
}
