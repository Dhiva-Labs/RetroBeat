import 'package:hive/hive.dart';

part 'playlist_model.g.dart';

@HiveType(typeId: 1)
class PlaylistModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? description;

  @HiveField(3)
  List<int> songIds;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  DateTime updatedAt;

  @HiveField(6)
  String? coverArtPath;

  PlaylistModel({
    required this.id,
    required this.name,
    this.description,
    List<int>? songIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.coverArtPath,
  })  : songIds = songIds ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get songCount => songIds.length;

  void addSong(int songId) {
    if (!songIds.contains(songId)) {
      songIds.add(songId);
      updatedAt = DateTime.now();
    }
  }

  void removeSong(int songId) {
    songIds.remove(songId);
    updatedAt = DateTime.now();
  }

  /// Move the song at [oldIndex] to [newIndex].
  ///
  /// [newIndex] is the final resting index, i.e. already adjusted for the
  /// removal of [oldIndex]. `ReorderableListView.onReorderItem` supplies indices
  /// in exactly this form; the older `onReorder` callback does not.
  void reorderSongs(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= songIds.length) return;
    final item = songIds.removeAt(oldIndex);
    songIds.insert(newIndex.clamp(0, songIds.length), item);
    updatedAt = DateTime.now();
  }

  PlaylistModel copyWith({
    String? id,
    String? name,
    String? description,
    List<int>? songIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? coverArtPath,
  }) {
    return PlaylistModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      songIds: songIds ?? List.from(this.songIds),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      coverArtPath: coverArtPath ?? this.coverArtPath,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaylistModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
