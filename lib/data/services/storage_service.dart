import 'package:hive_flutter/hive_flutter.dart';
import '../models/song_model.dart';
import '../models/playlist_model.dart';
import '../models/group_model.dart';
import '../models/eq_preset_model.dart';
import '../../core/constants/app_constants.dart';

/// Service to handle Hive database initialization and access
class StorageService {
  static late Box<SongModel> songsBox;
  static late Box<PlaylistModel> playlistsBox;
  static late Box<GroupModel> groupsBox;
  static late Box<EqPresetModel> eqPresetsBox;
  static late Box settingsBox;

  /// Initialize Hive and register adapters
  static Future<void> init() async {
    await Hive.initFlutter();

    // Register adapters
    Hive.registerAdapter(SongModelAdapter());
    Hive.registerAdapter(PlaylistModelAdapter());
    Hive.registerAdapter(GroupModelAdapter());
    Hive.registerAdapter(EqPresetModelAdapter());

    // Open boxes
    songsBox = await Hive.openBox<SongModel>(AppConstants.songsBox);
    playlistsBox = await Hive.openBox<PlaylistModel>(AppConstants.playlistsBox);
    groupsBox = await Hive.openBox<GroupModel>(AppConstants.groupsBox);
    eqPresetsBox = await Hive.openBox<EqPresetModel>(AppConstants.eqPresetsBox);
    settingsBox = await Hive.openBox(AppConstants.settingsBox);

    // Initialize default EQ presets if empty
    if (eqPresetsBox.isEmpty) {
      await _initDefaultEqPresets();
    }

    // Initialize default groups if empty
    if (groupsBox.isEmpty) {
      await _initDefaultGroups();
    }
  }

  static Future<void> _initDefaultEqPresets() async {
    int i = 0;
    for (final entry in AppConstants.defaultEqPresets.entries) {
      final preset = EqPresetModel(
        id: 'preset_$i',
        name: entry.key,
        bandLevels: entry.value,
      );
      await eqPresetsBox.put(preset.id, preset);
      i++;
    }
  }

  static Future<void> _initDefaultGroups() async {
    final defaultGroups = [
      GroupModel(
        id: 'group_favorites',
        name: 'Favorites',
        emoji: '❤️',
        colorHex: '#FF6B6B',
        isSmartGroup: true,
      ),
      GroupModel(
        id: 'group_recently_added',
        name: 'Recently Added',
        emoji: '🆕',
        colorHex: '#4D96FF',
        isSmartGroup: true,
      ),
      GroupModel(
        id: 'group_most_played',
        name: 'Most Played',
        emoji: '🔥',
        colorHex: '#FFD93D',
        isSmartGroup: true,
      ),
    ];

    for (final group in defaultGroups) {
      await groupsBox.put(group.id, group);
    }
  }

  /// Get a setting value
  static T? getSetting<T>(String key) {
    return settingsBox.get(key) as T?;
  }

  /// Set a setting value
  static Future<void> setSetting(String key, dynamic value) async {
    await settingsBox.put(key, value);
  }

  /// Close all boxes
  static Future<void> close() async {
    await Hive.close();
  }
}
