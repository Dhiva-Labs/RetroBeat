import 'package:on_audio_query/on_audio_query.dart' hide SongModel;
import 'package:audio_service/audio_service.dart';
import '../../core/utils/folder_utils.dart';
import '../models/song_model.dart';
import '../services/storage_service.dart';

/// Repository for scanning and managing local media files
class MediaRepository {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Clips shorter than this are usually ringtones and notification sounds
  /// rather than music.
  static const int shortAudioCutoffMs = 30000;

  static const String _knownFoldersKey = 'known_folders';

  /// Scan device for local audio files and cache in Hive.
  ///
  /// [hideShortAudio] mirrors the Settings toggle of the same name.
  /// [excludedFolders] mirrors the Folders settings screen: any song whose
  /// containing folder is excluded is skipped, and purged from the cache if it
  /// is already there from an earlier scan.
  Future<List<SongModel>> scanLocalSongs({
    bool hideShortAudio = true,
    Set<String> excludedFolders = const {},
  }) async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      // Every folder MediaStore reports, regardless of exclusion — this is
      // what backs the Folders settings screen. Computed from the unfiltered
      // scan, or a folder the user excluded would vanish from that screen
      // along with its songs, making it impossible to turn back on.
      final folderCounts = <String, int>{};
      final songModels = <SongModel>[];

      for (final song in songs) {
        final folder = folderOf(song.data);
        if (folder != null) {
          folderCounts[folder] = (folderCounts[folder] ?? 0) + 1;
        }

        final tooShort = hideShortAudio &&
            song.duration != null &&
            song.duration! < shortAudioCutoffMs;
        final excluded =
            folder != null && isFolderExcluded(folder, excludedFolders);

        if (tooShort || excluded) {
          // Remove it if an earlier scan (before this folder was excluded, or
          // before hideShortAudio was turned on) already cached it.
          await StorageService.songsBox.delete(song.id);
          continue;
        }

        // A rescan rebuilds every field from MediaStore, which does not know
        // about isFavorite or playCount — those exist only in our own cache.
        // Carrying them forward here is what stops every rescan from quietly
        // resetting them to defaults; that bug was survivable when rescans
        // only happened on a manual tap, and stops being survivable once
        // auto-rescan runs on every resume.
        final existing = StorageService.songsBox.get(song.id);

        final model = SongModel(
          id: song.id,
          title: song.title,
          artist: song.artist ?? 'Unknown Artist',
          album: song.album ?? 'Unknown Album',
          uri: song.uri ?? song.data,
          duration: song.duration ?? 0,
          genre: song.genre ?? 'Unknown',
          size: song.size,
          dateAdded: song.dateAdded != null
              ? DateTime.fromMillisecondsSinceEpoch(song.dateAdded! * 1000)
              : null,
          filePath: song.data,
          isFavorite: existing?.isFavorite ?? false,
          playCount: existing?.playCount ?? 0,
        );

        songModels.add(model);
        await StorageService.songsBox.put(model.id, model);
      }

      await StorageService.setSetting(_knownFoldersKey, folderCounts);

      return songModels;
    } catch (e) {
      // Return cached songs if scan fails
      return StorageService.songsBox.values.toList();
    }
  }

  /// Get all cached songs from Hive
  List<SongModel> getCachedSongs() {
    return StorageService.songsBox.values.toList();
  }

  /// Every folder seen on the last scan, mapped to how many songs are in it —
  /// including folders currently excluded, so they can be turned back on.
  Map<String, int> getKnownFolders() {
    final raw = StorageService.getSetting<Map>(_knownFoldersKey);
    if (raw == null) return {};
    return raw.map((key, value) => MapEntry(key as String, value as int));
  }

  /// Convert SongModel to MediaItem for audio_service
  static MediaItem songToMediaItem(SongModel song) {
    return MediaItem(
      id: song.uri,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.duration),
      artUri: song.albumArtPath != null ? Uri.file(song.albumArtPath!) : null,
      extras: {'songId': song.id},
    );
  }

  /// Toggle favorite status for a song
  Future<void> toggleFavorite(int songId) async {
    final song = StorageService.songsBox.get(songId);
    if (song != null) {
      song.isFavorite = !song.isFavorite;
      await song.save();
    }
  }

  /// Increment play count
  Future<void> incrementPlayCount(int songId) async {
    final song = StorageService.songsBox.get(songId);
    if (song != null) {
      song.playCount++;
      await song.save();
    }
  }
}
