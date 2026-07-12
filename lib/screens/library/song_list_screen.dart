import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/artwork.dart';
import '../../core/widgets/song_tile.dart';
import '../../data/models/song_model.dart';

/// The songs inside one album, artist or genre.
///
/// Shared by every browse tab so that drilling into an album and drilling into
/// an artist behave the same way.
class SongListScreen extends ConsumerWidget {
  const SongListScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.songs,
    required this.artworkSongId,
  });

  final String title;
  final String subtitle;
  final List<SongModel> songs;
  final int artworkSongId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.only(top: 72, bottom: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Artwork(id: artworkSongId, size: 148, radius: 16),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => playSongs(ref, songs, 0),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shuffle(ref),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => SongTile(
                song: songs[index],
                onTap: () => playSongs(ref, songs, index),
              ),
              childCount: songs.length,
            ),
          ),
          // Clear the mini player.
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  void _shuffle(WidgetRef ref) {
    final shuffled = [...songs]..shuffle();
    playSongs(ref, shuffled, 0);
  }
}
