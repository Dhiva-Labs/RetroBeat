import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:on_audio_query/on_audio_query.dart' hide SongModel;
import 'package:audio_service/audio_service.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/folder_utils.dart';
import '../../core/utils/stable_id.dart';
import '../models/song_model.dart';
import '../services/desktop_artwork_cache.dart';
import '../services/storage_service.dart';

/// Repository for scanning and managing local media files
class MediaRepository {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Clips shorter than this are usually ringtones and notification sounds
  /// rather than music.
  static const int shortAudioCutoffMs = 30000;

  static const String _knownFoldersKey = 'known_folders';

  /// Extensions this desktop scan recognises. Kept separate from
  /// `audio_metadata_reader`'s own supported list because a couple of these
  /// (bare `.aac` elementary streams, in particular) have no tag container it
  /// can parse — such files are still added to the library, just without
  /// metadata, since a missing tag is not a reason to hide a playable file.
  static const Set<String> desktopExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.wav',
    '.ogg',
    '.opus',
  };

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

  /// Recursively scan [folders] for audio files and cache them in Hive.
  ///
  /// There is no MediaStore outside Android, so the desktop library is
  /// exactly whatever this finds under the folders the user picked — nothing
  /// more. A song cached from an earlier scan that this pass does not find
  /// again (its file was deleted, or its folder was removed from [folders])
  /// is dropped: unlike [scanLocalSongs]'s excluded-but-remembered folders,
  /// there is no wider MediaStore listing here to fall back on, so "not
  /// found this time" is the only signal available.
  Future<List<SongModel>> scanDesktopSongs({
    required List<String> folders,
    bool hideShortAudio = true,
  }) async {
    final found = <int, SongModel>{};

    for (final folder in folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;

      Stream<FileSystemEntity> entries;
      try {
        entries = dir.list(recursive: true, followLinks: false);
      } catch (_) {
        continue; // Unreadable folder (permissions, unmounted drive, ...).
      }

      await for (final entity in entries.handleError((_) {})) {
        if (entity is! File) continue;
        if (!desktopExtensions
            .contains(p.extension(entity.path).toLowerCase())) {
          continue;
        }

        final song = await _readDesktopSong(entity);
        if (song == null) continue;
        if (hideShortAudio && song.duration < shortAudioCutoffMs) continue;

        found[song.id] = song;
      }
    }

    // Anything cached that this pass did not (re)find has been deleted, or
    // has fallen out of every currently configured folder.
    for (final id in StorageService.songsBox.keys.toList()) {
      if (!found.containsKey(id)) {
        await StorageService.songsBox.delete(id);
      }
    }

    for (final song in found.values) {
      await StorageService.songsBox.put(song.id, song);
    }

    return found.values.toList();
  }

  /// Build a [SongModel] for one file, reading its tags and pulling any
  /// embedded art into [DesktopArtworkCache] on the way.
  ///
  /// Returns null only when the file has vanished between being listed and
  /// being read (a folder mid-sync, for instance) — a tag-reading failure is
  /// not reason enough to drop an otherwise playable file, so that case falls
  /// back to filename-derived metadata instead.
  Future<SongModel?> _readDesktopSong(File file) async {
    final FileStat stat;
    try {
      stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
    } catch (_) {
      return null;
    }

    AudioMetadata? tags;
    try {
      tags = readMetadata(file, getImage: true);
    } catch (_) {
      tags = null;
    }

    final id = stableIdFor(file.path);
    final existing = StorageService.songsBox.get(id);
    DesktopArtworkCache.put(id, tags?.pictures.firstOrNull?.bytes);

    final title = tags?.title?.trim();
    final artist = tags?.artist?.trim();
    final album = tags?.album?.trim();

    return SongModel(
      id: id,
      title: title?.isNotEmpty == true
          ? title!
          : p.basenameWithoutExtension(file.path),
      artist: artist?.isNotEmpty == true ? artist! : 'Unknown Artist',
      album: album?.isNotEmpty == true ? album! : 'Unknown Album',
      uri: Uri.file(file.path).toString(),
      duration: tags?.duration?.inMilliseconds ?? 0,
      genre: tags?.genres.firstOrNull ?? 'Unknown',
      size: stat.size,
      // First-seen time, carried forward exactly like isFavorite/playCount
      // below — there is no MediaStore "date added" to read here, and
      // re-stamping it on every rescan would make "Recently Added" meaningless.
      dateAdded: existing?.dateAdded ?? DateTime.now(),
      filePath: file.path,
      isFavorite: existing?.isFavorite ?? false,
      playCount: existing?.playCount ?? 0,
    );
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
