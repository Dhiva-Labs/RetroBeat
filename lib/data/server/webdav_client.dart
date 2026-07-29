import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../core/constants/app_constants.dart';
import '../models/server_config_model.dart';
import 'credential_vault.dart';
import 'webdav_entry.dart';
import 'webdav_exceptions.dart';

export 'webdav_entry.dart';
export 'webdav_exceptions.dart';

/// Supplies the password for the next request, or null if none is stored.
///
/// Called per request rather than once at construction, so the password is
/// never held in a field and a change in the keychain takes effect without
/// rebuilding the client.
typedef SecretResolver = Future<String?> Function();

/// A WebDAV client with only the verbs this app needs.
///
/// Three constraints shape it:
///
/// * **Nothing is buffered.** [download] hands back the live body stream and
///   [upload] sends one, so a 300 MB file costs a socket buffer, not 300 MB.
/// * **Credentials are per-request.** The Basic header is built from a
///   [SecretResolver] at call time and never stored, logged, or put in a URL.
/// * **Namespaces are not assumed.** Servers answer PROPFIND with `D:`, `d:`,
///   `lp1:` or no prefix at all, so parsing matches on local names only.
///
/// Every method throws [WebDavException] subtypes. Methods that need the
/// password may also throw [VaultUnavailableException], which is left
/// untranslated because "your keychain is missing" is a different problem from
/// "the server said no" and deserves its own message.
class WebDavClient {
  WebDavClient({
    required Uri baseUrl,
    required this.username,
    required SecretResolver secret,
    http.Client? httpClient,
    this.requestTimeout = AppConstants.webDavRequestTimeout,
  })  : _baseUrl = baseUrl,
        _secret = secret,
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// The client a [ServerConfigModel] describes, reading its password from
  /// [vault] on every request.
  factory WebDavClient.forConfig(
    ServerConfigModel config,
    CredentialVault vault, {
    http.Client? httpClient,
    Duration requestTimeout = AppConstants.webDavRequestTimeout,
  }) {
    return WebDavClient(
      baseUrl: config.baseUri,
      username: config.username,
      secret: () => vault.read(config.id),
      httpClient: httpClient,
      requestTimeout: requestTimeout,
    );
  }

  final Uri _baseUrl;
  final String username;
  final SecretResolver _secret;
  final http.Client _http;
  final bool _ownsHttp;

  /// Caps requests that only exchange headers or a small XML body, plus the
  /// header phase of a download. Bodies are not capped: a transfer takes as
  /// long as the file is, and a deadline there would kill working downloads.
  final Duration requestTimeout;

  static const _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<propfind xmlns="DAV:"><prop>'
      '<displayname/><getcontentlength/><getcontenttype/>'
      '<getlastmodified/><resourcetype/>'
      '</prop></propfind>';

  /// Absolute URL for a server-relative [path], percent-encoding each segment.
  ///
  /// Segments are encoded individually, so spaces, `#`, `%` and non-ASCII
  /// names survive intact — building the URL by string concatenation is what
  /// makes `Song #1 (100%).mp3` unreachable.
  Uri resolveUrl(String path, {bool asCollection = false}) {
    final segments = <String>[
      ..._baseUrl.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/').where((s) => s.isNotEmpty),
    ];
    if (asCollection) segments.add('');
    return _baseUrl.replace(pathSegments: segments);
  }

