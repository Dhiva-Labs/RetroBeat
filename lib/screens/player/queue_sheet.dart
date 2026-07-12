import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/artwork.dart';
import '../../providers/audio_provider.dart';

/// The current play order, reorderable by dragging.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(queueProvider).valueOrNull ?? const <MediaItem>[];
    final current = ref.watch(currentMediaItemProvider).valueOrNull;
    final handler = ref.read(audioHandlerProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Text('Queue', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Text(
                  '${queue.length}',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: scrollController,
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: queue.length,
              onReorderItem: (oldIndex, newIndex) =>
                  handler.moveQueueItem(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final item = queue[index];
                final isCurrent = item.id == current?.id;
                final songId = item.extras?['songId'] as int?;

                return ListTile(
                  key: ValueKey('${item.id}_$index'),
                  onTap: () => handler.skipToQueueItem(index),
                  leading: songId == null
                      ? const SizedBox(width: 44)
                      : Artwork(id: songId, size: 44),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? scheme.primary : scheme.onSurface,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    item.artist ?? 'Unknown Artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: scheme.outline,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
