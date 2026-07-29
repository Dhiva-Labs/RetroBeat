import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/storage_service.dart';

/// Every folder the last scan found, mapped to its song count — including
/// folders currently excluded, so the Folders screen can still offer to turn
/// them back on. Refreshed by [LibraryLoader] after each scan.
final knownFoldersProvider = StateProvider<Map<String, int>>((ref) => {});

/// Folders the user has asked to leave out of their library.
final excludedFoldersProvider =
    StateNotifierProvider<ExcludedFoldersNotifier, Set<String>>((ref) {
  return ExcludedFoldersNotifier();
});

class ExcludedFoldersNotifier extends StateNotifier<Set<String>> {
  ExcludedFoldersNotifier() : super(_load());

  static const _key = 'excluded_folders';

  static Set<String> _load() {
    final saved = StorageService.getSetting<List<dynamic>>(_key);
    return saved?.cast<String>().toSet() ?? {};
  }

  Future<void> setExcluded(String folder, bool excluded) async {
    final next = Set<String>.from(state);
    if (excluded) {
      next.add(folder);
    } else {
      next.remove(folder);
    }
    state = next;
    await StorageService.setSetting(_key, next.toList());
  }
}

/// Folders the user has picked to scan for music — desktop only.
///
/// There is no MediaStore off Android: the library is exactly the audio
/// reachable from these folders, so this is additive (pick a folder to grow
/// the library) rather than [excludedFoldersProvider]'s subtractive model
/// (start from everything MediaStore knows about, opt specific folders out).
final desktopScanFoldersProvider =
    StateNotifierProvider<DesktopScanFoldersNotifier, List<String>>((ref) {
  return DesktopScanFoldersNotifier();
});

class DesktopScanFoldersNotifier extends StateNotifier<List<String>> {
  DesktopScanFoldersNotifier() : super(_load());

  static const _key = 'desktop_scan_folders';

  static List<String> _load() {
    final saved = StorageService.getSetting<List<dynamic>>(_key);
    return saved?.cast<String>().toList() ?? [];
  }

  Future<void> _persist() async {
    await StorageService.setSetting(_key, state);
  }

  Future<void> addFolder(String folder) async {
    if (state.contains(folder)) return;
    state = [...state, folder]..sort();
    await _persist();
  }

  Future<void> removeFolder(String folder) async {
    if (!state.contains(folder)) return;
    state = state.where((f) => f != folder).toList();
    await _persist();
  }
}
