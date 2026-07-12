import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/data/models/playlist_model.dart';

/// `reorderSongs` takes indices in `ReorderableListView.onReorderItem` form,
/// i.e. [newIndex] is the final resting position and is *already* adjusted for
/// the removal of [oldIndex]. It previously adjusted a second time, which
/// dropped items one slot off whenever you dragged downwards.
void main() {
  PlaylistModel playlist(List<int> ids) => PlaylistModel(
        id: 'p',
        name: 'Test',
        songIds: [...ids],
      );

  test('moves an item downwards to the given index', () {
    final p = playlist([1, 2, 3, 4]);
    p.reorderSongs(0, 2);
    expect(p.songIds, [2, 3, 1, 4]);
  });

  test('moves an item upwards to the given index', () {
    final p = playlist([1, 2, 3, 4]);
    p.reorderSongs(3, 1);
    expect(p.songIds, [1, 4, 2, 3]);
  });

  test('moving to the end keeps every song', () {
    final p = playlist([1, 2, 3]);
    p.reorderSongs(0, 2);
    expect(p.songIds, [2, 3, 1]);
  });

  test('a no-op move leaves the order untouched', () {
    final p = playlist([1, 2, 3]);
    p.reorderSongs(1, 1);
    expect(p.songIds, [1, 2, 3]);
  });

  test('an out-of-range source index is ignored rather than throwing', () {
    final p = playlist([1, 2, 3]);
    p.reorderSongs(9, 0);
    expect(p.songIds, [1, 2, 3]);
  });

  test('an out-of-range target is clamped instead of throwing', () {
    final p = playlist([1, 2, 3]);
    p.reorderSongs(0, 99);
    expect(p.songIds, [2, 3, 1]);
  });
}
