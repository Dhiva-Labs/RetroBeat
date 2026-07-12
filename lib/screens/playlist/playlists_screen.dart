import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/add_songs_sheet.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_room.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/song_tile.dart';
import '../../data/models/song_model.dart';
import '../../providers/audio_provider.dart';
import '../../providers/playlist_provider.dart';

/// The Playlists tab.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final playlists = ref.watch(playlistsProvider);

    return Column(
      children: [
        ListTile(
          onTap: () => _showCreateDialog(context, ref),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add_rounded, color: scheme.primary),
          ),
          title: Text(
            'New playlist',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (playlists.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.queue_music_rounded,
              message: 'No playlists yet.',
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          _PlaylistDetailScreen(playlistId: playlist.id),
                    ),
                  ),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.queue_music_rounded,
                      color: scheme.outline,
                    ),
                  ),
                  title: Text(playlist.name),
                  subtitle: Text(
                    '${playlist.songCount} song'
                    '${playlist.songCount == 1 ? '' : 's'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: scheme.outline,
                    ),
                    onSelected: (value) {
                      if (value == 'delete') {
                        ref
                            .read(playlistsProvider.notifier)
                            .deletePlaylist(playlist.id);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              ref.read(playlistsProvider.notifier).createPlaylist(name: name);
              Navigator.pop(dialogContext);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _PlaylistDetailScreen extends ConsumerWidget {
  const _PlaylistDetailScreen({required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref
        .watch(playlistsProvider)
        .where((p) => p.id == playlistId)
        .firstOrNull;

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.error_outline_rounded,
          message: 'This playlist no longer exists.',
        ),
      );
    }

    final allSongs = ref.watch(songsProvider);
    // Ordered by the playlist's own song order, not the library's.
    final songs = [
      for (final id in playlist.songIds) ...allSongs.where((s) => s.id == id),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _addSongs(
              context,
              ref,
              playlist.name,
              allSongs,
              playlist.songIds,
            ),
          ),
        ],
      ),
      floatingActionButton: songs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => playSongs(ref, songs, 0),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
            ),
      body: songs.isEmpty
          ? EmptyState(
              illustration: const EmptyRoom(),
              message: 'Empty for now.\nAdd a song to fill this space.',
              action: FilledButton.icon(
                onPressed: () => _addSongs(
                  context,
                  ref,
                  playlist.name,
                  allSongs,
                  playlist.songIds,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add songs'),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: songs.length,
              onReorderItem: (oldIndex, newIndex) => ref
                  .read(playlistsProvider.notifier)
                  .reorderSongs(playlistId, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final song = songs[index];
                return ListTile(
                  key: ValueKey(song.id),
                  onTap: () => playSongs(ref, songs, index),
                  leading: Artwork(id: song.id),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () => ref
                            .read(playlistsProvider.notifier)
                            .removeSongFromPlaylist(playlistId, song.id),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _addSongs(
    BuildContext context,
    WidgetRef ref,
    String playlistName,
    List<SongModel> allSongs,
    List<int> existingIds,
  ) {
    final available =
        allSongs.where((s) => !existingIds.contains(s.id)).toList();

    showAddSongsSheet(
      context,
      available: available,
      emptyMessage: 'Every song is already in this playlist.',
      containerName: playlistName,
      onAdd: (song) => ref
          .read(playlistsProvider.notifier)
          .addSongToPlaylist(playlistId, song.id),
    );
  }
}
