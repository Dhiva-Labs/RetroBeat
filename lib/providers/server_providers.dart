import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../data/models/server_config_model.dart';
import '../data/server/credential_vault.dart';
import '../data/server/server_session.dart';
import '../data/server/transfer_engine.dart';
import '../data/server/webdav_client.dart';
import '../data/services/storage_service.dart';

// Re-exported so a screen needs one import for the whole server layer: the
// config type, session state, transfers, entries and every exception it has to
// explain.
export '../data/models/server_config_model.dart' show ServerConfigModel;
export '../data/server/credential_vault.dart'
    show VaultException, VaultUnavailableException;
export '../data/server/server_session.dart'
    show
        ServerConnectionStatus,
        ServerSession,
        ServerSessionsNotifier,
        WebDavClientFactory,
        describeServerError;
export '../data/server/transfer_engine.dart';
export '../data/server/webdav_client.dart';

/// The OS keychain. Overridden in tests with a fake backend so no test ever
/// needs a running keyring.
final credentialVaultProvider = Provider<CredentialVault>((ref) {
  return CredentialVault.keychain();
});

/// The Hive box holding server *configuration* — never passwords.
///
/// A provider rather than a direct [StorageService] reference so tests can
/// point it at a temporary box.
final serverBoxProvider = Provider<Box<ServerConfigModel>>((ref) {
  return StorageService.serversBox;
});

/// Every saved server, oldest first.
final serverListProvider =
    StateNotifierProvider<ServerListNotifier, List<ServerConfigModel>>((ref) {
  return ServerListNotifier(
    box: ref.watch(serverBoxProvider),
    vault: ref.watch(credentialVaultProvider),
  );
});

/// Saved servers, and the one place their passwords are written.
///
/// The split matters: the config goes to Hive, which is an unencrypted file,
/// and the password goes to the keychain. Nothing here ever puts the two in
/// the same place.
class ServerListNotifier extends StateNotifier<List<ServerConfigModel>> {
  ServerListNotifier({
    required Box<ServerConfigModel> box,
    required CredentialVault vault,
  })  : _box = box,
        _vault = vault,
        super(const []) {
    reload();
  }

  final Box<ServerConfigModel> _box;
  final CredentialVault _vault;
  static const _uuid = Uuid();

  void reload() {
    state = _box.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  ServerConfigModel? byId(String id) {
    for (final config in state) {
      if (config.id == id) return config;
    }
    return null;
  }

  /// Saves a new server.
  ///
  /// The password is written to the keychain **first**: if that fails there is
  /// no server in the list to explain, whereas the other order would leave a
  /// saved server that can never connect and no obvious way to tell why.
  ///
  /// Throws [VaultUnavailableException] if there is no keychain, and
  /// [ArgumentError] if [baseUrl] is not an absolute http(s) URL.
  Future<ServerConfigModel> add({
    required String name,
    required String baseUrl,
    required String username,
    required String password,
    String rootPath = '/',
    bool autoConnect = true,
  }) async {
    final problem = validateBaseUrl(baseUrl);
    if (problem != null) throw ArgumentError.value(baseUrl, 'baseUrl', problem);

    final config = ServerConfigModel(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? Uri.parse(baseUrl).host : name.trim(),
      baseUrl: baseUrl,
      username: username,
      rootPath: rootPath,
      autoConnect: autoConnect,
    );

    await _vault.store(config.id, password);
    await _box.put(config.id, config);
    reload();
    return config;
  }

  /// Replaces a saved server's settings, and its password when [password] is
  /// given. Passing null leaves the stored password alone; passing an empty
  /// string is rejected, since a blank password cannot authenticate and would
  /// look like a working save.
  Future<void> update(
    ServerConfigModel config, {
    String? password,
  }) async {
    final problem = validateBaseUrl(config.baseUrl);
    if (problem != null) {
      throw ArgumentError.value(config.baseUrl, 'baseUrl', problem);
    }
    if (password != null) {
      if (password.isEmpty) {
        throw ArgumentError.value(password, 'password', 'Must not be empty');
      }
      await _vault.store(config.id, password);
    }
    await _box.put(config.id, config);
    reload();
  }

  /// Forgets a server and its password.
  ///
  /// The list entry goes first so the server disappears from the UI even on a
  /// machine with no keychain; the vault delete then throws
  /// [VaultUnavailableException] if the password could not be purged, which
  /// the UI should report rather than swallow — a leftover keychain entry is
  /// worth telling the user about.
  Future<void> remove(String id) async {
    await _box.delete(id);
    reload();
    await _vault.delete(id);
  }

  /// Null if [raw] is a usable server address, or a sentence saying what is
  /// wrong. Exposed for form validation so the UI and this class agree on what
  /// counts as valid.
  static String? validateBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Enter a server address.';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.isAbsolute) {
      return 'Enter a full address, starting with http:// or https://.';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'Only http:// and https:// addresses work.';
    }
    if (uri.host.isEmpty) return 'That address has no server name.';
    if (uri.userInfo.isNotEmpty) {
      return 'Leave the username out of the address; enter it below.';
    }
    return null;
  }
}

