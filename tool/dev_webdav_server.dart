/// A small WebDAV server for developing and testing the server layer.
///
/// It serves one directory over the subset of WebDAV the app speaks — OPTIONS,
/// PROPFIND (depth 0 and 1), GET with byte ranges, HEAD, PUT, DELETE, MKCOL and
/// MOVE — with Basic auth required on every request.
///
/// ```
/// dart run tool/dev_webdav_server.dart --root ~/Music --port 8080 \
///     --user demo --pass demo
/// ```
///
/// Range support is not optional decoration: mpv (and therefore desktop
/// playback) seeks by asking for byte ranges, and a server that answers 200
/// with the whole file every time makes seeking look broken.
///
/// This is a development tool. It has no TLS, no locking, and no quota
/// handling, and it is not meant to face a network you do not control.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options == null) {
    stderr.writeln(_usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  final root = Directory(options.root);
  if (!root.existsSync()) {
    stderr.writeln('No such directory: ${options.root}');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final server = await startDevWebDavServer(
    root: root.absolute.path,
    username: options.username,
    password: options.password,
    port: options.port,
    address: options.host,
  );

  stdout.writeln('WebDAV on http://${options.host}:${server.port}/');
  stdout.writeln('  root: ${root.absolute.path}');
  stdout.writeln('  user: ${options.username}');
  stdout.writeln('Ctrl-C to stop.');
}

/// Binds a dev server on [port] (0 for an ephemeral one) and returns it, so
/// tests can read `server.port` and shut it down afterwards.
Future<HttpServer> startDevWebDavServer({
  required String root,
  required String username,
  required String password,
  int port = 0,
  String address = '127.0.0.1',
}) {
  return shelf_io.serve(
    createHandler(root: root, username: username, password: password),
    address,
    port,
  );
}

/// The WebDAV handler for [root], requiring [username]/[password] on every
/// request.
///
/// Mountable in-process: tests serve this on an ephemeral port and point a
/// real [WebDavClient] at it, so the client is exercised over an actual socket
/// rather than against a mock of the protocol.
shelf.Handler createHandler({
  required String root,
  required String username,
  required String password,
}) {
  final rootPath = p.normalize(Directory(root).absolute.path);
  final expected = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  return (shelf.Request request) async {
    if (request.headers['authorization'] != expected) {
      return shelf.Response(
        401,
        body: 'Authentication required.',
        headers: {'www-authenticate': 'Basic realm="RetroBeat"'},
      );
    }

    final segments = _segmentsOf(request.url.pathSegments);
    final local = _resolveLocal(rootPath, segments);
    if (local == null) {
      return shelf.Response.forbidden('Path escapes the served root.');
    }

    switch (request.method) {
      case 'OPTIONS':
        return shelf.Response.ok(
          null,
          headers: {
            'dav': '1, 2',
            'ms-author-via': 'DAV',
            'allow': 'OPTIONS, HEAD, GET, PUT, DELETE, PROPFIND, MKCOL, MOVE',
          },
        );
      case 'PROPFIND':
        return _propfind(request, rootPath, segments, local);
      case 'GET':
        return _get(request, local, withBody: true);
      case 'HEAD':
        return _get(request, local, withBody: false);
      case 'PUT':
        return _put(request, local);
      case 'DELETE':
        return _delete(local);
      case 'MKCOL':
        return _mkcol(local);
      case 'MOVE':
        return _move(request, rootPath, local);
      default:
        return shelf.Response(405, body: 'Unsupported method.');
    }
  };
}

/// Drops the empty segment a trailing slash produces, so `/Music/` and
/// `/Music` address the same thing.
List<String> _segmentsOf(List<String> raw) =>
    raw.where((s) => s.isNotEmpty).toList();

/// The on-disk path for [segments], or null if it would leave [rootPath].
///
/// A dev tool still refuses `..`: it is pointed at a music folder, not at the
/// whole filesystem.
String? _resolveLocal(String rootPath, List<String> segments) {
  if (segments.any((s) => s == '..' || s == '.')) return null;
  final joined = p.normalize(p.joinAll([rootPath, ...segments]));
  if (joined != rootPath && !p.isWithin(rootPath, joined)) return null;
  return joined;
}

shelf.Response _propfind(
  shelf.Request request,
  String rootPath,
  List<String> segments,
  String local,
) {
  final type = FileSystemEntity.typeSync(local);
  if (type == FileSystemEntityType.notFound) {
    return shelf.Response.notFound('Not found.');
  }

  final depth = request.headers['depth'] ?? 'infinity';
  final base = request.handlerPath.endsWith('/')
      ? request.handlerPath
      : '${request.handlerPath}/';

  final buffer = StringBuffer()
    ..write('<?xml version="1.0" encoding="utf-8"?>\n')
    ..write('<D:multistatus xmlns:D="DAV:">\n');

  // The prefixed namespace is deliberate: clients that assume an unprefixed
  // DAV: document break against real servers, so the dev server uses the
  // spelling most of them use.
  _writeResponseXml(buffer, base, segments, local);

  if (depth != '0' && type == FileSystemEntityType.directory) {
    final children = Directory(local).listSync()..sort(_byPath);
    for (final child in children) {
      _writeResponseXml(
        buffer,
        base,
        [...segments, p.basename(child.path)],
        child.path,
      );
    }
  }
  buffer.write('</D:multistatus>\n');

  return shelf.Response(
    207,
    body: utf8.encode(buffer.toString()),
    headers: {'content-type': 'application/xml; charset=utf-8'},
  );
}

int _byPath(FileSystemEntity a, FileSystemEntity b) =>
    a.path.toLowerCase().compareTo(b.path.toLowerCase());

void _writeResponseXml(
  StringBuffer buffer,
  String base,
  List<String> segments,
  String local,
) {
  final stat = FileStat.statSync(local);
  final isDir = stat.type == FileSystemEntityType.directory;
  final href =
      base + segments.map(Uri.encodeComponent).join('/') + (isDir ? '/' : '');
  final name = segments.isEmpty ? '/' : segments.last;

  buffer
    ..write('  <D:response>\n')
    ..write('    <D:href>${_escape(href)}</D:href>\n')
    ..write('    <D:propstat>\n')
    ..write('      <D:prop>\n')
    ..write('        <D:displayname>${_escape(name)}</D:displayname>\n')
    ..write('        <D:getlastmodified>')
    ..write(HttpDate.format(stat.modified.toUtc()))
    ..write('</D:getlastmodified>\n');

  if (isDir) {
    buffer.write('        <D:resourcetype><D:collection/></D:resourcetype>\n');
  } else {
    buffer
      ..write('        <D:resourcetype/>\n')
      ..write('        <D:getcontentlength>${stat.size}'
          '</D:getcontentlength>\n')
      ..write('        <D:getcontenttype>${_contentTypeOf(local)}'
          '</D:getcontenttype>\n');
  }

  buffer
    ..write('      </D:prop>\n')
    ..write('      <D:status>HTTP/1.1 200 OK</D:status>\n')
    ..write('    </D:propstat>\n')
    ..write('  </D:response>\n');
}

Future<shelf.Response> _get(
  shelf.Request request,
  String local, {
  required bool withBody,
}) async {
  final file = File(local);
  if (!file.existsSync()) {
    if (Directory(local).existsSync()) {
      return shelf.Response(405, body: 'That is a collection.');
    }
    return shelf.Response.notFound('Not found.');
  }

  final length = await file.length();
  final headers = <String, String>{
    'content-type': _contentTypeOf(local),
    'accept-ranges': 'bytes',
    'last-modified': HttpDate.format(file.lastModifiedSync().toUtc()),
  };

  final range = _parseRange(request.headers['range'], length);
  if (range == _rangeUnsatisfiable) {
    return shelf.Response(
      416,
      headers: {...headers, 'content-range': 'bytes */$length'},
    );
  }

  if (range != null) {
    final count = range.end - range.start + 1;
    return shelf.Response(
      206,
      body: withBody ? file.openRead(range.start, range.end + 1) : null,
      headers: {
        ...headers,
        'content-range': 'bytes ${range.start}-${range.end}/$length',
        'content-length': '$count',
      },
    );
  }

  return shelf.Response.ok(
    withBody ? file.openRead() : null,
    headers: {...headers, 'content-length': '$length'},
  );
}

/// A byte range that a request asked for and the file can satisfy.
class _Range {
  const _Range(this.start, this.end);

  /// Inclusive, as in the HTTP header.
  final int start;
  final int end;
}

/// Sentinel for "a range was asked for and it cannot be met", which is a 416
/// rather than the "no range asked for" that null means.
const _rangeUnsatisfiable = _Range(-1, -1);

/// Handles `bytes=N-M`, `bytes=N-` and the suffix form `bytes=-N`.
///
/// Multi-range requests are answered as if no range were given: they are legal
/// but need multipart/byteranges, and nothing in this app asks for them.
_Range? _parseRange(String? header, int length) {
  if (header == null) return null;
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (match == null) return null;

  final fromText = match.group(1)!;
  final toText = match.group(2)!;
  if (fromText.isEmpty && toText.isEmpty) return null;

  int start;
  int end;
  if (fromText.isEmpty) {
    // Suffix range: the last N bytes.
    final suffix = int.parse(toText);
    if (suffix == 0) return _rangeUnsatisfiable;
    start = length - suffix < 0 ? 0 : length - suffix;
    end = length - 1;
  } else {
    start = int.parse(fromText);
    end = toText.isEmpty ? length - 1 : int.parse(toText);
    if (end > length - 1) end = length - 1;
  }
  if (length == 0 || start > end || start >= length) {
    return _rangeUnsatisfiable;
  }
  return _Range(start, end);
}

Future<shelf.Response> _put(shelf.Request request, String local) async {
  final parent = Directory(p.dirname(local));
  if (!parent.existsSync()) {
    return shelf.Response(409, body: 'Parent collection does not exist.');
  }
  if (Directory(local).existsSync()) {
    return shelf.Response(405, body: 'That is a collection.');
  }

  final file = File(local);
  final existed = file.existsSync();
  if (existed && request.headers['if-none-match'] == '*') {
    return shelf.Response(412, body: 'Already exists.');
  }

  // Written straight from the request stream: a dev server that buffered the
  // upload would hide the very thing the transfer tests are checking.
  final sink = file.openWrite();
  try {
    await sink.addStream(request.read());
    await sink.close();
  } catch (_) {
    // The client hung up mid-body, which is what a cancelled transfer looks
    // like from here. Close quietly; the partial file is left for the client
    // to clean up, as most servers do.
    try {
      await sink.close();
    } catch (_) {
      // Already closed by the failed addStream.
    }
    return shelf.Response(400, body: 'The upload did not complete.');
  }
  return shelf.Response(existed ? 204 : 201);
}

Future<shelf.Response> _delete(String local) async {
  final type = FileSystemEntity.typeSync(local);
  if (type == FileSystemEntityType.notFound) {
    return shelf.Response.notFound('Not found.');
  }
  if (type == FileSystemEntityType.directory) {
    await Directory(local).delete(recursive: true);
  } else {
    await File(local).delete();
  }
  return shelf.Response(204);
}

Future<shelf.Response> _mkcol(String local) async {
  if (FileSystemEntity.typeSync(local) != FileSystemEntityType.notFound) {
    return shelf.Response(405, body: 'Already exists.');
  }
  if (!Directory(p.dirname(local)).existsSync()) {
    return shelf.Response(409, body: 'Parent collection does not exist.');
  }
  await Directory(local).create();
  return shelf.Response(201);
}

Future<shelf.Response> _move(
  shelf.Request request,
  String rootPath,
  String local,
) async {
  final destination = request.headers['destination'];
  if (destination == null) {
    return shelf.Response(400, body: 'Destination header required.');
  }
  if (FileSystemEntity.typeSync(local) == FileSystemEntityType.notFound) {
    return shelf.Response.notFound('Not found.');
  }

  // WebDAV has no cross-server MOVE, and answering 201 for one would tell the
  // client the bytes are somewhere they are not.
  final parsed = Uri.tryParse(destination);
  if (parsed == null) {
    return shelf.Response(400, body: 'Destination is not a URL.');
  }
  final here = request.requestedUri;
  if (parsed.hasAuthority &&
      (parsed.host != here.host || parsed.port != here.port)) {
    return shelf.Response(502, body: 'Destination is on another server.');
  }

  final base = request.handlerPath.endsWith('/')
      ? request.handlerPath
      : '${request.handlerPath}/';
  final target = _localForDestination(rootPath, base, destination);
  if (target == null) {
    return shelf.Response(400, body: 'Destination is not on this server.');
  }
  if (!Directory(p.dirname(target)).existsSync()) {
    return shelf.Response(409, body: 'Destination collection does not exist.');
  }

  final existed =
      FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound;
  if (existed && request.headers['overwrite'] != 'T') {
    return shelf.Response(412, body: 'Destination already exists.');
  }
  if (existed) {
    final type = FileSystemEntity.typeSync(target);
    if (type == FileSystemEntityType.directory) {
      await Directory(target).delete(recursive: true);
    } else {
      await File(target).delete();
    }
  }

  if (FileSystemEntity.isDirectorySync(local)) {
    await Directory(local).rename(target);
  } else {
    await File(local).rename(target);
  }
  return shelf.Response(existed ? 204 : 201);
}

/// The on-disk path a Destination header points at, or null if it addresses
/// something outside this server's mount.
String? _localForDestination(String rootPath, String base, String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  final baseSegments = Uri(path: base).pathSegments.where((s) => s.isNotEmpty);
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  for (final segment in baseSegments) {
    if (segments.isEmpty || segments.first != segment) return null;
    segments.removeAt(0);
  }
  if (segments.isEmpty) return null;
  return _resolveLocal(rootPath, segments);
}

String _contentTypeOf(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.mp3':
      return 'audio/mpeg';
    case '.flac':
      return 'audio/flac';
    case '.m4a':
    case '.aac':
      return 'audio/mp4';
    case '.ogg':
    case '.opus':
      return 'audio/ogg';
    case '.wav':
      return 'audio/wav';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.txt':
      return 'text/plain';
    case '.xml':
      return 'application/xml';
    default:
      return 'application/octet-stream';
  }
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

const _usage = '''
Serve a directory over WebDAV, for development.

Usage: dart run tool/dev_webdav_server.dart --root DIR [options]

  --root DIR   Directory to serve (required)
  --port N     Port to listen on (default 8080; 0 picks a free one)
  --host H     Address to bind (default 127.0.0.1)
  --user U     Basic auth username (default demo)
  --pass P     Basic auth password (default demo)
''';

class _Options {
  _Options({
    required this.root,
    required this.port,
    required this.host,
    required this.username,
    required this.password,
  });

  final String root;
  final int port;
  final String host;
  final String username;
  final String password;

  /// Returns null when the arguments do not make a runnable server, which the
  /// caller turns into usage output.
  static _Options? parse(List<String> args) {
    final values = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) return null;
      final equals = arg.indexOf('=');
      if (equals >= 0) {
        values[arg.substring(2, equals)] = arg.substring(equals + 1);
      } else {
        if (i + 1 >= args.length) return null;
        values[arg.substring(2)] = args[++i];
      }
    }

    final root = values['root'];
    if (root == null || root.isEmpty) return null;
    final port = int.tryParse(values['port'] ?? '8080');
    if (port == null) return null;

    return _Options(
      root: root,
      port: port,
      host: values['host'] ?? '127.0.0.1',
      username: values['user'] ?? 'demo',
      password: values['pass'] ?? 'demo',
    );
  }
}
