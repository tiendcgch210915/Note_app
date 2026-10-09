import 'package:flutter/material.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/date_utils.dart';
import 'app_surface.dart';

/// Card note theo style Apple Notes.
class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;

  const NoteCard({super.key, required this.note, this.onTap});

  @override
  Widget build(BuildContext context) {
    final textPrimary = context.appTextPrimary;
    final textSecondary = context.appTextSecondary;

    return AppSurface(
      onTap: onTap,
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  note.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (note.isPinned)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (note.previewBody.isNotEmpty)
            Text(
              note.previewBody,
              style: TextStyle(fontSize: 14, color: textSecondary, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  AppDateUtils.formatRelative(note.updatedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ),
              if (note.type == NoteType.cornell) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: ShapeDecoration(
                    color: context.appPrimarySoft,
                    shape: AppShape.pill,
                  ),
                  child: Text(
                    'Cornell',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.appPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              // Thẻ tag chiếm phần còn lại, tên dài thì cắt "…" thay vì tràn ngang.
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final t in note.tags.take(2))
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: ShapeDecoration(
                              color: t.color.withValues(alpha: 0.15),
                              shape: AppShape.pill,
                            ),
                            child: Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: t.color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
