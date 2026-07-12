import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/playlist_model.dart';
import '../data/repositories/playlist_repository.dart';

/// Provider for PlaylistRepository
final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository();
});

/// Provider for all playlists
final playlistsProvider =
    StateNotifierProvider<PlaylistsNotifier, List<PlaylistModel>>((ref) {
  return PlaylistsNotifier(ref.watch(playlistRepositoryProvider));
});

class PlaylistsNotifier extends StateNotifier<List<PlaylistModel>> {
  final PlaylistRepository _repository;

  PlaylistsNotifier(this._repository) : super([]) {
    loadPlaylists();
  }

  void loadPlaylists() {
    state = _repository.getAllPlaylists();
  }

  Future<PlaylistModel> createPlaylist({
    required String name,
    String? description,
    List<int>? songIds,
  }) async {
    final playlist = await _repository.createPlaylist(
      name: name,
      description: description,
      songIds: songIds,
    );
    state = _repository.getAllPlaylists();
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    await _repository.deletePlaylist(id);
    state = _repository.getAllPlaylists();
  }

  Future<void> updatePlaylist(PlaylistModel playlist) async {
    await _repository.updatePlaylist(playlist);
    state = _repository.getAllPlaylists();
  }

  Future<void> addSongToPlaylist(String playlistId, int songId) async {
    await _repository.addSongToPlaylist(playlistId, songId);
    state = _repository.getAllPlaylists();
  }

  Future<void> removeSongFromPlaylist(String playlistId, int songId) async {
    await _repository.removeSongFromPlaylist(playlistId, songId);
    state = _repository.getAllPlaylists();
  }

  Future<void> reorderSongs(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    await _repository.reorderSongs(playlistId, oldIndex, newIndex);
    state = _repository.getAllPlaylists();
  }
}
