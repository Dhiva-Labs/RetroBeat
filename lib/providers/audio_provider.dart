import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/platform_info.dart';
import '../core/utils/stable_id.dart';
import '../data/models/song_model.dart';
import '../data/repositories/media_repository.dart';
import '../data/services/audio_handler.dart';
import '../data/services/permission_service.dart';
import 'folders_provider.dart';
import 'server_providers.dart';
import 'settings_provider.dart';

/// Provider for the AudioHandler singleton
final audioHandlerProvider = Provider<RetroBeatAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden');
});

/// Provider for player state
final playerStateProvider = StreamProvider<PlaybackState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playbackState;
});

/// Provider for current media item
final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.mediaItem;
});

/// Provider for position data
final positionDataProvider = StreamProvider<PositionData>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.positionDataStream;
});

/// Provider for the queue
final queueProvider = StreamProvider<List<MediaItem>>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.queue;
});

/// Provider for the current playing song's model
final currentSongProvider = Provider<SongModel?>((ref) {
  final mediaItem = ref.watch(currentMediaItemProvider).valueOrNull;
  if (mediaItem == null) return null;

  final songId = mediaItem.extras?['songId'] as int?;
  if (songId == null) {
    // A remote (WebDAV) track has no library row to look up — display it
    // straight from the MediaItem instead of disappearing. See
    // isRemotePlaybackProvider for the flag this same check drives.
    return _remoteDisplaySong(mediaItem);
  }

  final songs = ref.watch(songsProvider);
  try {
    return songs.firstWhere((s) => s.id == songId);
  } catch (e) {
    return null;
  }
});

/// True while the playing item has no local library id — a remote WebDAV
/// track, currently. Lets a control that only makes sense against the
/// library (favoriting, in NowPlayingScreen) hide itself rather than tap and
/// do nothing.
final isRemotePlaybackProvider = Provider<bool>((ref) {
  final mediaItem = ref.watch(currentMediaItemProvider).valueOrNull;
  return mediaItem != null && mediaItem.extras?['songId'] == null;
});

/// A display-only stand-in for a [MediaItem] with no library row. Never
/// written to Hive: the id only has to be stable enough for [Artwork]'s
/// per-id cache lookup to consistently miss and fall back to the placeholder,
/// which is exactly what happens since nothing ever caches art under it.
SongModel _remoteDisplaySong(MediaItem item) {
  return SongModel(
    id: stableIdFor(item.id),
    title: item.title,
    artist: item.artist ?? 'Unknown Artist',
    album: item.album ?? 'Unknown Album',
    uri: item.id,
    duration: item.duration?.inMilliseconds ?? 0,
  );
}

/// Provider for is playing state
final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(playerStateProvider).valueOrNull?.playing ?? false;
});

/// Provider for shuffle mode
final shuffleModeProvider = Provider<bool>((ref) {
  final state = ref.watch(playerStateProvider).valueOrNull;
  return state?.shuffleMode == AudioServiceShuffleMode.all;
});

/// Provider for repeat mode
final repeatModeProvider = Provider<AudioServiceRepeatMode>((ref) {
  return ref.watch(playerStateProvider).valueOrNull?.repeatMode ??
      AudioServiceRepeatMode.none;
});

// ================== Media Providers ==================

/// Provider for MediaRepository
final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository();
});

/// Provider for all songs
final songsProvider = StateProvider<List<SongModel>>((ref) {
  return [];
});

/// Provider for songs loading state
final songsLoadingProvider = StateProvider<bool>((ref) {
  return true;
});

/// Whether we currently have access to the user's audio library.
///
/// The library being empty and the library being unreadable look identical in
/// the song list, so this is tracked separately to keep the empty state honest.
final mediaPermissionProvider = StateProvider<MediaPermissionStatus>((ref) {
  return MediaPermissionStatus.denied;
});

/// Loads the on-device library, requesting access first.
final libraryLoaderProvider = Provider<LibraryLoader>((ref) {
  return LibraryLoader(ref);
});

class LibraryLoader {
  LibraryLoader(this._ref);

  final Ref _ref;

