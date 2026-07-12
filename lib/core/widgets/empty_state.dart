import 'package:flutter/material.dart';

/// The one empty-state layout, so "nothing here" always looks deliberate
/// rather than like a screen that failed to load.
///
/// Pass [icon] for the default look, or [illustration] where the emptiness is
/// worth a proper picture (e.g. [EmptyRoom]) rather than a generic glyph.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon,
    this.illustration,
    required this.message,
    this.action,
  }) : assert(
          icon != null || illustration != null,
          'EmptyState needs an icon or an illustration',
        );

  final IconData? icon;
  final Widget? illustration;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            illustration ?? Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
