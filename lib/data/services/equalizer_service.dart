import 'dart:io';

import 'package:just_audio/just_audio.dart';

/// Applies equalizer settings to the live audio pipeline.
///
/// The number of bands and their centre frequencies are reported by the device,
/// not chosen by us, so stored presets (which are authored as a fixed 5-point
/// curve) are resampled onto whatever bands the hardware actually exposes.
class EqualizerService {
  EqualizerService(this._equalizer);

  final AndroidEqualizer _equalizer;

  /// Number of points in an authored preset curve. See
  /// `AppConstants.defaultEqPresets`.
  static const int presetBandCount = 5;

  AndroidEqualizerParameters? _parameters;

  bool get isSupported => Platform.isAndroid;

  /// Device-reported band parameters, or null if unavailable.
  ///
  /// just_audio only resolves these once the player has connected to the
  /// platform, which does not happen until an audio source is set. Before the
  /// first song is loaded this future never completes, so it is bounded by a
  /// timeout and callers must handle null.
  Future<AndroidEqualizerParameters?> parameters() async {
    if (!isSupported) return null;
    if (_parameters != null) return _parameters;
    try {
      _parameters =
          await _equalizer.parameters.timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
    return _parameters;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    await _equalizer.setEnabled(enabled);
  }

  /// Push a per-device-band gain list (in dB) to the hardware.
  ///
  /// Returns the gains that were actually applied. A device's supported range
  /// can be narrower than an authored preset asks for, so values are clamped —
  /// and the caller must store what came back, not what it sent, or the UI will
  /// display a gain the hardware never accepted.
  Future<List<double>> applyGains(List<double> gains) async {
    final params = await parameters();
    if (params == null) return gains;

    final applied = <double>[];
    for (var i = 0; i < params.bands.length && i < gains.length; i++) {
      final gain = gains[i].clamp(params.minDecibels, params.maxDecibels);
      await params.bands[i].setGain(gain);
      applied.add(gain);
    }
    return applied;
  }

  /// Resample an authored [presetBandCount]-point curve onto the device's bands.
  ///
  /// When the device happens to expose exactly [presetBandCount] bands (the
  /// common case) this is a straight copy. Otherwise the curve is linearly
  /// interpolated across the band positions so the intended shape is preserved.
  List<double> resamplePreset(List<double> curve, int deviceBandCount) {
    if (curve.isEmpty || deviceBandCount <= 0) {
      return List.filled(deviceBandCount < 0 ? 0 : deviceBandCount, 0.0);
    }
    if (curve.length == deviceBandCount) return List<double>.from(curve);
    if (deviceBandCount == 1) return [curve[curve.length ~/ 2]];

    return List<double>.generate(deviceBandCount, (i) {
      // Map band i onto a fractional position within the source curve.
      final t = i * (curve.length - 1) / (deviceBandCount - 1);
      final lower = t.floor();
      final upper = t.ceil();
      if (lower == upper) return curve[lower];
      final fraction = t - lower;
      return curve[lower] + (curve[upper] - curve[lower]) * fraction;
    });
  }

  /// Apply an authored preset curve, resampled to the device's bands.
  Future<void> applyPresetCurve(List<double> curve) async {
    final params = await parameters();
    if (params == null) return;
    await applyGains(resamplePreset(curve, params.bands.length));
  }

  /// Collapse the device's current band gains back into an authored curve, so a
  /// user's hand-tuned settings can be saved as a preset.
  List<double> toPresetCurve(List<double> deviceGains) {
    return resamplePreset(deviceGains, presetBandCount);
  }
}
