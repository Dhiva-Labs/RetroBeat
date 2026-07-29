import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/folder_utils.dart';
import '../../core/utils/platform_info.dart';
import '../../core/widgets/empty_state.dart';
import '../../providers/audio_provider.dart';
import '../../providers/folders_provider.dart';

/// Lets the user leave specific folders out of their library — the WhatsApp
/// voice-notes folder, a ringtone pack, whatever showed up that isn't music.
///
/// The list comes from [knownFoldersProvider], which is every folder the last
/// scan found, including ones already excluded — a folder that disappeared
/// the moment you turned it off would be impossible to turn back on.
///
/// There is no MediaStore to enumerate on desktop, so there this screen is
/// repurposed into the opposite model: [_DesktopFoldersScreen] picks folders
/// *in* rather than excluding them from a system-wide list.
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (PlatformInfo.isDesktop) return const _DesktopFoldersScreen();

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

/// The desktop scan-folder manager: pick folders in, rather than exclude them
/// from a MediaStore listing that does not exist here.
class _DesktopFoldersScreen extends ConsumerWidget {
  const _DesktopFoldersScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final folders = ref.watch(desktopScanFoldersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Folders'),
        actions: [
          IconButton(
            tooltip: 'Add folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _addFolder(context, ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: folders.isEmpty
          ? EmptyState(
              icon: Icons.folder_off_outlined,
              message: 'No folders yet.\nAdd one to build your library.',
              action: FilledButton.icon(
                onPressed: () => _addFolder(context, ref),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add folder'),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text(
                    'Music is scanned from these folders, recursively.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                for (final folder in folders)
                  ListTile(
                    leading: Icon(
                      Icons.folder_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      folderLeafName(folder),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => _removeFolder(context, ref, folder),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Future<void> _addFolder(BuildContext context, WidgetRef ref) async {
    final path = await getDirectoryPath();
    if (path == null) return;
    await ref.read(desktopScanFoldersProvider.notifier).addFolder(path);
    if (!context.mounted) return;
    await ref.read(libraryLoaderProvider).load(prompt: false);
  }

  Future<void> _removeFolder(
    BuildContext context,
    WidgetRef ref,
    String folder,
  ) async {
    await ref.read(desktopScanFoldersProvider.notifier).removeFolder(folder);
    if (!context.mounted) return;
    // A removed folder's songs only actually leave the library once the next
    // scan reconciles the cache against what is left in the folder list.
    await ref.read(libraryLoaderProvider).load(prompt: false);
  }
}
