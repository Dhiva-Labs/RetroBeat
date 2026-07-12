import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:retro_beat/data/services/equalizer_service.dart';

/// The preset curves are authored as 5 points, but the number of bands is
/// decided by the device — so resampling is the piece that has to be right, or
/// a "Bass Boost" preset lands on the wrong frequencies.
void main() {
  final service = EqualizerService(AndroidEqualizer());

  group('resamplePreset', () {
    test('copies the curve when the device has exactly as many bands', () {
      final curve = [5.0, 3.5, 0.0, -2.0, -4.0];
      expect(service.resamplePreset(curve, 5), curve);
    });

    test('stretches a 5-point curve across more bands', () {
      final result = service.resamplePreset([0, 10, 0, 0, 0], 9);

      expect(result, hasLength(9));
      // The authored points must survive at their proportional positions.
      expect(result.first, 0);
      expect(result[2], 10); // second authored point, now at index 2 of 9
      expect(result.last, 0);
      // And the gap between them is bridged, not left as a step.
      expect(result[1], closeTo(5, 0.001));
    });

    test('squeezes a 5-point curve into fewer bands', () {
      final result = service.resamplePreset([0, 0, 6, 0, 0], 3);

      expect(result, hasLength(3));
      expect(result, [0, 6, 0]);
    });

    test('keeps the middle of the curve when the device reports one band', () {
      expect(service.resamplePreset([1, 2, 9, 4, 5], 1), [9]);
    });

    test('returns flat gains for an empty curve', () {
      expect(service.resamplePreset([], 4), [0.0, 0.0, 0.0, 0.0]);
    });

    test('returns nothing when the device reports no bands', () {
      expect(service.resamplePreset([1, 2, 3, 4, 5], 0), isEmpty);
    });
  });

  test('toPresetCurve collapses device gains back to 5 authored points', () {
    final curve = service.toPresetCurve([1, 2, 3, 4, 5, 6, 7, 8, 9]);

    expect(curve, hasLength(EqualizerService.presetBandCount));
    expect(curve.first, 1);
    expect(curve.last, 9);
  });

  test('a curve survives a round trip through a 10-band device', () {
    final original = [6.0, 3.0, 0.0, -3.0, -6.0];
    final onDevice = service.resamplePreset(original, 10);

    expect(service.toPresetCurve(onDevice), original);
  });
}
