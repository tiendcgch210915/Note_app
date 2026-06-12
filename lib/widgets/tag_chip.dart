import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../utils/featured_todo_tags.dart';

class TodoTagChip extends StatelessWidget {
  final Tag tag;
  final VoidCallback? onDeleted;
  final VoidCallback? onTap;
  final bool compact;

  const TodoTagChip({
    super.key,
    required this.tag,
    this.onDeleted,
    this.onTap,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = tag.color;
    final featured = featuredTodoTagForName(tag.name);
    final text = Text(
      tag.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: compact ? 11 : 12,
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
    final child = Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: EdgeInsets.only(
        left: compact ? 8 : 10,
        right: onDeleted == null ? (compact ? 8 : 10) : 4,
        top: compact ? 3 : 5,
        bottom: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (featured != null) ...[
            Icon(featured.icon, size: compact ? 13 : 15, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(child: text),
          if (onDeleted != null) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: onDeleted,
              customBorder: const CircleBorder(),
              child: Icon(Icons.close, size: compact ? 14 : 16, color: color),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: child,
    );
  }
}

class TodoTagWrap extends StatelessWidget {
  final List<Tag> tags;
  final void Function(Tag tag)? onDeleted;
  final bool compact;

  const TodoTagWrap({
    super.key,
    required this.tags,
    this.onDeleted,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          TodoTagChip(
            tag: tag,
            compact: compact,
            onDeleted: onDeleted == null ? null : () => onDeleted!(tag),
          ),
      ],
    );
  }
}
