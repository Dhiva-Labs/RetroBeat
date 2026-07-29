import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_config_model.dart';
import 'credential_vault.dart';
import 'webdav_client.dart';

/// Where one server currently stands.
enum ServerConnectionStatus {
  /// Known but not in use. No socket, no credentials read.
  disconnected,

  /// A connection attempt is in flight.
  connecting,

  /// Reachable, authenticated, and the root folder is there.
  connected,

  /// The last attempt failed; [ServerSession.message] says how.
  error,
}

/// One server's live state.
///
/// Sessions are independent by design: several can be [connected] at once, and
/// connecting, failing or disconnecting one leaves the rest alone. That is the
/// point of keying them by id rather than holding a single "current server".
class ServerSession {
  const ServerSession._({
    required this.config,
    required this.status,
    this.message,
    this.client,
  });

  /// Known, idle, no client.
  factory ServerSession.disconnected(ServerConfigModel config) =>
      ServerSession._(
        config: config,
        status: ServerConnectionStatus.disconnected,
      );

  /// Attempting to reach the server. The client exists already so a caller can
  /// cancel by disconnecting.
  factory ServerSession.connecting(
    ServerConfigModel config,
    WebDavClient client,
  ) =>
      ServerSession._(
        config: config,
        status: ServerConnectionStatus.connecting,
        client: client,
      );

  /// Reachable and authenticated; [client] is ready for requests.
  factory ServerSession.connected(
    ServerConfigModel config,
    WebDavClient client,
  ) =>
      ServerSession._(
        config: config,
        status: ServerConnectionStatus.connected,
        client: client,
      );

  /// The attempt failed. [message] is written for the user, not for a log.
  factory ServerSession.failed(ServerConfigModel config, String message) =>
      ServerSession._(
        config: config,
        status: ServerConnectionStatus.error,
        message: message,
      );

  final ServerConfigModel config;
  final ServerConnectionStatus status;

  /// Why the last attempt failed, when [status] is
  /// [ServerConnectionStatus.error]. Safe to show verbatim.
  final String? message;

  /// Null unless connecting or connected. Never keep a reference past a
  /// disconnect — the session closes it.
  final WebDavClient? client;

  bool get isConnected =>
      status == ServerConnectionStatus.connected && client != null;

  bool get isBusy => status == ServerConnectionStatus.connecting;

  @override
  String toString() => 'ServerSession(${config.id}, ${status.name})';
}

/// Builds the client for a server. Injectable so tests can point every session
/// at an in-process server without a keychain in the picture.
typedef WebDavClientFactory = WebDavClient Function(
  ServerConfigModel config,
  CredentialVault vault,
);

WebDavClient _defaultClientFactory(
  ServerConfigModel config,
  CredentialVault vault,
) =>
    WebDavClient.forConfig(config, vault);

/// Every known server's session, keyed by server id.
///
/// The map always holds one entry per saved server, including disconnected
/// ones, so the UI can list servers and their state from a single watch.
class ServerSessionsNotifier extends StateNotifier<Map<String, ServerSession>> {
  ServerSessionsNotifier({
    required CredentialVault vault,
    WebDavClientFactory clientFactory = _defaultClientFactory,
  })  : _vault = vault,
        _clientFactory = clientFactory,
        super(const {});

  final CredentialVault _vault;
  final WebDavClientFactory _clientFactory;
  bool _bootstrapped = false;

  /// Brings the session map in line with the saved servers: new servers appear
  /// disconnected, removed ones are dropped and their clients closed, and
  /// edited ones keep their connection unless the address or account changed.
  void sync(List<ServerConfigModel> configs) {
    final next = <String, ServerSession>{};
    for (final config in configs) {
      final existing = state[config.id];
      if (existing == null) {
        next[config.id] = ServerSession.disconnected(config);
        continue;
      }
      // A client is bound to a base URL and username, so those changing means
      // the live connection is to the wrong place.
      final rebound = existing.config.baseUrl != config.baseUrl ||
          existing.config.username != config.username;
      if (rebound) {
        existing.client?.close();
        next[config.id] = ServerSession.disconnected(config);
      } else if (existing.isConnected) {
        next[config.id] = ServerSession.connected(config, existing.client!);
      } else if (existing.isBusy) {
        next[config.id] = ServerSession.connecting(config, existing.client!);
      } else if (existing.status == ServerConnectionStatus.error) {
        next[config.id] = ServerSession.failed(config, existing.message ?? '');
      } else {
        next[config.id] = ServerSession.disconnected(config);
      }
    }

    for (final entry in state.entries) {
      if (!next.containsKey(entry.key)) entry.value.client?.close();
    }
    state = next;
  }

