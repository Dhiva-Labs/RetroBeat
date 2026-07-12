import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/swipe_to_change_track.dart';
import '../../../providers/audio_provider.dart';
import '../../player/now_playing_screen.dart';

/// The persistent bar above the tab bar.
///
/// Nothing here watches the position stream except [_MiniProgressBar]. When the
/// whole bar rebuilt on every tick it took the album art with it, and the art
/// re-queried and flashed its placeholder five times a second.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(currentSongProvider);
    if (currentSong == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final isPlaying = ref.watch(isPlayingProvider);
    final handler = ref.read(audioHandlerProvider);

    return Material(
      color: scheme.surfaceContainer,
      child: SwipeToChangeTrack(
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, animation, __) => const NowPlayingScreen(),
              transitionsBuilder: (_, animation, __, child) => SlideTransition(
                position:
                    Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                        .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
              transitionDuration: const Duration(milliseconds: 320),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _MiniProgressBar(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Artwork(id: currentSong.id, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentSong.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentSong.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: handler.skipToPrevious,
                      icon: const Icon(Icons.skip_previous_rounded),
                      iconSize: 28,
                    ),
                    IconButton(
                      onPressed: isPlaying ? handler.pause : handler.play,
                      iconSize: 34,
                      color: scheme.primary,
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_filled_rounded,
                          key: ValueKey(isPlaying),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: handler.skipToNext,
                      icon: const Icon(Icons.skip_next_rounded),
                      iconSize: 28,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The only part of the mini player that follows the position stream.
class _MiniProgressBar extends ConsumerWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(positionDataProvider).valueOrNull;
    final duration = data?.duration ?? Duration.zero;
    final position = data?.position ?? Duration.zero;

    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return LinearProgressIndicator(
      value: progress.clamp(0.0, 1.0),
      minHeight: 2,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
