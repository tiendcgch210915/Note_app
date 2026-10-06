import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class CornellNoteLayout extends StatelessWidget {
  const CornellNoteLayout({
    super.key,
    required this.notes,
    required this.cues,
    required this.summary,
  });

  final Widget notes;
  final Widget cues;
  final Widget summary;

  static const wideBreakpoint = 680.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < wideBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: const ValueKey('cornell-notes-section'),
                child: _Section(label: 'Notes', child: notes),
              ),
              const SizedBox(height: 20),
              KeyedSubtree(
                key: const ValueKey('cornell-cues-section'),
                child: _Section(label: 'Cues', child: cues),
              ),
              const SizedBox(height: 20),
              KeyedSubtree(
                key: const ValueKey('cornell-summary-section'),
                child: _Section(label: 'Summary', child: summary),
              ),
            ],
          );
        }

        final divider = Theme.of(context).brightness == Brightness.dark
            ? AppColors.dividerDark
            : AppColors.divider;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: KeyedSubtree(
                        key: const ValueKey('cornell-cues-section'),
                        child: _Section(
                          label: 'Cues',
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 320),
                            child: cues,
                          ),
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: divider),
                  Expanded(
                    flex: 7,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: KeyedSubtree(
                        key: const ValueKey('cornell-notes-section'),
                        child: _Section(
                          label: 'Notes',
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 320),
                            child: notes,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Divider(height: 1, color: divider),
            ),
            KeyedSubtree(
              key: const ValueKey('cornell-summary-section'),
              child: _Section(label: 'Summary', child: summary),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
