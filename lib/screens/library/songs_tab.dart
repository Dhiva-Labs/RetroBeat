import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/platform_info.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/song_tile.dart';
import '../../data/services/permission_service.dart';
import '../../providers/audio_provider.dart';
import '../../providers/folders_provider.dart';

/// Every song on the device.
class SongsTab extends ConsumerWidget {
  const SongsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(sortedSongsProvider);
    final isLoading = ref.watch(songsLoadingProvider);

    if (isLoading && songs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (songs.isEmpty) {
      return const _SongsEmptyState();
    }

    return Column(
      children: [
        _ShuffleHeader(count: songs.length),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: songs.length,
            itemBuilder: (context, index) => SongTile(
              song: songs[index],
              onTap: () => playSongs(ref, songs, index),
            ),
          ),
        ),
      ],
    );
  }
}

/// Song count on the left, shuffle-all on the right.
class _ShuffleHeader extends ConsumerWidget {
  const _ShuffleHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Row(
        children: [
          Text(
            '$count song${count == 1 ? '' : 's'}',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              final shuffled = [...ref.read(sortedSongsProvider)]..shuffle();
              playSongs(ref, shuffled, 0);
            },
            icon: const Icon(Icons.shuffle_rounded, size: 18),
            label: const Text('Shuffle'),
          ),
        ],
      ),
    );
  }
}

/// Tells the truth about *why* the list is empty.
///
/// "No songs found" when the real problem is a denied permission blames the
/// user's library for the app's problem, and offers them no way out.
class _SongsEmptyState extends ConsumerWidget {
  const _SongsEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(mediaPermissionProvider);
    final query = ref.watch(searchQueryProvider);

    if (permission != MediaPermissionStatus.granted) {
      final isPermanent = permission == MediaPermissionStatus.permanentlyDenied;
      return EmptyState(
        icon: Icons.lock_outline_rounded,
        message: isPermanent
            ? 'Music access is turned off, so we can\'t see your songs.\n'
                'Turn it on in Settings to get started.'
            : 'We need permission to read the music on your device.',
        action: FilledButton(
          onPressed: () async {
            if (isPermanent) {
              // The system will not prompt again; only Settings can change it.
              await PermissionService.openSettings();
              await ref.read(libraryLoaderProvider).load(prompt: false);
            } else {
              await ref.read(libraryLoaderProvider).load();
            }
          },
          child: Text(isPermanent ? 'Open Settings' : 'Grant access'),
        ),
      );
    }

    if (query.isNotEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        message: 'No songs match "$query"',
      );
    }

    // No MediaStore here — an empty library means no folder has been picked
    // yet (or the ones picked have nothing playable), so the way out is
    // "add a folder", never a permission prompt that does not apply.
    if (PlatformInfo.isDesktop) {
      final hasFolders = ref.watch(desktopScanFoldersProvider).isNotEmpty;
      return EmptyState(
        icon: Icons.create_new_folder_outlined,
        message: hasFolders
            ? 'No music found in the folders you added.'
            : 'No music yet.\nAdd a folder to build your library.',
        action: FilledButton.icon(
          onPressed: () => _addFolder(ref),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Add folder'),
        ),
      );
    }

    return const EmptyState(
      icon: Icons.music_off_rounded,
      message: 'No music found on your device.',
    );
  }

  Future<void> _addFolder(WidgetRef ref) async {
    final path = await getDirectoryPath();
    if (path == null) return;
    await ref.read(desktopScanFoldersProvider.notifier).addFolder(path);
    await ref.read(libraryLoaderProvider).load(prompt: false);
  }
}
