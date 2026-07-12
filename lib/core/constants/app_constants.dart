/// App-wide constants
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'RetroBeat';
  static const String appVersion = '1.0.0';

  // Hive Box Names
  static const String songsBox = 'songs_box';
  static const String playlistsBox = 'playlists_box';
  static const String groupsBox = 'groups_box';
  static const String eqPresetsBox = 'eq_presets_box';
  static const String settingsBox = 'settings_box';

  // Settings Keys
  static const String activeEqPreset = 'active_eq_preset';
  static const String eqEnabled = 'eq_enabled';
  static const String eqBandGains = 'eq_band_gains';

  // Preset curves below are authored as 5 points and resampled onto whatever
  // bands the device's equalizer actually reports. See EqualizerService.
  // Default EQ Presets
  static const Map<String, List<double>> defaultEqPresets = {
    'Flat': [0, 0, 0, 0, 0],
    'Bass Boost': [5, 3.5, 0, 0, 0],
    'Bass Reducer': [-5, -3.5, 0, 0, 0],
    'Treble Boost': [0, 0, 0, 3.5, 5],
    'Treble Reducer': [0, 0, 0, -3.5, -5],
    'Classical': [3, 1, 0, 2, 3],
    'Dance': [4, 2, -1, 3, 4],
    'Hip Hop': [4, 3, 0, 1, 2],
    'Jazz': [3, 1, -1, 1, 3],
    'Pop': [-1, 2, 4, 2, -1],
    'Rock': [4, 2, -1, 2, 4],
    'Vocal': [-2, 0, 3, 2, -1],
    'Acoustic': [3, 1, 0, 1, 2],
    'Electronic': [4, 2, 0, 1, 3],
    'R&B': [2, 4, 2, 0, 1],
    'Latin': [2, 0, 0, 2, 3],
  };

  // Group Emojis
  static const List<String> groupEmojis = [
    '🎵',
    '🎧',
    '🎸',
    '🎹',
    '🥁',
    '🎺',
    '🎻',
    '🎤',
    '💃',
    '🏃',
    '🧘',
    '😴',
    '❤️',
    '🔥',
    '⚡',
    '🌙',
    '🌅',
    '🎉',
    '🏖️',
    '☕',
    '🍷',
    '🎮',
    '📚',
    '🚗',
  ];
}