  /// The server-relative, decoded path an `href` from a PROPFIND response
  /// refers to.
  ///
  /// Strips whatever path prefix the base URL carries, so a Nextcloud href of
  /// `/remote.php/dav/files/me/Music` comes back as `/Music`.
  String pathFromHref(String href) {
    Uri uri;
    try {
      uri = Uri.parse(href);
    } on FormatException {
      // Some servers emit raw spaces or UTF-8 in href, which is not a legal
      // URI reference. Encode first, then parse.
      uri = Uri.parse(Uri.encodeFull(href));
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final baseSegments =
        _baseUrl.pathSegments.where((s) => s.isNotEmpty).toList();
    var start = 0;
    if (segments.length >= baseSegments.length) {
      var matches = true;
      for (var i = 0; i < baseSegments.length; i++) {
        if (segments[i] != baseSegments[i]) {
          matches = false;
          break;
        }
      }
      if (matches) start = baseSegments.length;
    }
    return normalizePath('/${segments.sublist(start).join('/')}');
  }

  /// Leading slash, no trailing slash, `/` for the root — the one shape every
  /// method here compares against.
  static String normalizePath(String path) {
    var value = path.trim();
    if (!value.startsWith('/')) value = '/$value';
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// `dir` + `name`, with exactly one slash between them.
  static String joinPath(String dir, String name) {
    final base = normalizePath(dir);
    final leaf = name.startsWith('/') ? name.substring(1) : name;
    return base == '/' ? '/$leaf' : '$base/$leaf';
  }

  /// Everything after the last slash.
  static String basename(String path) {
    final normalized = normalizePath(path);
    final cut = normalized.lastIndexOf('/');
    return cut < 0 ? normalized : normalized.substring(cut + 1);
  }

  /// Proves the server is reachable, speaks WebDAV and accepts the stored
  /// credentials — and that [path] exists, since a correct login against a
  /// mistyped folder is the more common mistake.
  Future<void> testConnection({String path = '/'}) async {
    final request = http.Request(
      'OPTIONS',
      resolveUrl(path, asCollection: true),
    )..headers.addAll(await _authHeaders());
    final response = await _sendBuffered(request, 'OPTIONS', path);
    if (response.statusCode >= 400) {
      _throwForStatus(response.statusCode, 'OPTIONS', path);
    }
    if (await stat(path) == null) {
      throw WebDavNotFoundException(
        'The server is reachable but has no folder at $path.',
        statusCode: 404,
        path: path,
      );
    }
  }

  /// The direct children of [path], with the folder's own entry removed.
  ///
  /// A depth-1 PROPFIND always includes the collection itself; leaving it in
  /// gives the UI a folder that contains itself.
  Future<List<WebDavEntry>> list(String path) async {
    final target = normalizePath(path);
    final body = await _propfind(target, depth: 1, asCollection: true);
    return _parseMultistatus(body).where((e) => e.path != target).toList();
  }

  /// [path] itself, or null if it is not there.
  ///
  /// Used to verify a completed upload, so absence must not throw — callers
  /// tell "gone" from "unreachable" by null versus exception.
  Future<WebDavEntry?> stat(String path) async {
    final target = normalizePath(path);
    var entries = await _statOnce(target, asCollection: false);
    // Some servers (Apache mod_dav among them) will not answer for a
    // collection addressed without its trailing slash, so a miss is retried
    // the other way round before believing the resource is gone.
    entries ??= await _statOnce(target, asCollection: true);
    if (entries == null || entries.isEmpty) return null;
    // Depth 0 returns one response, but a server that ignores Depth returns
    // the children too; the self entry is the one whose path matches.
    final found = entries;
    return found.firstWhere(
      (e) => e.path == target,
      orElse: () => found.first,
    );
  }

  /// Whether [path] exists. Convenience over [stat] for collision checks.
  Future<bool> exists(String path) async => await stat(path) != null;

  /// Opens [path] for reading. The body is still on the wire when this
  /// returns — see [WebDavDownload].
  ///
  /// [rangeStart]/[rangeEnd] request a byte range. A server that ignores the
  /// header answers 200 with the whole file, which [WebDavDownload.isPartial]
  /// reports as false so the caller can skip the bytes itself rather than
  /// playing from the wrong offset.
  Future<WebDavDownload> download(
    String path, {
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final target = normalizePath(path);
    final request = http.Request('GET', resolveUrl(target))
      ..headers.addAll(await _authHeaders());
    if (rangeStart != null || rangeEnd != null) {
      request.headers['range'] = 'bytes=${rangeStart ?? ''}-${rangeEnd ?? ''}';
    }

    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(requestTimeout);
    } on TimeoutException {
      throw WebDavNetworkException(
        'The server did not start sending $target in time.',
        path: target,
      );
    } on http.ClientException catch (e) {
      throw WebDavNetworkException(e.message, path: target);
    }

    if (response.statusCode != 200 && response.statusCode != 206) {
      // The connection stays checked out until the body is read, even on an
      // error status.
      await response.stream.drain<void>();
      _throwForStatus(response.statusCode, 'GET', target);
    }
    return WebDavDownload(
      stream: response.stream,
      contentLength: response.contentLength,
      contentType: response.headers['content-type'],
      isPartial: response.statusCode == 206,
    );
  }

  /// Writes [body] to [path]. [length] must be the exact byte count: it
  /// becomes Content-Length, and a body that disagrees is truncated or
  /// rejected.
  ///
  /// Pass null only when the size genuinely is not known — the request then
  /// goes out chunked, which some servers refuse.
  ///
  /// With `overwrite: false` the request carries `If-None-Match: *`, so a
  /// server that honours it refuses an existing file with 412 instead of
  /// silently replacing it. Not every server does, which is why
  /// `TransferEngine` also checks the destination first.
  Future<void> upload(
    String path,
    Stream<List<int>> body,
    int? length, {
    bool overwrite = true,
    String? contentType,
  }) async {
    final target = normalizePath(path);
    final request = _StreamedBodyRequest('PUT', resolveUrl(target), body)
      ..contentLength = length
      ..headers.addAll(await _authHeaders());
    if (contentType != null) request.headers['content-type'] = contentType;
    if (!overwrite) request.headers['if-none-match'] = '*';

    // An upload takes as long as the file is, and http offers no hook for
    // "deadline on the response only", so the call runs untimed; a stalled
    // socket still surfaces as a network error.
    final response = await _sendBuffered(request, 'PUT', target, untimed: true);
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      _throwForStatus(response.statusCode, 'PUT', target);
    }
  }

  /// Removes [path]. Deleting a collection removes its contents, which is
  /// what WebDAV specifies.
  Future<void> delete(String path) async {
    final target = normalizePath(path);
    final request = http.Request('DELETE', resolveUrl(target))
      ..headers.addAll(await _authHeaders());
    final response = await _sendBuffered(request, 'DELETE', target);
    if (response.statusCode != 200 &&
        response.statusCode != 202 &&
        response.statusCode != 204) {
      _throwForStatus(response.statusCode, 'DELETE', target);
    }
  }

  /// Creates the collection [path]. The parent must exist — WebDAV has no
  /// `mkdir -p`, and a missing parent comes back as
  /// [WebDavConflictException].
  Future<void> mkcol(String path) async {
    final target = normalizePath(path);
    final request = http.Request(
      'MKCOL',
      resolveUrl(target, asCollection: true),
    )..headers.addAll(await _authHeaders());
    final response = await _sendBuffered(request, 'MKCOL', target);
    if (response.statusCode != 201) {
      if (response.statusCode == 405) {
        throw WebDavConflictException(
          'Something already exists at $target.',
          statusCode: 405,
          path: target,
        );
      }
      _throwForStatus(response.statusCode, 'MKCOL', target);
    }
  }

  /// Moves [src] to [dst] **within this server**, which the server performs
  /// itself — no bytes cross the network.
  ///
  /// WebDAV has no cross-server MOVE: Destination must be on the same host, so
  /// a move between servers is a copy plus a delete. See `TransferEngine`.
  Future<void> moveSameServer(
    String src,
    String dst, {
    bool overwrite = false,
  }) async {
    final from = normalizePath(src);
    final to = normalizePath(dst);
    final request = http.Request('MOVE', resolveUrl(from))
      ..headers.addAll(await _authHeaders())
      ..headers['destination'] = resolveUrl(to).toString()
      ..headers['overwrite'] = overwrite ? 'T' : 'F';
    final response = await _sendBuffered(request, 'MOVE', from);
    if (response.statusCode != 201 && response.statusCode != 204) {
      if (response.statusCode == 412) {
        throw WebDavConflictException(
          'Something already exists at $to.',
          statusCode: 412,
          path: to,
        );
      }
      _throwForStatus(response.statusCode, 'MOVE', from);
    }
  }

  /// URL and headers for handing [path] to a media player.
  ///
  /// Exposed rather than wired into playback: the player owns its own source
  /// handling, and this layer's job ends at "here is the file and how to ask
  /// for it".
  Future<RemoteStreamSpec> streamSpec(String path) async {
    return RemoteStreamSpec(
      url: resolveUrl(normalizePath(path)),
      headers: await _authHeaders(),
    );
  }

  /// Releases the HTTP connection pool. Only closes the client if this
  /// instance created it — an injected one belongs to the caller.
  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<List<WebDavEntry>?> _statOnce(
    String path, {
    required bool asCollection,
  }) async {
    try {
      final body = await _propfind(
        path,
        depth: 0,
        asCollection: asCollection,
      );
      return _parseMultistatus(body);
    } on WebDavNotFoundException {
      return null;
    } on WebDavProtocolException catch (e) {
      // A redirect here means the server wants the other spelling of the path.
      final status = e.statusCode ?? 0;
      if (status >= 300 && status < 400) return null;
      rethrow;
    }
  }

  Future<String> _propfind(
    String path, {
    required int depth,
    required bool asCollection,
  }) async {
    final request = http.Request(
      'PROPFIND',
      resolveUrl(path, asCollection: asCollection),
    )
      ..headers.addAll(await _authHeaders())
      ..headers['depth'] = '$depth'
      ..headers['content-type'] = 'application/xml; charset=utf-8'
      ..bodyBytes = utf8.encode(_propfindBody);
    final response = await _sendBuffered(request, 'PROPFIND', path);
    if (response.statusCode != 207 && response.statusCode != 200) {
      _throwForStatus(response.statusCode, 'PROPFIND', path);
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  List<WebDavEntry> _parseMultistatus(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException catch (e) {
      throw WebDavProtocolException(
        'The server answered PROPFIND with something that is not XML '
        '(${e.message}).',
      );
    }

    final entries = <WebDavEntry>[];
    final responses = document.findAllElements('response', namespace: '*');
    for (final response in responses) {
      final rawHref = response.getElement('href', namespace: '*')?.innerText;
      if (rawHref == null || rawHref.trim().isEmpty) continue;
      final href = rawHref.trim();
      final path = pathFromHref(href);

      final props = _okProps(response);
      final resourceType = _element(props, 'resourcetype');
      final isDir =
          resourceType?.getElement('collection', namespace: '*') != null ||
              // Some servers mark a collection only by the trailing slash.
              (resourceType == null && href.endsWith('/'));

      entries.add(
        WebDavEntry(
          name: _displayName(props, path),
          path: path,
          isDir: isDir,
          size: int.tryParse(_prop(props, 'getcontentlength') ?? ''),
          contentType: _prop(props, 'getcontenttype'),
          lastModified: _parseHttpDate(_prop(props, 'getlastmodified')),
        ),
      );
    }
    return entries;
  }

  /// The `prop` elements whose `propstat` reported 200.
  ///
  /// Properties a server could not supply come back in a second propstat with
  /// 404; reading those yields empty values where the caller expects null.
  List<XmlElement> _okProps(XmlElement response) {
    final propstats =
        response.findElements('propstat', namespace: '*').toList();
    if (propstats.isEmpty) {
      return response.findElements('prop', namespace: '*').toList();
    }
    final ok = <XmlElement>[];
    for (final propstat in propstats) {
      final status =
          propstat.getElement('status', namespace: '*')?.innerText ?? '';
      if (status.isEmpty || status.contains(' 200')) {
        final prop = propstat.getElement('prop', namespace: '*');
        if (prop != null) ok.add(prop);
      }
    }
    return ok;
  }

  XmlElement? _element(List<XmlElement> props, String name) {
    for (final prop in props) {
      final found = prop.getElement(name, namespace: '*');
      if (found != null) return found;
    }
    return null;
  }

  String? _prop(List<XmlElement> props, String name) {
    final value = _element(props, name)?.innerText;
    return (value == null || value.isEmpty) ? null : value;
  }

  /// The path segment wins over `displayname`: the segment is what every
  /// other method needs, and some servers report a displayname that is not
  /// the addressable name.
  String _displayName(List<XmlElement> props, String path) {
    final leaf = basename(path);
    if (leaf.isNotEmpty) return leaf;
    return _prop(props, 'displayname') ?? '/';
  }

  Future<Map<String, String>> _authHeaders() async {
    final secret = await _secret();
    if (secret == null || secret.isEmpty) {
      throw const WebDavAuthException(
        'No password is stored for this server. Edit the server to enter it '
        'again.',
      );
    }
    final token = base64Encode(utf8.encode('$username:$secret'));
    return {'authorization': 'Basic $token'};
  }

  Future<http.Response> _sendBuffered(
    http.BaseRequest request,
    String method,
    String path, {
    bool untimed = false,
  }) async {
    try {
      final send = _http.send(request);
      final streamed = await (untimed ? send : send.timeout(requestTimeout));
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw WebDavNetworkException(
        'The server did not answer $method in time.',
        path: path,
      );
    } on http.ClientException catch (e) {
      throw WebDavNetworkException(e.message, path: path);
    }
  }

  Never _throwForStatus(int status, String method, String path) {
    switch (status) {
      case 401:
      case 403:
        throw WebDavAuthException(
          'The server rejected the username or password.',
          statusCode: status,
          path: path,
        );
      case 404:
      case 410:
        throw WebDavNotFoundException(
          'Not found on the server: $path',
          statusCode: status,
          path: path,
        );
      case 405:
      case 409:
      case 412:
      case 423:
        throw WebDavConflictException(
          'The server refused $method on $path because of what is already '
          'there.',
          statusCode: status,
          path: path,
        );
      default:
        throw WebDavProtocolException(
          'The server answered $method with HTTP $status.',
          statusCode: status,
          path: path,
        );
    }
  }
}

/// RFC 1123 (`Tue, 15 Nov 1994 12:45:26 GMT`) is what `getlastmodified`
/// specifies, but ISO 8601 turns up too, so that is tried first.
///
/// An unparseable date is null, never `DateTime.now()`: a wrong timestamp is
/// worse than a missing one, because sorting by it looks like it works.
DateTime? _parseHttpDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final iso = DateTime.tryParse(raw);
  if (iso != null) return iso;

  final match = RegExp(
    r'^\w{3},\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+'
    r'(\d{2}):(\d{2}):(\d{2})\s+GMT$',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  const months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  final month = months[match.group(2)!.toLowerCase()];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

/// A request whose body is a stream the caller already holds.
///
/// `http.StreamedRequest` expects the caller to push into a sink, which cannot
/// be handed a download stream directly. Yielding the stream at finalize time
/// is what keeps a cross-server transfer at constant memory.
class _StreamedBodyRequest extends http.BaseRequest {
  _StreamedBodyRequest(super.method, super.url, this._body);

  final Stream<List<int>> _body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}
