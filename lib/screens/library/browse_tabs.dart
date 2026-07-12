import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/song_tile.dart';
import '../../providers/library_provider.dart';
import 'song_list_screen.dart';

void _openGroup(BuildContext context, LibraryGroup group) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SongListScreen(
        title: group.name,
        subtitle: group.subtitle,
        songs: group.songs,
        artworkSongId: group.artworkSongId,
      ),
    ),
  );
}

/// Albums, as a grid — cover art is the whole point of an album, so it gets the
/// space. Artists and genres are lists, where the name is what you scan for.
class AlbumsTab extends ConsumerWidget {
  const AlbumsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);

    if (albums.isEmpty) {
      return const EmptyState(
        icon: Icons.album_outlined,
        message: 'No albums yet.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
        childAspectRatio: 0.78,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return _AlbumCard(album: album);
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final LibraryGroup album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _openGroup(context, album),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Artwork(
                id: album.artworkSongId,
                size: constraints.maxWidth,
                radius: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 2),
          Text(
            album.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class ArtistsTab extends ConsumerWidget {
  const ArtistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);

    if (artists.isEmpty) {
      return const EmptyState(
        icon: Icons.person_outline_rounded,
        message: 'No artists yet.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ListTile(
          onTap: () => _openGroup(context, artist),
          leading: ClipOval(
            child: Artwork(id: artist.artworkSongId, radius: 24),
          ),
          title:
              Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(artist.subtitle),
        );
      },
    );
  }
}

class GenresTab extends ConsumerWidget {
  const GenresTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genresProvider);

    if (genres.isEmpty) {
      return const EmptyState(
        icon: Icons.category_outlined,
        message: 'None of your songs are tagged with a genre.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      itemCount: genres.length,
      itemBuilder: (context, index) {
        final genre = genres[index];
        return ListTile(
          onTap: () => _openGroup(context, genre),
          leading: Artwork(id: genre.artworkSongId),
          title: Text(genre.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(genre.subtitle),
        );
      },
    );
  }
}

class LikedTab extends ConsumerWidget {
  const LikedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(likedSongsProvider);

    if (songs.isEmpty) {
      return const EmptyState(
        icon: Icons.favorite_border_rounded,
        message: 'Songs you like will show up here.\n'
            'Tap the ⋮ on any song to add one.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      itemCount: songs.length,
      itemBuilder: (context, index) => SongTile(
        song: songs[index],
        onTap: () => playSongs(ref, songs, index),
      ),
    );
  }
}
