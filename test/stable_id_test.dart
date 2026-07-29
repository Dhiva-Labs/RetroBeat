import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/core/utils/stable_id.dart';

/// This id is a persisted Hive key (for desktop-scanned songs, and reusable
/// as-is for anything else keyed by a path or URL), so what matters is not
/// the exact numbers but that they stay put across calls and never go
/// negative.
void main() {
  group('stableIdFor', () {
    test('is deterministic for the same input', () {
      const path = '/home/user/Music/Artist/Song.mp3';
      expect(stableIdFor(path), stableIdFor(path));
    });

    test('differs across different input', () {
      expect(
        stableIdFor('/Music/A.mp3'),
        isNot(stableIdFor('/Music/B.mp3')),
      );
    });

    test('is always non-negative', () {
      for (final key in ['/a', '/b/c.flac', 'relative/path.wav', '']) {
        expect(stableIdFor(key), greaterThanOrEqualTo(0));
      }
    });
  });
}
