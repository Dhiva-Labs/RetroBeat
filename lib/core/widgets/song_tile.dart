import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/song_model.dart';
import '../../data/repositories/media_repository.dart';
import '../../providers/audio_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/playlist_provider.dart';
import '../utils/duration_formatter.dart';
import 'artwork.dart';

/// Start [songs] playing from [index], making that list the queue.
void playSongs(WidgetRef ref, List<SongModel> songs, int index) {
  if (songs.isEmpty) return;
  final handler = ref.read(audioHandlerProvider);
  handler.loadPlaylist(
    songs.map(MediaRepository.songToMediaItem).toList(),
    initialIndex: index,
  );
  handler.play();
  ref.read(mediaRepositoryProvider).incrementPlayCount(songs[index].id);
}

/// One row in any song list. Shared so the Tracks tab, an album and a playlist
/// all offer the same actions and the same now-playing highlight.
class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
  });

  final SongModel song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currentId =
        ref.watch(currentMediaItemProvider).valueOrNull?.extras?['songId'];
    final isPlaying = currentId == song.id;

    return ListTile(
      onTap: onTap,
      leading: Artwork(id: song.id),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          // The playing track is the only row that takes the accent.
          color: isPlaying ? scheme.primary : scheme.onSurface,
          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${song.artist}  ·  ${formatMilliseconds(song.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song.isFavorite)
            Icon(Icons.favorite_rounded, size: 16, color: scheme.primary),
          _SongMenu(song: song),
        ],
      ),
    );
  }
}

class _SongMenu extends ConsumerWidget {
  const _SongMenu({required this.song});

  final SongModel song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        color: Theme.of(context).colorScheme.outline,
      ),
      onSelected: (value) => _onSelected(context, ref, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              Icon(
                song.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(song.isFavorite ? 'Remove from Liked' : 'Add to Liked'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'add_to_playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_add_rounded, size: 20),
              SizedBox(width: 12),
              Text('Add to Playlist'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'add_to_group',
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 20),
              SizedBox(width: 12),
              Text('Add to Group'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    switch (value) {
      case 'favorite':
        final wasFavorite = song.isFavorite;
        await ref.read(mediaRepositoryProvider).toggleFavorite(song.id);
        // SongModel is a HiveObject mutated in place, so the list identity has
        // to change for Riverpod to rebuild.
        ref.read(songsProvider.notifier).state =
            List<SongModel>.from(ref.read(songsProvider));
        if (!context.mounted) return;
        _notify(context, wasFavorite ? 'Removed from Liked' : 'Added to Liked');

      case 'add_to_playlist':
        final playlists = ref.read(playlistsProvider);
        if (playlists.isEmpty) {
          _notify(context, 'Create a playlist first');
          return;
        }
        final choice = await _pick(
          context,
          title: 'Add to Playlist',
          options: {for (final p in playlists) p.id: p.name},
        );
        if (choice == null || !context.mounted) return;
        await ref
            .read(playlistsProvider.notifier)
            .addSongToPlaylist(choice, song.id);
        if (!context.mounted) return;
        _notify(context, 'Added to playlist');

      case 'add_to_group':
        final groups = ref.read(groupsProvider);
        if (groups.isEmpty) {
          _notify(context, 'Create a group first');
          return;
        }
        final choice = await _pick(
          context,
          title: 'Add to Group',
          options: {for (final g in groups) g.id: '${g.emoji}   ${g.name}'},
        );
        if (choice == null || !context.mounted) return;
        await ref.read(groupsProvider.notifier).addSongToGroup(choice, song.id);
        if (!context.mounted) return;
        _notify(context, 'Added to group');
    }
  }

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Sheet listing [options] (id -> label); resolves to the chosen id.
  Future<String?> _pick(
    BuildContext context, {
    required String title,
    required Map<String, String> options,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: options.entries
                    .map(
                      (entry) => ListTile(
                        title: Text(entry.value),
                        onTap: () => Navigator.pop(sheetContext, entry.key),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
