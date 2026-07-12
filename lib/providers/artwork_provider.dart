import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// Cover art bytes for a song, fetched once and cached.
///
/// This exists because `QueryArtworkWidget` builds its `FutureBuilder` future
/// inside `build()`: every rebuild starts a *new* MediaStore query, which resets
/// the builder to null and flashes the placeholder before the image comes back.
/// Anything rebuilding on the position tick — the mini player did, ~5x a second
/// — therefore flickered continuously while playing. Reading from a provider
/// means a rebuild reuses the cached bytes instead of re-querying.
final artworkProvider =
    FutureProvider.autoDispose.family<Uint8List?, int>((ref, songId) async {
  // Hold the art for a little while after it scrolls out of view, so flicking
  // back up a long list does not re-hit MediaStore for every row.
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(timer.cancel);

  return OnAudioQuery().queryArtwork(
    songId,
    ArtworkType.AUDIO,
    size: 400,
  );
});
