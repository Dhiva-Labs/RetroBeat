import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/server_providers.dart';

/// One directory's contents on one server: folders first, then files, both
/// alphabetically — the order every listing in this feature displays and
/// queues playback from.
///
/// Reactive to the session map (not just read once), so a server that
/// disconnects mid-browse turns into a proper error state here instead of a
/// stale listing that looks live.
final directoryListingProvider = FutureProvider.autoDispose
    .family<List<WebDavEntry>, ({String serverId, String path})>(
        (ref, key) async {
  final session = ref.watch(serverSessionsProvider)[key.serverId];
  if (session == null || !session.isConnected) {
    throw StateError('This server is not connected.');
  }

  final entries = await session.client!.list(key.path);
  entries.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return entries;
});

/// [describeServerError] plus the one failure this provider raises itself (a
/// disconnected server) — a [StateError], not a [WebDavException], so it is
/// not something that function already knows how to word.
String describeDirectoryError(Object error) {
  if (error is StateError) return error.message;
  return describeServerError(error);
}
