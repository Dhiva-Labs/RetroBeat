import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A stable numeric id for a song that has no database row to number it.
///
/// Android's `id` comes from MediaStore; nothing plays that role for a file
/// found by walking the filesystem (desktop scanning, or a WebDAV listing),
/// so this derives one from the thing that *is* stable across rescans: the
/// file's own path (or, for a remote file, its URL).
///
/// `String.hashCode` was the obvious shortcut and deliberately not used here —
/// the language spec never promises it stays the same across Dart versions,
/// and this id is a persisted Hive key, not a throwaway in-memory value.
///
/// Truncated to 32 bits, not 63: Hive's own integer keys are required to fall
/// within 0 - 0xFFFFFFFF (`Frame.assertKey`) regardless of Dart's native int
/// width, and it throws rather than clamping. That leaves a ~4.3 billion-value
/// space — collisions are effectively impossible for any real music library,
/// but not for a much larger one; a truly collision-proof scheme would need a
/// String key instead, which is a bigger change than this port makes.
int stableIdFor(String key) {
  final digest = md5.convert(utf8.encode(key));
  var id = 0;
  for (var i = 0; i < 4; i++) {
    id = (id << 8) | digest.bytes[i];
  }
  return id & 0xFFFFFFFF;
}
