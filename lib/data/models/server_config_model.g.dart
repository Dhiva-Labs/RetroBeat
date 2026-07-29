// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_config_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ServerConfigModelAdapter extends TypeAdapter<ServerConfigModel> {
  @override
  final int typeId = 4;

  @override
  ServerConfigModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ServerConfigModel(
      id: fields[0] as String,
      name: fields[1] as String,
      baseUrl: fields[2] as String,
      username: fields[3] as String,
      rootPath: fields[4] as String,
      autoConnect: fields[5] as bool,
      createdAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ServerConfigModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.baseUrl)
      ..writeByte(3)
      ..write(obj.username)
      ..writeByte(4)
      ..write(obj.rootPath)
      ..writeByte(5)
      ..write(obj.autoConnect)
      ..writeByte(6)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerConfigModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
