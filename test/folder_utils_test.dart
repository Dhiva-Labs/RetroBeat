import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/core/utils/folder_utils.dart';

void main() {
  group('folderOf', () {
    test('returns the containing directory', () {
      expect(
        folderOf('/storage/emulated/0/Music/Song.mp3'),
        '/storage/emulated/0/Music',
      );
    });

    test('null for a path with no directory component', () {
      expect(folderOf('Song.mp3'), null);
    });

    test('null for null or empty input', () {
      expect(folderOf(null), null);
      expect(folderOf(''), null);
    });
  });

  group('isFolderExcluded', () {
    test('matches the excluded folder itself', () {
      expect(isFolderExcluded('/Music/Ringtones', {'/Music/Ringtones'}), true);
    });

    test('matches a subfolder of an excluded folder', () {
      expect(
        isFolderExcluded(
          '/WhatsApp/Media/Voice Notes',
          {'/WhatsApp/Media'},
        ),
        true,
      );
    });

    test(
      'does not match a folder that merely shares a prefix string',
      () {
        // /Music/Rock must not be excluded by an exclusion of /Music/Ro —
        // string startsWith without the trailing slash would wrongly match.
        expect(
          isFolderExcluded('/Music/Rock', {'/Music/Ro'}),
          false,
        );
      },
    );

    test('unrelated folders are not excluded', () {
      expect(isFolderExcluded('/Music/Jazz', {'/Music/Ringtones'}), false);
    });

    test('empty exclusion set excludes nothing', () {
      expect(isFolderExcluded('/Music/Jazz', {}), false);
    });
  });

  group('folderLeafName', () {
    test('returns the last path segment', () {
      expect(folderLeafName('/storage/emulated/0/Music/Artist'), 'Artist');
    });

    test('a path with no slash is its own leaf', () {
      expect(folderLeafName('Music'), 'Music');
    });
  });

  group('folderParentLabel', () {
    test('strips the primary storage root', () {
      expect(
        folderParentLabel('/storage/emulated/0/Music/Artist'),
        'Music',
      );
    });

    test('a folder directly under the root reads as Internal storage', () {
      expect(
        folderParentLabel('/storage/emulated/0/Music'),
        'Internal storage',
      );
    });

    test('paths outside the known roots are left alone', () {
      expect(
        folderParentLabel('/storage/1234-5678/Music/Artist'),
        '/storage/1234-5678/Music',
      );
    });
  });
}
