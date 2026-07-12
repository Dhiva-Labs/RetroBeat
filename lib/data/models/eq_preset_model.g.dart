// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'eq_preset_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EqPresetModelAdapter extends TypeAdapter<EqPresetModel> {
  @override
  final int typeId = 3;

  @override
  EqPresetModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EqPresetModel(
      id: fields[0] as String,
      name: fields[1] as String,
      bandLevels: (fields[2] as List).cast<double>(),
      isCustom: fields[3] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, EqPresetModel obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.bandLevels)
      ..writeByte(3)
      ..write(obj.isCustom);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EqPresetModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
