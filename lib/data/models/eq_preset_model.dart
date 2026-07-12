import 'package:hive/hive.dart';

part 'eq_preset_model.g.dart';

@HiveType(typeId: 3)
class EqPresetModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<double> bandLevels; // dB values for each frequency band

  @HiveField(3)
  final bool isCustom; // false for built-in presets

  EqPresetModel({
    required this.id,
    required this.name,
    required this.bandLevels,
    this.isCustom = false,
  });

  EqPresetModel copyWith({
    String? id,
    String? name,
    List<double>? bandLevels,
    bool? isCustom,
  }) {
    return EqPresetModel(
      id: id ?? this.id,
      name: name ?? this.name,
      bandLevels: bandLevels ?? List.from(this.bandLevels),
      isCustom: isCustom ?? this.isCustom,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EqPresetModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
