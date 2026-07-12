import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../data/models/eq_preset_model.dart';
import '../data/repositories/equalizer_repository.dart';
import '../data/services/equalizer_service.dart';
import 'audio_provider.dart';

/// Persistence for EQ settings.
final equalizerRepositoryProvider = Provider<EqualizerRepository>((ref) {
  return EqualizerRepository();
});

/// Applies EQ settings to the live playback pipeline.
final equalizerServiceProvider = Provider<EqualizerService>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return EqualizerService(handler.equalizer);
});

/// The device's own band layout, or null when the equalizer is unavailable —
/// which includes the case where nothing has been played yet, because just_audio
/// cannot report bands until the player has connected to the platform.
final equalizerParametersProvider =
    FutureProvider<AndroidEqualizerParameters?>((ref) async {
  // Re-resolve once playback starts, since that is when bands become readable.
  ref.watch(currentMediaItemProvider);
  return ref.watch(equalizerServiceProvider).parameters();
});

/// Whether the EQ is switched on.
final eqEnabledProvider = StateNotifierProvider<EqEnabledNotifier, bool>((ref) {
  return EqEnabledNotifier(
    ref.watch(equalizerRepositoryProvider),
    ref.watch(equalizerServiceProvider),
  );
});

class EqEnabledNotifier extends StateNotifier<bool> {
  EqEnabledNotifier(this._repo, this._service) : super(_repo.isEqEnabled()) {
    // Re-assert the persisted state onto the pipeline once it is reachable.
    _service.setEnabled(state);
  }

  final EqualizerRepository _repo;
  final EqualizerService _service;

  Future<void> set(bool enabled) async {
    state = enabled;
    await _repo.setEqEnabled(enabled);
    await _service.setEnabled(enabled);
  }
}

/// Current per-band gains in dB, sized to the device's band count.
final bandGainsProvider =
    StateNotifierProvider<BandGainsNotifier, List<double>>((ref) {
  return BandGainsNotifier(
    ref.watch(equalizerRepositoryProvider),
    ref.watch(equalizerServiceProvider),
  );
});

class BandGainsNotifier extends StateNotifier<List<double>> {
  BandGainsNotifier(this._repo, this._service) : super(const []);

  final EqualizerRepository _repo;
  final EqualizerService _service;

  /// Adopt the device's band count, restoring saved gains if they still fit.
  Future<void> hydrate(int bandCount) async {
    if (state.length == bandCount) return;
    final saved = _repo.getSavedGains(bandCount);
    if (saved == null) {
      state = List<double>.filled(bandCount, 0.0);
      return;
    }
    state = saved;
    await _push(saved);
  }

  Future<void> setBand(int index, double gain) async {
    if (index < 0 || index >= state.length) return;
    await _push(List<double>.from(state)..[index] = gain);
  }

  Future<void> applyPreset(EqPresetModel preset) async {
    await _push(_service.resamplePreset(preset.bandLevels, state.length));
    await _repo.setActivePreset(preset.id);
  }

  Future<void> reset() async {
    await _push(List<double>.filled(state.length, 0.0));
    await _repo.clearActivePreset();
  }

  /// Send gains to the hardware and adopt whatever it actually accepted, so the
  /// sliders and the sound never disagree.
  Future<void> _push(List<double> gains) async {
    final applied = await _service.applyGains(gains);
    state = applied;
    await _repo.setSavedGains(applied);
  }

  /// The current gains collapsed back to an authored 5-point curve, for saving.
  List<double> asPresetCurve() => _service.toPresetCurve(state);
}

/// All stored presets, built-in and custom.
final eqPresetsProvider = StateProvider<List<EqPresetModel>>((ref) {
  return ref.watch(equalizerRepositoryProvider).getAllPresets();
});

/// The preset currently applied, if the user has not since hand-tuned a band.
final activePresetIdProvider = StateProvider<String?>((ref) {
  return ref.watch(equalizerRepositoryProvider).getActivePresetId();
});
