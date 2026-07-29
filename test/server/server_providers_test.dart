import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:retro_beat/data/models/server_config_model.dart';
import 'package:retro_beat/data/server/credential_vault.dart';
import 'package:retro_beat/providers/server_providers.dart';

import 'dev_server_fixture.dart';

void main() {
  late Directory hiveDir;
  late Box<ServerConfigModel> box;
  late FakeSecretStore store;
  late CredentialVault vault;
  late ProviderContainer container;
  late ServerListNotifier servers;
  late ServerSessionsNotifier sessions;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('retrobeat_hive');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ServerConfigModelAdapter());
    }
    box = await Hive.openBox<ServerConfigModel>('servers_test');
    store = FakeSecretStore();
    vault = CredentialVault(store);
    container = ProviderContainer(
      overrides: [
        serverBoxProvider.overrideWithValue(box),
        credentialVaultProvider.overrideWithValue(vault),
      ],
    );
    servers = container.read(serverListProvider.notifier);
    sessions = container.read(serverSessionsProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  group('server list', () {
    test('add writes the password to the vault and the rest to Hive', () async {
      final config = await servers.add(
        name: 'NAS',
        baseUrl: 'https://nas.local:5006/dav',
        username: 'me',
        password: 'hunter2-correct-horse',
        rootPath: '/Music/',
      );

      expect(container.read(serverListProvider), [config]);
      expect(box.get(config.id)?.name, 'NAS');
      expect(box.get(config.id)?.rootPath, '/Music');
      expect(box.get(config.id)?.baseUrl, 'https://nas.local:5006/dav');
      expect(box.get(config.id)?.autoConnect, isTrue);

      expect(
        store.entries['retrobeat_server_${config.id}'],
        'hunter2-correct-horse',
      );
    });

    test('the password reaches no part of the Hive file', () async {
      const password = 'a-very-distinctive-password';
      final config = await servers.add(
        name: 'NAS',
        baseUrl: 'http://nas.local',
        username: 'me',
        password: password,
      );
      await box.flush();

      final stored = box.get(config.id)!;
      expect(stored.toString(), isNot(contains(password)));

      final bytes = File('${hiveDir.path}/servers_test.hive').readAsBytesSync();
      expect(
        String.fromCharCodes(bytes),
        isNot(contains(password)),
        reason: 'Hive is an unencrypted file; secrets belong in the keychain',
      );
    });

    test('remove clears both the config and the password', () async {
      final config = await servers.add(
        name: 'NAS',
        baseUrl: 'http://nas.local',
        username: 'me',
        password: 'hunter2',
      );
      await servers.remove(config.id);

      expect(container.read(serverListProvider), isEmpty);
      expect(box.get(config.id), isNull);
      expect(store.entries, isEmpty);
    });

    test('update changes the password only when one is given', () async {
      final config = await servers.add(
        name: 'NAS',
        baseUrl: 'http://nas.local',
        username: 'me',
        password: 'first',
      );

      await servers.update(config.copyWith(name: 'Renamed'));
      expect(container.read(serverListProvider).single.name, 'Renamed');
      expect(store.entries['retrobeat_server_${config.id}'], 'first');

      await servers.update(
        config.copyWith(name: 'Renamed'),
        password: 'second',
      );
      expect(store.entries['retrobeat_server_${config.id}'], 'second');
    });

    test('an empty replacement password is refused', () async {
      final config = await servers.add(
        name: 'NAS',
        baseUrl: 'http://nas.local',
        username: 'me',
        password: 'first',
      );
      await expectLater(
        servers.update(config, password: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(store.entries['retrobeat_server_${config.id}'], 'first');
    });

    test('a server with no keychain to store into is not saved', () async {
      store.available = false;
      await expectLater(
        servers.add(
          name: 'NAS',
          baseUrl: 'http://nas.local',
          username: 'me',
          password: 'hunter2',
        ),
        throwsA(isA<VaultUnavailableException>()),
      );
      expect(box.values, isEmpty);
      expect(container.read(serverListProvider), isEmpty);
    });

    test('rejects addresses that cannot work', () async {
      expect(ServerListNotifier.validateBaseUrl(''), isNotNull);
      expect(ServerListNotifier.validateBaseUrl('nas.local'), isNotNull);
      expect(ServerListNotifier.validateBaseUrl('ftp://nas.local'), isNotNull);
      expect(
        ServerListNotifier.validateBaseUrl('http://me:pw@nas.local'),
        isNotNull,
      );
      expect(ServerListNotifier.validateBaseUrl('https://nas.local'), isNull);

      await expectLater(
        servers.add(
          name: 'Bad',
          baseUrl: 'nas.local',
          username: 'me',
          password: 'x',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('isSecure marks plain-http servers for the UI to badge', () async {
      final plain = await servers.add(
        name: 'Plain',
        baseUrl: 'http://nas.local',
        username: 'me',
        password: 'x',
      );
      final secure = await servers.add(
        name: 'Secure',
        baseUrl: 'https://nas.local',
        username: 'me',
        password: 'x',
      );
      expect(plain.isSecure, isFalse);
      expect(secure.isSecure, isTrue);
    });
  });

  group('sessions', () {
    late DevServer alpha;
    late DevServer beta;

    setUp(() async {
      alpha = await DevServer.start();
      beta = await DevServer.start();
    });

    tearDown(() async {
      await alpha.stop();
      await beta.stop();
    });

    Future<ServerConfigModel> save(
      DevServer server, {
      required String name,
      bool autoConnect = true,
    }) {
      return servers.add(
        name: name,
        baseUrl: server.baseUrl.toString(),
        username: server.username,
        password: server.password,
        autoConnect: autoConnect,
      );
    }

    test('a new server shows up disconnected', () async {
      // Created before the server is saved, so the listener path is exercised.
      expect(container.read(serverSessionsProvider), isEmpty);
      final config = await save(alpha, name: 'Alpha');

      final session = container.read(serverSessionsProvider)[config.id]!;
      expect(session.status, ServerConnectionStatus.disconnected);
      expect(session.client, isNull);
      expect(session.config.name, 'Alpha');
    });

    test('two servers stay connected at the same time', () async {
      final one = await save(alpha, name: 'Alpha');
      final two = await save(beta, name: 'Beta');

      await sessions.connect(one.id);
      await sessions.connect(two.id);

      final state = container.read(serverSessionsProvider);
      expect(state[one.id]!.status, ServerConnectionStatus.connected);
      expect(state[two.id]!.status, ServerConnectionStatus.connected);
      expect(container.read(connectedSessionsProvider), hasLength(2));
      expect(sessions.clientFor(one.id), isNotNull);
      expect(sessions.clientFor(two.id), isNotNull);
    });

    test('disconnecting one leaves the other alone', () async {
      final one = await save(alpha, name: 'Alpha');
      final two = await save(beta, name: 'Beta');
      await sessions.connect(one.id);
      await sessions.connect(two.id);

      sessions.disconnect(one.id);

      final state = container.read(serverSessionsProvider);
      expect(state[one.id]!.status, ServerConnectionStatus.disconnected);
      expect(state[two.id]!.status, ServerConnectionStatus.connected);
      expect(sessions.clientFor(one.id), isNull);
    });

    test('switching the active server disconnects nothing', () async {
      final one = await save(alpha, name: 'Alpha');
      final two = await save(beta, name: 'Beta');
      await sessions.connect(one.id);
      await sessions.connect(two.id);

      container.read(activeServerProvider.notifier).state = one.id;
      expect(container.read(activeServerConfigProvider)?.id, one.id);
      container.read(activeServerProvider.notifier).state = two.id;

      expect(container.read(activeSessionProvider)?.config.id, two.id);
      expect(container.read(connectedSessionsProvider), hasLength(2));
    });

    test('a bad password leaves the session in error with a message', () async {
      final config = await save(alpha, name: 'Alpha');
      await vault.store(config.id, 'wrong-password');

      await sessions.connect(config.id);

      final session = container.read(serverSessionsProvider)[config.id]!;
      expect(session.status, ServerConnectionStatus.error);
      expect(session.message, isNotNull);
      expect(session.message, isNot(contains('wrong-password')));
      expect(session.client, isNull);
    });

    test('an unreachable server fails without throwing', () async {
      final config = await servers.add(
        name: 'Gone',
        baseUrl: 'http://127.0.0.1:1',
        username: 'me',
        password: 'x',
      );

      await expectLater(sessions.connect(config.id), completes);
      expect(
        container.read(serverSessionsProvider)[config.id]!.status,
        ServerConnectionStatus.error,
      );
    });

    test('the bootstrap connects only autoConnect servers, once', () async {
      final auto = await save(alpha, name: 'Alpha');
      final manual = await save(beta, name: 'Beta', autoConnect: false);

      await sessions.connectAutoConnect();

      var state = container.read(serverSessionsProvider);
      expect(state[auto.id]!.status, ServerConnectionStatus.connected);
      expect(state[manual.id]!.status, ServerConnectionStatus.disconnected);

      // A second call must not start another round of connections.
      sessions.disconnect(auto.id);
      await sessions.connectAutoConnect();
      state = container.read(serverSessionsProvider);
      expect(state[auto.id]!.status, ServerConnectionStatus.disconnected);
    });

    test('removing a connected server drops its session', () async {
      final config = await save(alpha, name: 'Alpha');
      await sessions.connect(config.id);

      await servers.remove(config.id);

      expect(container.read(serverSessionsProvider), isEmpty);
      expect(sessions.clientFor(config.id), isNull);
    });

    test('remoteStreamSpec hands a player a URL and an auth header', () async {
      alpha.writeText('song.mp3', 'payload');
      final config = await save(alpha, name: 'Alpha');

      // Deliberately not connected: playback needs credentials, not a session.
      final spec = await sessions.remoteStreamSpec(config.id, '/song.mp3');

      expect(spec.url, Uri.parse('${alpha.baseUrl}/song.mp3'));
      expect(spec.url.userInfo, isEmpty);
      expect(spec.headers['authorization'], basicHeaderFor(alpha));
      expect(spec.toString(), isNot(contains(alpha.password)));
    });

    test('remoteStreamSpec for an unknown server is an argument error',
        () async {
      await expectLater(
        sessions.remoteStreamSpec('nope', '/song.mp3'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
