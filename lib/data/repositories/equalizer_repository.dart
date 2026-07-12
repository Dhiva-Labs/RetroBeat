import 'package:uuid/uuid.dart';
import '../models/eq_preset_model.dart';
import '../services/storage_service.dart';
import '../../core/constants/app_constants.dart';

/// Persistence for equalizer settings and presets.
///
/// This stores what the user chose; applying it to the audio pipeline is
/// [EqualizerService]'s job.
class EqualizerRepository {
  static const _uuid = Uuid();

  /// Get all EQ presets
  List<EqPresetModel> getAllPresets() {
    return StorageService.eqPresetsBox.values.toList();
  }

  /// Create a custom EQ preset
  Future<EqPresetModel> createCustomPreset({
    required String name,
    required List<double> bandLevels,
  }) async {
    final preset = EqPresetModel(
      id: _uuid.v4(),
      name: name,
      bandLevels: bandLevels,
      isCustom: true,
    );
    await StorageService.eqPresetsBox.put(preset.id, preset);
    return preset;
  }

  /// Delete a custom preset
  Future<void> deletePreset(String id) async {
    final preset = StorageService.eqPresetsBox.get(id);
    if (preset != null && preset.isCustom) {
      await StorageService.eqPresetsBox.delete(id);
    }
  }

  /// Get the active EQ preset ID
  String? getActivePresetId() {
    return StorageService.getSetting<String>(AppConstants.activeEqPreset);
  }

  /// Set the active EQ preset
  Future<void> setActivePreset(String presetId) async {
    await StorageService.setSetting(AppConstants.activeEqPreset, presetId);
  }

  /// Get EQ enabled state
  bool isEqEnabled() {
    return StorageService.getSetting<bool>(AppConstants.eqEnabled) ?? false;
  }

  /// Set EQ enabled state
  Future<void> setEqEnabled(bool enabled) async {
    await StorageService.setSetting(AppConstants.eqEnabled, enabled);
  }

  /// The user's current per-band gains, in dB.
  ///
  /// Length matches the band count of the device this was saved on, so it is
  /// discarded if the device now reports a different number of bands.
  List<double>? getSavedGains(int expectedBandCount) {
    final saved = StorageService.getSetting<List<dynamic>>(
      AppConstants.eqBandGains,
    );
    if (saved == null || saved.length != expectedBandCount) return null;
    return saved.cast<num>().map((g) => g.toDouble()).toList();
  }

  Future<void> setSavedGains(List<double> gains) async {
    await StorageService.setSetting(AppConstants.eqBandGains, gains);
  }

  /// Clear the active preset, e.g. once the user hand-tunes a band away from it.
  Future<void> clearActivePreset() async {
    await StorageService.setSetting(AppConstants.activeEqPreset, null);
  }
}
