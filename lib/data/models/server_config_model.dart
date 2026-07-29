import 'package:hive/hive.dart';

part 'server_config_model.g.dart';

/// A saved WebDAV server.
///
/// There is deliberately **no password field**. Hive boxes are plain files on
/// disk with no encryption of their own, so the password lives in the OS
/// keychain under `CredentialVault` and is looked up by [id] at request time.
/// Adding a password here would silently undo that, so don't.
@HiveType(typeId: 4)
class ServerConfigModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  /// Scheme, host, port and any path prefix the server is mounted under, e.g.
  /// `https://nas.local:5006/remote.php/dav/files/me`. Stored without a
  /// trailing slash.
  @HiveField(2)
  String baseUrl;

  @HiveField(3)
  String username;

  /// Folder within the server to open at, as an absolute path relative to
  /// [baseUrl]. `/` means the whole share.
  @HiveField(4)
  String rootPath;

  /// Whether the startup bootstrap should connect this server without being
  /// asked. See `serverBootstrapProvider`.
  @HiveField(5)
  bool autoConnect;

  @HiveField(6)
  final DateTime createdAt;

  ServerConfigModel({
    required this.id,
    required this.name,
    required String baseUrl,
    required this.username,
    String rootPath = '/',
    this.autoConnect = true,
    DateTime? createdAt,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        rootPath = normalizeRootPath(rootPath),
        createdAt = createdAt ?? DateTime.now();

  /// Whether traffic to this server is encrypted.
  ///
  /// Basic auth sends the password in a reversible header, so a plain-http
  /// server hands it to anyone on the path. The UI is expected to badge these.
  bool get isSecure => Uri.tryParse(baseUrl)?.scheme.toLowerCase() == 'https';

  /// The parsed [baseUrl]. Throws [FormatException] if the stored URL is not a
  /// URL at all, which only happens if it was written by something other than
  /// this class.
  Uri get baseUri => Uri.parse(baseUrl);

  /// Trims whitespace and drops the trailing slash, so `http://h/dav` and
  /// `http://h/dav/` are one server rather than two.
  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Forces a leading slash and drops the trailing one, so every stored root
  /// compares equal to the paths the WebDAV client hands back.
  static String normalizeRootPath(String raw) {
    var value = raw.trim();
    if (!value.startsWith('/')) value = '/$value';
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  ServerConfigModel copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? username,
    String? rootPath,
    bool? autoConnect,
    DateTime? createdAt,
  }) {
    return ServerConfigModel(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      rootPath: rootPath ?? this.rootPath,
      autoConnect: autoConnect ?? this.autoConnect,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerConfigModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ServerConfigModel($id, $name, $baseUrl, $username)';
}
