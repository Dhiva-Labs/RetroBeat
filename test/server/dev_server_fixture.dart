import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:retro_beat/data/server/credential_vault.dart';

import '../../tool/dev_webdav_server.dart';

/// A dev WebDAV server on an ephemeral port, serving a throwaway directory.
///
/// Tests run against a real socket rather than a mocked client: the parts most
/// likely to be wrong — percent-encoding, PROPFIND namespaces, Range replies,
/// streamed PUT — only exist at that boundary.
class DevServer {
  DevServer._(this._server, this.root, this.username, this.password);

  final HttpServer _server;
  final Directory root;
  final String username;
  final String password;

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<DevServer> start({
    String username = 'demo',
    String password = 'hunter2-correct-horse',
    String prefix = 'retrobeat_dav',
  }) async {
    final root = await Directory.systemTemp.createTemp(prefix);
    final server = await startDevWebDavServer(
      root: root.path,
      username: username,
      password: password,
    );
    return DevServer._(server, root, username, password);
  }

  Future<void> stop() async {
    await _server.close(force: true);
    if (root.existsSync()) root.deleteSync(recursive: true);
  }

  File fileAt(String relative) => File('${root.path}/$relative');

  Directory dirAt(String relative) => Directory('${root.path}/$relative');

  void writeText(String relative, String contents) {
    final file = fileAt(relative);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  void writeBytes(String relative, List<int> bytes) {
    final file = fileAt(relative);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  void makeDir(String relative) => dirAt(relative).createSync(recursive: true);

  bool has(String relative) =>
      FileSystemEntity.typeSync('${root.path}/$relative') !=
      FileSystemEntityType.notFound;

  String readText(String relative) => fileAt(relative).readAsStringSync();
}

/// A vault backed by a map, for tests that must not touch a real keychain.
///
/// [available] models a machine with no keyring: flip it off and every call
/// throws the same typed exception the plugin failure is translated into.
class FakeSecretStore implements SecretStore {
  FakeSecretStore({this.available = true});

  final Map<String, String> entries = {};
  bool available;

  @override
  Future<void> write(String key, String value) async {
    _check();
    entries[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return entries[key];
  }

  @override
  Future<void> delete(String key) async {
    _check();
    entries.remove(key);
  }

  void _check() {
    if (!available) throw const VaultUnavailableException();
  }
}

/// Wraps a real client and records the requests that go out, so a test can
/// prove *how* something was done — a same-server move must use MOVE rather
/// than a download and re-upload, and a move must not delete the source until
/// the destination has been read back.
///
/// Pass a shared [log] to two of these to get one ordered trace across both
/// servers.
class RecordingClient extends http.BaseClient {
  RecordingClient({http.Client? inner, this.label = '', List<String>? log})
      : _inner = inner ?? http.Client(),
        log = log ?? [];

  final http.Client _inner;

  /// Prefix for this client's entries in [log], e.g. the server's name.
  final String label;

  /// `<label> <METHOD> <path>` per request, in the order they were sent.
  final List<String> log;

  List<String> get methods => log
      .where((e) => e.startsWith(label))
      .map((e) => e.split(' ')[1])
      .toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    log.add('$label ${request.method} ${Uri.decodeFull(request.url.path)}');
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// The Basic header a request to [server] should carry, for tests that check
/// what `streamSpec` hands to a player.
String basicHeaderFor(DevServer server) =>
    'Basic ${base64Encode(utf8.encode('${server.username}:${server.password}'))}';
