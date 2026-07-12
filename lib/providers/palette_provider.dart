import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import 'artwork_provider.dart';
import 'audio_provider.dart';

/// A colour pulled from the current track's cover art, used to tint the player
/// background. Null when the track has no art, in which case the player should
/// fall back to the theme rather than invent a colour.
final artworkAccentProvider = FutureProvider<Color?>((ref) async {
  final song = ref.watch(currentSongProvider);
  if (song == null) return null;

  // Reuse the bytes the artwork widgets already fetched rather than querying
  // MediaStore a second time for the same image.
  final bytes = await ref.watch(artworkProvider(song.id).future);
  if (bytes == null || bytes.isEmpty) return null;

  final palette = await PaletteGenerator.fromImageProvider(
    MemoryImage(bytes),
    // Small sample: we want one representative colour, not an exact histogram,
    // and this runs on every track change.
    size: const Size(120, 120),
    maximumColorCount: 8,
  );

  return palette.darkVibrantColor?.color ??
      palette.vibrantColor?.color ??
      palette.dominantColor?.color;
});
