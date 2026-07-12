import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/song_model.dart';
import 'audio_provider.dart';

/// A browsable collection of songs — one album, artist or genre.
class LibraryGroup {
  const LibraryGroup({
    required this.name,
    required this.songs,
    required this.subtitle,
  });

  final String name;
  final List<SongModel> songs;
  final String subtitle;

  /// A track to pull cover art from. Albums share art, so any member works.
  int get artworkSongId => songs.first.id;
}

List<LibraryGroup> _groupBy(
  List<SongModel> songs,
  String Function(SongModel) key,
  String Function(String name, List<SongModel> members) subtitle,
) {
  final buckets = <String, List<SongModel>>{};
  for (final song in songs) {
    buckets.putIfAbsent(key(song), () => []).add(song);
  }

  final groups = buckets.entries
      .map(
        (e) => LibraryGroup(
          name: e.key,
          songs: e.value,
          subtitle: subtitle(e.key, e.value),
        ),
      )
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return groups;
}

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

final albumsProvider = Provider<List<LibraryGroup>>((ref) {
  final songs = ref.watch(sortedSongsProvider);
  return _groupBy(
    songs,
    (s) => s.album,
    // An album's most useful second line is who made it, not how long it is.
    (_, members) => members.first.artist,
  );
});

final artistsProvider = Provider<List<LibraryGroup>>((ref) {
  final songs = ref.watch(sortedSongsProvider);
  return _groupBy(
    songs,
    (s) => s.artist,
    (_, members) {
      final albums = members.map((s) => s.album).toSet().length;
      return '${_plural(albums, 'album')} · ${_plural(members.length, 'song')}';
    },
  );
});

final genresProvider = Provider<List<LibraryGroup>>((ref) {
  final songs =
      ref.watch(sortedSongsProvider).where((s) => s.genre != 'Unknown');
  return _groupBy(
    songs.toList(),
    (s) => s.genre,
    (_, members) => _plural(members.length, 'song'),
  );
});

/// Songs the user has hearted. Backs the Liked tab.
final likedSongsProvider = Provider<List<SongModel>>((ref) {
  return ref.watch(sortedSongsProvider).where((s) => s.isFavorite).toList();
});
