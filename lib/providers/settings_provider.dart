import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/visualizer_style.dart';
import '../data/services/storage_service.dart';

/// A boolean setting that persists itself to Hive.
class _BoolSetting extends StateNotifier<bool> {
  _BoolSetting(this._key, {required bool fallback})
      : super(StorageService.getSetting<bool>(_key) ?? fallback);

  final String _key;

  Future<void> set(bool value) async {
    if (value == state) return;
    state = value;
    await StorageService.setSetting(_key, value);
  }

  Future<void> toggle() => set(!state);
}

/// Dark vs light. Ignored while [retroModeProvider] is on, since the retro skin
/// is its own palette.
final themeProvider = StateNotifierProvider<ThemeNotifier, bool>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends _BoolSetting {
  ThemeNotifier() : super('is_dark_mode', fallback: true);

  void toggleTheme() => toggle();
}

/// Hide clips under 30 seconds (ringtones, notification sounds).
final minDurationFilterProvider =
    StateNotifierProvider<MinDurationFilterNotifier, bool>((ref) {
  return MinDurationFilterNotifier();
});

class MinDurationFilterNotifier extends _BoolSetting {
  MinDurationFilterNotifier() : super('min_duration_filter', fallback: true);
}

/// Rescan automatically whenever the app comes back to the foreground, so new
/// music shows up without a manual "Rescan library" tap. On by default: a
/// library that silently misses what you just added is the more surprising
/// state, not the other way around.
final autoRescanProvider =
    StateNotifierProvider<AutoRescanNotifier, bool>((ref) {
  return AutoRescanNotifier();
});

class AutoRescanNotifier extends _BoolSetting {
  AutoRescanNotifier() : super('auto_rescan', fallback: true);
}

/// The Windows-Media-Player-flavoured skin, plus the visualiser on the player.
/// Off by default: it is a deliberate novelty, not the app's normal face.
final retroModeProvider = StateNotifierProvider<RetroModeNotifier, bool>((ref) {
  return RetroModeNotifier();
});

class RetroModeNotifier extends _BoolSetting {
  RetroModeNotifier() : super('retro_mode', fallback: false);
}

/// Whether the visualiser is driven by the real audio signal.
///
/// Off by default, because the Android API that exposes the waveform
/// (`android.media.audiofx.Visualizer`) requires the RECORD_AUDIO permission,
/// and a music player asking to record audio is alarming if it happens
/// unprompted. When off the bars are an animation and are labelled as one.
final audioReactiveVisualizerProvider =
    StateNotifierProvider<AudioReactiveNotifier, bool>((ref) {
  return AudioReactiveNotifier();
});

class AudioReactiveNotifier extends _BoolSetting {
  AudioReactiveNotifier() : super('audio_reactive_visualizer', fallback: false);
}

/// Which visualisation is on screen.
final visualizerStyleProvider =
    StateNotifierProvider<VisualizerStyleNotifier, VisualizerStyle>((ref) {
  return VisualizerStyleNotifier();
});

class VisualizerStyleNotifier extends StateNotifier<VisualizerStyle> {
  VisualizerStyleNotifier() : super(_load());

  static const _key = 'visualizer_style';

  static VisualizerStyle _load() {
    final saved = StorageService.getSetting<String>(_key);
    // Ambience by default: the flowing fields are the point of Retro mode, and
    // a bar chart is not what anyone remembers WMP for. An unknown name means a
    // style was removed in an update, so fall back rather than throw.
    return VisualizerStyle.values.asNameMap()[saved] ??
        VisualizerStyle.ambience;
  }

  Future<void> set(VisualizerStyle style) async {
    state = style;
    await StorageService.setSetting(_key, style.name);
  }

  /// Advance to the next one, as WMP's next-visualisation arrow did.
  Future<void> cycle() => set(state.next);
}
