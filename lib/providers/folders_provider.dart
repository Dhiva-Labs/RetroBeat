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