  ServerSession? sessionFor(String serverId) => state[serverId];

  /// The client for [serverId], or null if that server is not connected.
  /// Callers must not hold on to it across a disconnect.
  WebDavClient? clientFor(String serverId) {
    final session = state[serverId];
    return session != null && session.isConnected ? session.client : null;
  }

  /// Every currently connected session, in the order the servers are saved.
  List<ServerSession> get connected =>
      state.values.where((s) => s.isConnected).toList();

  /// Connects one server. Other sessions are untouched.
  ///
  /// Never throws: a failure becomes [ServerConnectionStatus.error] with a
  /// message, because connecting is something the UI shows rather than
  /// something it catches.
  Future<void> connect(String serverId) async {
    final session = state[serverId];
    if (session == null || session.isBusy) return;

    final config = session.config;
    final client = session.client ?? _clientFactory(config, _vault);
    _put(serverId, ServerSession.connecting(config, client));

    try {
      await client.testConnection(path: config.rootPath);
    } catch (error) {
      client.close();
      // The session may have been removed or disconnected while we waited.
      if (state[serverId]?.client != client) return;
      _put(serverId, ServerSession.failed(config, describeServerError(error)));
      return;
    }

    if (state[serverId]?.client != client) {
      client.close();
      return;
    }
    _put(serverId, ServerSession.connected(config, client));
  }

  /// Drops one server's connection and closes its client. Transfers holding
  /// that client will fail on their next request, which is the honest
  /// outcome — a disconnect the user asked for should not keep working.
  void disconnect(String serverId) {
    final session = state[serverId];
    if (session == null) return;
    session.client?.close();
    _put(serverId, ServerSession.disconnected(session.config));
  }

  /// Connects every server marked [ServerConfigModel.autoConnect], once per
  /// app run.
  ///
  /// Calling it again is a no-op, so it is safe to hang off a widget's
  /// `initState` without guarding against rebuilds. Servers connect in
  /// parallel; one failing does not stop the others.
  Future<void> connectAutoConnect() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final pending = state.values
        .where((s) => s.config.autoConnect && !s.isConnected && !s.isBusy)
        .map((s) => connect(s.config.id));
    await Future.wait(pending);
  }

  /// URL and headers for streaming [path] from [serverId] into a player.
  ///
  /// Works whether or not the server is connected: playback needs credentials,
  /// not a session. When there is no live client a throwaway one is built and
  /// closed again, since building the spec sends no request.
  ///
  /// Throws [ArgumentError] for an unknown server, [WebDavAuthException] if no
  /// password is stored, and [VaultUnavailableException] if the keychain is
  /// missing.
  Future<RemoteStreamSpec> remoteStreamSpec(
    String serverId,
    String path,
  ) async {
    final session = state[serverId];
    if (session == null) {
      throw ArgumentError.value(serverId, 'serverId', 'No such server');
    }
    final live = session.client;
    if (live != null) return live.streamSpec(path);

    final client = _clientFactory(session.config, _vault);
    try {
      return await client.streamSpec(path);
    } finally {
      client.close();
    }
  }

  void _put(String serverId, ServerSession session) {
    if (!mounted) return;
    state = {...state, serverId: session};
  }

  @override
  void dispose() {
    for (final session in state.values) {
      session.client?.close();
    }
    super.dispose();
  }
}

/// Turns anything the server layer throws into a sentence for the user.
///
/// Exists so the same wording appears wherever a failure surfaces — session
/// errors, transfer errors, connection tests. Nothing it returns contains a
/// credential, because none of the exception types carry one.
String describeServerError(Object error) {
  if (error is WebDavException) return error.message;
  if (error is VaultException) return error.message;
  if (error is ArgumentError) return error.message?.toString() ?? '$error';
  return error.toString();
}