/// Overridable so tests can build clients that talk to an in-process server.
final webDavClientFactoryProvider = Provider<WebDavClientFactory>((ref) {
  return (config, vault) => WebDavClient.forConfig(config, vault);
});

/// Live state for every saved server, keyed by id.
///
/// Several servers can be connected at once; this map is what makes that
/// visible. Watch it for the server list, and use
/// `ref.read(serverSessionsProvider.notifier)` to connect or disconnect.
final serverSessionsProvider =
    StateNotifierProvider<ServerSessionsNotifier, Map<String, ServerSession>>(
        (ref) {
  final notifier = ServerSessionsNotifier(
    vault: ref.watch(credentialVaultProvider),
    clientFactory: ref.watch(webDavClientFactoryProvider),
  );
  notifier.sync(ref.read(serverListProvider));
  ref.listen<List<ServerConfigModel>>(
    serverListProvider,
    (_, next) => notifier.sync(next),
  );
  return notifier;
});

/// The server the browse UI is looking at, or null before one is picked.
///
/// Only a focus: switching it connects and disconnects nothing, which is what
/// lets a transfer keep running on a server the user has navigated away from.
final activeServerProvider = StateProvider<String?>((ref) => null);

/// The active server's saved settings, or null if none is selected.
final activeServerConfigProvider = Provider<ServerConfigModel?>((ref) {
  final id = ref.watch(activeServerProvider);
  if (id == null) return null;
  for (final config in ref.watch(serverListProvider)) {
    if (config.id == id) return config;
  }
  return null;
});

/// The active server's session, or null if none is selected.
final activeSessionProvider = Provider<ServerSession?>((ref) {
  final id = ref.watch(activeServerProvider);
  if (id == null) return null;
  return ref.watch(serverSessionsProvider)[id];
});

/// Sessions that are connected right now, for a transfer destination picker.
final connectedSessionsProvider = Provider<List<ServerSession>>((ref) {
  return ref
      .watch(serverSessionsProvider)
      .values
      .where((session) => session.isConnected)
      .toList();
});

/// The transfer queue. Watch it for progress; use
/// `ref.read(transferEngineProvider.notifier)` to enqueue and cancel.
///
/// It resolves clients through the session map, so a transfer can only run
/// between connected servers and stops making sense the moment one is
/// disconnected — which is exactly what the user asked for.
final transferEngineProvider =
    StateNotifierProvider<TransferEngine, List<TransferJob>>((ref) {
  return TransferEngine(
    clients: (serverId) =>
        ref.read(serverSessionsProvider.notifier).clientFor(serverId),
  );
});

/// Connects every server marked `autoConnect`, once per app run.
///
/// Call it from the first screen that needs servers — repeat calls are no-ops,
/// so a rebuild cannot start a second round of connections.
Future<void> bootstrapServers(WidgetRef ref) {
  return ref.read(serverSessionsProvider.notifier).connectAutoConnect();
}

/// The same bootstrap for code holding a [Ref] rather than a [WidgetRef].
Future<void> bootstrapServersWith(Ref ref) {
  return ref.read(serverSessionsProvider.notifier).connectAutoConnect();
}
