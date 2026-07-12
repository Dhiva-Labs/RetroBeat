import 'package:hive/hive.dart';

part 'group_model.g.dart';

@HiveType(typeId: 2)
class GroupModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String emoji;

  @HiveField(3)
  String colorHex; // Hex color for visual identity

  @HiveField(4)
  List<int> songIds;

  @HiveField(5)
  List<String> playlistIds;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  bool isSmartGroup; // Auto-populated groups

  GroupModel({
    required this.id,
    required this.name,
    this.emoji = '🎵',
    this.colorHex = '#7C4DFF',
    List<int>? songIds,
    List<String>? playlistIds,
    DateTime? createdAt,
    this.isSmartGroup = false,
  })  : songIds = songIds ?? [],
        playlistIds = playlistIds ?? [],
        createdAt = createdAt ?? DateTime.now();

  int get totalItems => songIds.length + playlistIds.length;

  void addSong(int songId) {
    if (!songIds.contains(songId)) {
      songIds.add(songId);
    }
  }

  void removeSong(int songId) {
    songIds.remove(songId);
  }

  void addPlaylist(String playlistId) {
    if (!playlistIds.contains(playlistId)) {
      playlistIds.add(playlistId);
    }
  }

  void removePlaylist(String playlistId) {
    playlistIds.remove(playlistId);
  }

  GroupModel copyWith({
    String? id,
    String? name,
    String? emoji,
    String? colorHex,
    List<int>? songIds,
    List<String>? playlistIds,
    DateTime? createdAt,
    bool? isSmartGroup,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      colorHex: colorHex ?? this.colorHex,
      songIds: songIds ?? List.from(this.songIds),
      playlistIds: playlistIds ?? List.from(this.playlistIds),
      createdAt: createdAt ?? this.createdAt,
      isSmartGroup: isSmartGroup ?? this.isSmartGroup,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
