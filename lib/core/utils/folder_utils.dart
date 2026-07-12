/// The folder a media file lives in, derived from its absolute path.
///
/// Null when there is no usable path (e.g. content URIs with no filesystem
/// path behind them) — nothing to exclude by folder in that case.
String? folderOf(String? path) {
  if (path == null || path.isEmpty) return null;
  final idx = path.lastIndexOf('/');
  if (idx <= 0) return null;
  return path.substring(0, idx);
}

/// Whether [folder] should be skipped.
///
/// Matches the folder itself and anything nested under it, so excluding a
/// parent folder (say, all of `WhatsApp/Media`) also excludes its
/// subfolders without the user having to list each one individually.
bool isFolderExcluded(String folder, Set<String> excludedFolders) {
  for (final excluded in excludedFolders) {
    if (folder == excluded || folder.startsWith('$excluded/')) return true;
  }
  return false;
}

/// The leaf directory name, e.g. `Album` from `/Music/Artist/Album`.
String folderLeafName(String folder) {
  final idx = folder.lastIndexOf('/');
  return idx == -1 ? folder : folder.substring(idx + 1);
}

/// The parent of [folder], with the common Android storage root stripped so
/// paths read as `Music/Artist` instead of
/// `/storage/emulated/0/Music/Artist`.
String folderParentLabel(String folder) {
  final idx = folder.lastIndexOf('/');
  final parent = idx <= 0 ? '/' : folder.substring(0, idx);

  const roots = ['/storage/emulated/0', '/storage/self/primary'];
  for (final root in roots) {
    if (parent == root) return 'Internal storage';
    if (parent.startsWith('$root/')) return parent.substring(root.length + 1);
  }
  return parent;
}
