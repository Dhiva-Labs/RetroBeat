import 'dart:typed_data';

/// Embedded cover art pulled out of a file's tags during a desktop library
/// scan, keyed by song id.
///
/// There is no MediaStore to hand artwork back by id outside Android, so
/// [MediaRepository.scanDesktopSongs] reads the picture straight out of each
/// file's tags while it already has them open, and [artworkProvider] serves
/// the bytes from here instead of re-opening the file.
///
/// Purely in memory: it is rebuilt by the scan that already runs on every
/// launch, the same way the Android path re-queries MediaStore every time
/// rather than persisting a copy of what it found.
class DesktopArtworkCache {
  DesktopArtworkCache._();

  static final Map<int, Uint8List?> _bytes = {};

  static Uint8List? get(int songId) => _bytes[songId];

  static void put(int songId, Uint8List? bytes) {
    _bytes[songId] = bytes;
  }

  static void clear() => _bytes.clear();
}
