import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/visualizer_service.dart';
import 'audio_provider.dart';
import 'settings_provider.dart';

final visualizerServiceProvider = Provider<VisualizerService>((ref) {
  return VisualizerService();
});

/// The audio session the player is writing to, or null before playback starts.
final audioSessionIdProvider = StreamProvider<int?>((ref) {
  return ref.watch(audioHandlerProvider).androidAudioSessionIdStream;
});

/// Real analysis of the playing audio, or null when we are not running
/// audio-reactive.
///
/// Null is meaningful: it tells the visualiser to fall back to its procedural
/// animation rather than draw a flat, dead frame.
final visualizerFrameProvider = StreamProvider<VisualizerFrame?>((ref) {
  if (!ref.watch(audioReactiveVisualizerProvider)) {
    return Stream.value(null);
  }

  final sessionId = ref.watch(audioSessionIdProvider).valueOrNull;
  if (sessionId == null || sessionId == 0) {
    return Stream.value(null);
  }

  return ref
      .watch(visualizerServiceProvider)
      .frames(sessionId)
      .map<VisualizerFrame?>((frame) => frame)
      // If the platform refuses (permission revoked, session not capturable),
      // degrade to the animation instead of taking the player down.
      .handleError((_) {});
});
