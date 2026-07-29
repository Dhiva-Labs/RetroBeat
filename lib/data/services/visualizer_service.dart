import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/platform_info.dart';

/// One frame of analysis: the spectrum and the waveform of the same instant.
///
/// Both travel together because the styles want different things — the bar
/// styles read [bands], the oscilloscope styles read [wave] — and splitting them
/// across two events would let them drift a frame apart.
class VisualizerFrame {
  const VisualizerFrame({required this.bands, required this.wave});

  /// Per-band magnitudes, 0..1, low frequency first.
  final List<double> bands;

  /// PCM samples normalised to -1..1.
  final List<double> wave;

  static const int bandCount = 24;
  static const int wavePoints = 96;

  static VisualizerFrame silent = VisualizerFrame(
    bands: List.filled(bandCount, 0),
    wave: List.filled(wavePoints, 0),
  );
}

/// Spectrum and waveform of the audio that is actually playing.
///
/// Backed by `android.media.audiofx.Visualizer`, which Android gates behind the
/// RECORD_AUDIO permission even though the audio being analysed is our own
/// playback. Nothing is recorded or stored — the bytes go straight to the
/// painter and are discarded — but the permission is unavoidable, which is why
/// this is opt-in and the procedural animation is the default.
class VisualizerService {
  static const _channel = EventChannel('retrobeat/visualizer');

  bool get isSupported => PlatformInfo.isAndroid;

  /// Ask for the permission the platform API requires.
  ///
  /// Called only when the user turns the setting on, never at launch.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    return Permission.microphone.isGranted;
  }

  /// Frames at roughly display rate.
  ///
  /// Errors rather than hanging if the session cannot be captured, so callers
  /// can fall back to the animation.
  Stream<VisualizerFrame> frames(int sessionId) {
    return _channel
        .receiveBroadcastStream({'sessionId': sessionId}).map((event) {
      final map = event as Map;
      return VisualizerFrame(
        bands: (map['bands'] as List).cast<double>(),
        wave: (map['wave'] as List).cast<double>(),
      );
    });
  }
}
