import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/duration_formatter.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/swipe_to_change_track.dart';
import '../../data/models/song_model.dart';
import '../../providers/audio_provider.dart';
import '../../providers/palette_provider.dart';
import '../../providers/settings_provider.dart';
import '../equalizer/equalizer_screen.dart';
import 'queue_sheet.dart';
import 'widgets/visualizer.dart';

/// Full-screen player.
///
/// The background is a wash of one colour sampled from the cover art, fading
/// into the theme surface — enough to make each track feel like its own place
/// without turning the controls into low-contrast decoration.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final song = ref.watch(currentSongProvider);

    if (song == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: Text('Nothing playing')),
      );
    }

    final artColor = ref.watch(artworkAccentProvider).valueOrNull;
    final isRetro = ref.watch(retroModeProvider);
    final style = ref.watch(visualizerStyleProvider);

    // A flowing visualisation takes the whole player, the way WMP's Now Playing
    // pane did. The strip styles stay a strip.
    final isFullBleed = isRetro && style.flows;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (isFullBleed) ...[
            const Visualizer(expand: true),
            // The flow is bright and busy; without this the controls sit on top
            // of moving light and become unreadable.
            const _Scrim(),
          ] else
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    // Tint only the top; the controls sit on the plain surface
                    // below so they stay legible whatever the art happens to be.
                    (artColor ?? scheme.surfaceContainerHigh)
                        .withValues(alpha: 0.55),
                    scheme.surface,
                  ],
                  stops: const [0.0, 0.62],
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(song: song),
                const Spacer(),
                // Swiping the art skips track, which is the gesture people try
                // first; the mini player accepts the same swipe.
                SwipeToChangeTrack(
                  child: Hero(
                    tag: 'album_art_${song.id}',
                    child: Artwork(
                      id: song.id,
                      // Give the flow more room to be seen; the cover is still
                      // the anchor, just not the whole screen.
                      size: isFullBleed ? 230 : 300,
                      radius: 20,
                    ),
                  ),
                ),
                const Spacer(),
                if (isRetro && !style.flows)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Visualizer(),
                  ),
                _TrackInfo(song: song),
                const SizedBox(height: 20),
                const _Seekbar(),
                const SizedBox(height: 8),
                const _Controls(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Darkens the lower half so the controls stay readable over a moving field.
///
/// Ignores pointers, or it would eat the tap that cycles the visualisation.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              // Light at the top and clear through the middle so the flow is
              // actually visible; only the strip under the controls is darkened.
              surface.withValues(alpha: 0.20),
              surface.withValues(alpha: 0.0),
              surface.withValues(alpha: 0.72),
            ],
            stops: const [0.0, 0.40, 0.92],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.song});

  final SongModel song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () => Navigator.pop(context),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Equalizer',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EqualizerScreen()),
          ),
        ),
        IconButton(
          tooltip: 'Queue',
          icon: const Icon(Icons.queue_music_rounded),
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const QueueSheet(),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _TrackInfo extends ConsumerWidget {
  const _TrackInfo({required this.song});

  final SongModel song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            iconSize: 28,
            color: song.isFavorite ? scheme.primary : scheme.onSurfaceVariant,
            icon: Icon(
              song.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
            onPressed: () async {
              await ref.read(mediaRepositoryProvider).toggleFavorite(song.id);
              // Mutated in place, so the list identity must change to rebuild.
              ref.read(songsProvider.notifier).state =
                  List<SongModel>.from(ref.read(songsProvider));
            },
          ),
        ],
      ),
    );
  }
}

class _Seekbar extends ConsumerStatefulWidget {
  const _Seekbar();

  @override
  ConsumerState<_Seekbar> createState() => _SeekbarState();
}

class _SeekbarState extends ConsumerState<_Seekbar> {
  /// While the thumb is held, the slider follows the finger rather than the
  /// player, or it would snap back on every position tick.
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = ref.watch(positionDataProvider).valueOrNull;
    final handler = ref.read(audioHandlerProvider);

    final duration = data?.duration ?? Duration.zero;
    final position = data?.position ?? Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble();
    final value = _dragValue ??
        position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: value,
            max: maxMs > 0 ? maxMs : 1.0,
            onChanged: maxMs > 0 ? (v) => setState(() => _dragValue = v) : null,
            onChangeEnd: (v) {
              handler.seek(Duration(milliseconds: v.round()));
              setState(() => _dragValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(Duration(milliseconds: value.round())),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Text(
                formatDuration(duration),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final handler = ref.read(audioHandlerProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final isShuffled = ref.watch(shuffleModeProvider);
    final repeatMode = ref.watch(repeatModeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Shuffle',
            iconSize: 24,
            color: isShuffled ? scheme.primary : scheme.onSurfaceVariant,
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: () => handler.setShuffleMode(
              isShuffled
                  ? AudioServiceShuffleMode.none
                  : AudioServiceShuffleMode.all,
            ),
          ),
          IconButton(
            iconSize: 40,
            icon: const Icon(Icons.skip_previous_rounded),
            onPressed: handler.skipToPrevious,
          ),
          // The only filled element on the screen: the thing you press most.
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: 38,
              color: scheme.onPrimary,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(isPlaying),
                ),
              ),
              onPressed: isPlaying ? handler.pause : handler.play,
            ),
          ),
          IconButton(
            iconSize: 40,
            icon: const Icon(Icons.skip_next_rounded),
            onPressed: handler.skipToNext,
          ),
          IconButton(
            tooltip: 'Repeat',
            iconSize: 24,
            color: repeatMode == AudioServiceRepeatMode.none
                ? scheme.onSurfaceVariant
                : scheme.primary,
            icon: Icon(
              repeatMode == AudioServiceRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
            ),
            onPressed: () => handler.setRepeatMode(_nextRepeat(repeatMode)),
          ),
        ],
      ),
    );
  }

  /// off -> all -> one -> off
  AudioServiceRepeatMode _nextRepeat(AudioServiceRepeatMode current) {
    return switch (current) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    };
  }
}
