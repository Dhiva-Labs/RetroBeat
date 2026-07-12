import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

/// Background playback: media notification, lockscreen and headset controls.
class RetroBeatAudioHandler extends BaseAudioHandler
    with SeekHandler, QueueHandler {
  /// Audio effects must exist before the player so they can be installed into
  /// its pipeline. On non-Android platforms just_audio ignores the Android
  /// effects list, so this is safe to build unconditionally.
  final AndroidEqualizer _equalizer = AndroidEqualizer();

  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [_equalizer]),
  );

  final ConcatenatingAudioSource _playlist =
      ConcatenatingAudioSource(children: []);

  /// The live equalizer attached to the playback pipeline.
  AndroidEqualizer get equalizer => _equalizer;

  /// The Android audio session the player is writing to.
  ///
  /// The native Visualizer attaches to this to read the spectrum of what is
  /// actually playing. Null until playback starts.
  Stream<int?> get androidAudioSessionIdStream =>
      _player.androidAudioSessionIdStream;

  /// Position, buffered position and duration as one stream, so the seekbar
  /// rebuilds once per tick rather than three times.
  Stream<PositionData> get positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (position, bufferedPosition, duration) => PositionData(
          position: position,
          bufferedPosition: bufferedPosition,
          duration: duration ?? Duration.zero,
        ),
      );

  RetroBeatAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Keep the notification's "now playing" in step with the player.
    _player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
      shuffleMode: _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      repeatMode: switch (_player.loopMode) {
        LoopMode.off => AudioServiceRepeatMode.none,
        LoopMode.one => AudioServiceRepeatMode.one,
        LoopMode.all => AudioServiceRepeatMode.all,
      },
    );
  }

  /// Replace the queue with [items] and cue up [initialIndex].
  Future<void> loadPlaylist(
    List<MediaItem> items, {
    int initialIndex = 0,
  }) async {
    queue.add(items);

    await _playlist.clear();
    await _playlist.addAll([
      for (final item in items) AudioSource.uri(Uri.parse(item.id), tag: item),
    ]);

    await _player.setAudioSource(
      _playlist,
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
  }

  /// Move a queued track. [newIndex] is the final resting index, as supplied by
  /// `ReorderableListView.onReorderItem`.
  ///
  /// The audio source and the queue metadata are separate lists that must be
  /// kept in step, or the notification would show one track while another plays.
  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    final items = List<MediaItem>.from(queue.value);
    if (oldIndex < 0 || oldIndex >= items.length) return;

    final target = newIndex.clamp(0, items.length - 1);
    if (oldIndex == target) return;

    await _playlist.move(oldIndex, target);
    items.insert(target, items.removeAt(oldIndex));
    queue.add(items);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        await _player.setLoopMode(LoopMode.all);
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    switch (shuffleMode) {
      case AudioServiceShuffleMode.none:
        await _player.setShuffleModeEnabled(false);
        break;
      case AudioServiceShuffleMode.all:
      case AudioServiceShuffleMode.group:
        await _player.setShuffleModeEnabled(true);
        break;
    }
  }
}

/// Data class for combined position information
class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData({
    required this.position,
    required this.bufferedPosition,
    required this.duration,
  });
}
