import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/storage_service.dart';

/// The library views the user can put in the top tab bar.
enum LibraryTab {
  tracks('Tracks', Icons.music_note_rounded),
  albums('Albums', Icons.album_rounded),
  artists('Artists', Icons.person_rounded),
  playlists('Playlists', Icons.queue_music_rounded),
  liked('Liked', Icons.favorite_rounded),
  genres('Genres', Icons.category_rounded),
  groups('Groups', Icons.folder_rounded);

  const LibraryTab(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Tabs the user cannot hide. Keeping the core views permanent means the
  /// app can never be configured into a state with nothing to play.
  bool get isPermanent =>
      this == LibraryTab.tracks || this == LibraryTab.playlists;
}

/// Shown out of the box.
///
/// Four, not all seven. A tab bar you have to scroll to read is not a menu, it
/// is a haystack — the rest are one toggle away in Settings.
const _defaultVisible = <LibraryTab>[
  LibraryTab.tracks,
  LibraryTab.albums,
  LibraryTab.artists,
  LibraryTab.playlists,
];

const _storageKey = 'visible_tabs';

final visibleTabsProvider =
    StateNotifierProvider<VisibleTabsNotifier, List<LibraryTab>>((ref) {
  return VisibleTabsNotifier();
});

class VisibleTabsNotifier extends StateNotifier<List<LibraryTab>> {
  VisibleTabsNotifier() : super(_load());

  static List<LibraryTab> _load() {
    final saved = StorageService.getSetting<List<dynamic>>(_storageKey);
    if (saved == null) return _defaultVisible;

    final tabs = saved
        .cast<String>()
        .map((name) => LibraryTab.values.asNameMap()[name])
        .whereType<LibraryTab>()
        .toList();

    // A stored list from an older build may predate a tab, or omit a permanent
    // one; rather than trust it blindly, repair it.
    for (final tab in LibraryTab.values.where((t) => t.isPermanent)) {
      if (!tabs.contains(tab)) tabs.insert(0, tab);
    }
    return tabs.isEmpty ? _defaultVisible : tabs;
  }

  Future<void> _persist() async {
    await StorageService.setSetting(
      _storageKey,
      state.map((t) => t.name).toList(),
    );
  }

  Future<void> setVisible(LibraryTab tab, bool visible) async {
    if (tab.isPermanent && !visible) return;
    if (visible == state.contains(tab)) return;

    if (visible) {
      // Insert in canonical order so toggling a tab on does not send it to the
      // end of an otherwise ordered bar.
      final next = [...state, tab]..sort((a, b) => a.index.compareTo(b.index));
      state = next;
    } else {
      state = state.where((t) => t != tab).toList();
    }
    await _persist();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final next = [...state];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    state = next;
    await _persist();
  }
}
