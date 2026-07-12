import 'package:hive/hive.dart';

part 'song_model.g.dart';

@HiveType(typeId: 0)
class SongModel extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String artist;

  @HiveField(3)
  final String album;

  @HiveField(4)
  final String uri;

  @HiveField(5)
  final int duration; // in milliseconds

  @HiveField(6)
  final String? albumArtPath;

  @HiveField(7)
  final String genre;

  @HiveField(8)
  final int size; // in bytes

  @HiveField(9)
  final DateTime? dateAdded;

  @HiveField(10)
  int playCount;

  @HiveField(11)
  bool isFavorite;

  /// Absolute filesystem path, e.g. `/storage/emulated/0/Music/Artist/Song.mp3`.
  ///
  /// Distinct from [uri]: on Android, `uri` is usually an opaque
  /// `content://media/...` handle with no folder information in it at all, so
  /// "which folder is this song in" (needed to let someone exclude a folder
  /// from their library) has to come from this field instead.
  @HiveField(12)
  final String? filePath;

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.uri,
    required this.duration,
    this.albumArtPath,
    this.genre = 'Unknown',
    this.size = 0,
    this.dateAdded,
    this.playCount = 0,
    this.isFavorite = false,
    this.filePath,
  });

  SongModel copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    String? uri,
    int? duration,
    String? albumArtPath,
    String? genre,
    int? size,
    DateTime? dateAdded,
    int? playCount,
    bool? isFavorite,
    String? filePath,
  }) {
    return SongModel(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      uri: uri ?? this.uri,
      duration: duration ?? this.duration,
      albumArtPath: albumArtPath ?? this.albumArtPath,
      genre: genre ?? this.genre,
      size: size ?? this.size,
      dateAdded: dateAdded ?? this.dateAdded,
      playCount: playCount ?? this.playCount,
      isFavorite: isFavorite ?? this.isFavorite,
      filePath: filePath ?? this.filePath,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SongModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
