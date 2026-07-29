/// One file or folder on a WebDAV server, as reported by PROPFIND.
///
/// Everything except [name], [path] and [isDir] is optional because servers
/// vary in what they report: a directory usually has no length, and plenty of
/// servers omit the content type. The UI must treat nulls as "unknown", not as
/// zero or empty.
class WebDavEntry {
  const WebDavEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
    this.contentType,
    this.lastModified,
  });

  /// The last path segment, decoded — `Björk — Jóga.flac`, not
  /// `Bj%C3%B6rk%20%E2%80%94%20J%C3%B3ga.flac`.
  final String name;

  /// Absolute path within the server, decoded, with a leading slash and no
  /// trailing one. Pass it straight back to any client method.
  final String path;

  final bool isDir;

  /// Bytes, or null for a collection or a server that did not say.
  final int? size;

  final String? contentType;

  final DateTime? lastModified;

  /// Path of the containing folder, or `/` at the root.
  String get parentPath {
    final cut = path.lastIndexOf('/');
    if (cut <= 0) return '/';
    return path.substring(0, cut);
  }

  /// Lowercased extension without the dot, or the empty string. Used to pick
  /// out playable files without trusting the content type, which many servers
  /// report as `application/octet-stream` for everything.
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebDavEntry && other.path == path && other.isDir == isDir;

  @override
  int get hashCode => Object.hash(path, isDir);

  @override
  String toString() => 'WebDavEntry(${isDir ? 'dir' : 'file'} $path)';
}

/// An open download: the body, still on the wire.
///
/// [stream] is single-subscription and must be consumed or cancelled —
/// dropping it holds the connection open. [contentLength] is null when the
/// server used chunked encoding.
class WebDavDownload {
  const WebDavDownload({
    required this.stream,
    this.contentLength,
    this.contentType,
    this.isPartial = false,
  });

  final Stream<List<int>> stream;
  final int? contentLength;
  final String? contentType;

  /// True when the server honoured a Range request and answered 206, so the
  /// body is a slice rather than the whole file.
  final bool isPartial;
}

/// What a player needs to stream a remote file directly.
///
/// The credential rides in [headers], never in [url]: userinfo in a URL leaks
/// into logs, `toString`s and media-player caches, and several players strip
/// it before connecting anyway.
class RemoteStreamSpec {
  const RemoteStreamSpec({required this.url, required this.headers});

  final Uri url;

  /// Includes `Authorization`. Pass as-is to the player; do not print.
  final Map<String, String> headers;

  /// Deliberately lists header *names* only — printing this must never expose
  /// the credential.
  @override
  String toString() =>
      'RemoteStreamSpec($url, headers: ${headers.keys.join(', ')})';
}
