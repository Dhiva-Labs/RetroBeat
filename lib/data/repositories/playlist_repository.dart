import 'package:uuid/uuid.dart';
import '../models/playlist_model.dart';
import '../services/storage_service.dart';

/// Repository for playlist CRUD operations
class PlaylistRepository {
  static const _uuid = Uuid();

  /// Create a new playlist
  Future<PlaylistModel> createPlaylist({
    required String name,
    String? description,
    List<int>? songIds,
  }) async {
    final playlist = PlaylistModel(
      id: _uuid.v4(),
      name: name,
      description: description,
      songIds: songIds,
    );
    await StorageService.playlistsBox.put(playlist.id, playlist);
    return playlist;
  }

  /// Get all playlists
  List<PlaylistModel> getAllPlaylists() {
    return StorageService.playlistsBox.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Get a playlist by ID
  PlaylistModel? getPlaylist(String id) {
    return StorageService.playlistsBox.get(id);
  }

  /// Update playlist details
  Future<void> updatePlaylist(PlaylistModel playlist) async {
    playlist.updatedAt = DateTime.now();
    await StorageService.playlistsBox.put(playlist.id, playlist);
  }

  /// Delete a playlist
  Future<void> deletePlaylist(String id) async {
    await StorageService.playlistsBox.delete(id);
  }

  /// Add a song to a playlist
  Future<void> addSongToPlaylist(String playlistId, int songId) async {
    final playlist = StorageService.playlistsBox.get(playlistId);
    if (playlist != null) {
      playlist.addSong(songId);
      await playlist.save();
    }
  }

  /// Remove a song from a playlist
  Future<void> removeSongFromPlaylist(String playlistId, int songId) async {
    final playlist = StorageService.playlistsBox.get(playlistId);
    if (playlist != null) {
      playlist.removeSong(songId);
      await playlist.save();
    }
  }

  /// Reorder songs in a playlist
  Future<void> reorderSongs(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final playlist = StorageService.playlistsBox.get(playlistId);
    if (playlist != null) {
      playlist.reorderSongs(oldIndex, newIndex);
      await playlist.save();
    }
  }
}
