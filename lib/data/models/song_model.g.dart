// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SongModelAdapter extends TypeAdapter<SongModel> {
  @override
  final int typeId = 0;

  @override
  SongModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SongModel(
      id: fields[0] as int,
      title: fields[1] as String,
      artist: fields[2] as String,
      album: fields[3] as String,
      uri: fields[4] as String,
      duration: fields[5] as int,
      albumArtPath: fields[6] as String?,
      genre: fields[7] as String,
      size: fields[8] as int,
      dateAdded: fields[9] as DateTime?,
      playCount: fields[10] as int,
      isFavorite: fields[11] as bool,
      filePath: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SongModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.album)
      ..writeByte(4)
      ..write(obj.uri)
      ..writeByte(5)
      ..write(obj.duration)
      ..writeByte(6)
      ..write(obj.albumArtPath)
      ..writeByte(7)
      ..write(obj.genre)
      ..writeByte(8)
      ..write(obj.size)
      ..writeByte(9)
      ..write(obj.dateAdded)
      ..writeByte(10)
      ..write(obj.playCount)
      ..writeByte(11)
      ..write(obj.isFavorite)
      ..writeByte(12)
      ..write(obj.filePath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
