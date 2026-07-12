import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../providers/artwork_provider.dart';
import '../theme/app_theme.dart';

/// Album art, with a neutral placeholder when a track has none.
///
/// The placeholder is a plain surface with a muted glyph rather than a coloured
/// gradient: in a list of fifty songs, fifty coloured tiles is noise, and it
/// makes the handful of tracks that *do* have art harder to pick out.
class Artwork extends ConsumerWidget {
  const Artwork({
    super.key,
    required this.id,
    this.size = 48,
    this.radius = AppRadius.artwork,
    this.type = ArtworkType.AUDIO,
  });

  final int id;
  final double size;
  final double radius;
  final ArtworkType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = ref.watch(artworkProvider(id)).valueOrNull;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes == null || bytes.isEmpty
            ? ColoredBox(
                color: scheme.surfaceContainerHigh,
                child: Icon(
                  type == ArtworkType.ARTIST
                      ? Icons.person_rounded
                      : Icons.music_note_rounded,
                  size: size * 0.42,
                  color: scheme.outline,
                ),
              )
            : Image.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                // Hold the previous frame until the next one has decoded, so
                // changing track does not blink through a blank box.
                gaplessPlayback: true,
              ),
      ),
    );
  }
}
