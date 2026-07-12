import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/folder_utils.dart';
import '../../core/widgets/empty_state.dart';
import '../../providers/audio_provider.dart';
import '../../providers/folders_provider.dart';

/// Lets the user leave specific folders out of their library — the WhatsApp
/// voice-notes folder, a ringtone pack, whatever showed up that isn't music.
///
/// The list comes from [knownFoldersProvider], which is every folder the last
/// scan found, including ones already excluded — a folder that disappeared
/// the moment you turned it off would be impossible to turn back on.
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final folders = ref.watch(knownFoldersProvider);
    final excluded = ref.watch(excludedFoldersProvider);

    final sorted = folders.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      body: sorted.isEmpty
          ? const EmptyState(
              icon: Icons.folder_off_outlined,
              message: 'Scan your library first — folders show up here once '
                  'there is something to exclude.',
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text(
                    'Turn off a folder to leave it out of your library. It '
                    'stays out until you turn it back on here.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                for (final entry in sorted)
                  SwitchListTile(
                    secondary: Icon(
                      excluded.contains(entry.key)
                          ? Icons.folder_off_outlined
                          : Icons.folder_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      folderLeafName(entry.key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${folderParentLabel(entry.key)} · '
                      '${entry.value} song${entry.value == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: !excluded.contains(entry.key),
                    onChanged: (include) => _setIncluded(
                      ref,
                      entry.key,
                      include,
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Future<void> _setIncluded(WidgetRef ref, String folder, bool include) async {
    await ref
        .read(excludedFoldersProvider.notifier)
        .setExcluded(folder, !include);
    // Apply immediately: exclusion is enforced during a scan, not by hiding
    // rows client-side, so the change needs a rescan to actually take effect.
    await ref.read(libraryLoaderProvider).load(prompt: false);
  }
}