  /// Populate the song list.
  ///
  /// Set [prompt] to show the system permission dialog; pass false to re-check
  /// silently, e.g. after returning from the system settings page.
  Future<void> load({bool prompt = true}) async {
    _ref.read(songsLoadingProvider.notifier).state = true;

    final status = prompt
        ? await PermissionService.request()
        : await PermissionService.check();
    _ref.read(mediaPermissionProvider.notifier).state = status;

    if (status != MediaPermissionStatus.granted) {
      _ref.read(songsProvider.notifier).state = [];
      _ref.read(songsLoadingProvider.notifier).state = false;
      return;
    }

    final repo = _ref.read(mediaRepositoryProvider);

    // Show the cached library immediately, then refresh from a live scan.
    final cached = repo.getCachedSongs();
    if (cached.isNotEmpty) {
      _ref.read(songsProvider.notifier).state = cached;
      _ref.read(songsLoadingProvider.notifier).state = false;
    }

    final List<SongModel> scanned;
    if (PlatformInfo.isDesktop) {
      scanned = await repo.scanDesktopSongs(
        folders: _ref.read(desktopScanFoldersProvider),
        hideShortAudio: _ref.read(minDurationFilterProvider),
      );
    } else {
      scanned = await repo.scanLocalSongs(
        hideShortAudio: _ref.read(minDurationFilterProvider),
        excludedFolders: _ref.read(excludedFoldersProvider),
      );
      // The Folders screen needs the full folder list refreshed after every
      // scan, including folders currently excluded.
      _ref.read(knownFoldersProvider.notifier).state = repo.getKnownFolders();
    }
    _ref.read(songsProvider.notifier).state = scanned;
    _ref.read(songsLoadingProvider.notifier).state = false;
  }
}

/// Provider for search query
final searchQueryProvider = StateProvider<String>((ref) {
  return '';
});

/// Provider for filtered songs based on search
final filteredSongsProvider = Provider<List<SongModel>>((ref) {
  final songs = ref.watch(songsProvider);
  final query = ref.watch(searchQueryProvider);

  if (query.isEmpty) return songs;

  final lowerQuery = query.toLowerCase();
  return songs
      .where(
        (song) =>
            song.title.toLowerCase().contains(lowerQuery) ||
            song.artist.toLowerCase().contains(lowerQuery) ||
            song.album.toLowerCase().contains(lowerQuery),
      )
      .toList();
});

// Album / artist / genre groupings live in library_provider.dart, which returns
// the songs in each group rather than bare name strings.

/// Provider for sort order
final sortOrderProvider = StateProvider<SongSortOrder>((ref) {
  return SongSortOrder.title;
});

/// Provider for sorted songs
final sortedSongsProvider = Provider<List<SongModel>>((ref) {
  final songs = List<SongModel>.from(ref.watch(filteredSongsProvider));
  final sortOrder = ref.watch(sortOrderProvider);

  switch (sortOrder) {
    case SongSortOrder.title:
      songs.sort((a, b) => a.title.compareTo(b.title));
      break;
    case SongSortOrder.artist:
      songs.sort((a, b) => a.artist.compareTo(b.artist));
      break;
    case SongSortOrder.album:
      songs.sort((a, b) => a.album.compareTo(b.album));
      break;
    case SongSortOrder.dateAdded:
      songs.sort(
        (a, b) => (b.dateAdded ?? DateTime(1970))
            .compareTo(a.dateAdded ?? DateTime(1970)),
      );
      break;
    case SongSortOrder.duration:
      songs.sort((a, b) => b.duration.compareTo(a.duration));
      break;
  }

  return songs;
});

enum SongSortOrder {
  title,
  artist,
  album,
  dateAdded,
  duration,
}

// ================== Remote (WebDAV) playback ==================

/// Builds MediaItems for [entries] (already filtered to audio files, in
/// display order) and starts playback at [index] — the remote counterpart to
/// [playSongs] in song_tile.dart.
///
/// [serverName] and [folderName] become every item's artist/album: WebDAV
/// exposes no ID3-style tags without downloading the file first, and "which
/// server, which folder" beats "Unknown Artist" repeated for every track.
Future<void> playRemoteQueue(
  WidgetRef ref, {
  required String serverId,
  required String serverName,
  required String folderName,
  required List<WebDavEntry> entries,
  required int index,
}) async {
  if (entries.isEmpty) return;
  final sessions = ref.read(serverSessionsProvider.notifier);

  final items = <MediaItem>[];
  for (final entry in entries) {
    final spec = await sessions.remoteStreamSpec(serverId, entry.path);
    items.add(
      MediaItem(
        id: spec.url.toString(),
        title: WebDavClient.basename(entry.path),
        artist: serverName,
        album: folderName,
        extras: {'headers': spec.headers},
      ),
    );
  }

  final handler = ref.read(audioHandlerProvider);
  await handler.loadPlaylist(items, initialIndex: index);
  await handler.play();
}
