import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/data/server/credential_vault.dart';

import 'dev_server_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSecretStore store;
  late CredentialVault vault;

  setUp(() {
    store = FakeSecretStore();
    vault = CredentialVault(store);
  });

  test('stores and reads a password back', () async {
    await vault.store('server-1', 'hunter2');
    expect(await vault.read('server-1'), 'hunter2');
  });

  test('keys entries by server id', () async {
    await vault.store('server-1', 'hunter2');
    expect(store.entries.keys, ['retrobeat_server_server-1']);
    expect(CredentialVault.keyFor('server-1'), 'retrobeat_server_server-1');
  });

  test('a password that was never stored reads as null', () async {
    expect(await vault.read('nobody'), isNull);
  });

  test('storing again replaces the old password', () async {
    await vault.store('server-1', 'old');
    await vault.store('server-1', 'new');
    expect(await vault.read('server-1'), 'new');
    expect(store.entries, hasLength(1));
  });

  test('delete removes the entry, and deleting nothing is fine', () async {
    await vault.store('server-1', 'hunter2');
    await vault.delete('server-1');
    expect(store.entries, isEmpty);
    expect(await vault.read('server-1'), isNull);
    await expectLater(vault.delete('server-1'), completes);
  });

  test('servers do not see each other\'s passwords', () async {
    await vault.store('server-1', 'one');
    await vault.store('server-2', 'two');
    expect(await vault.read('server-1'), 'one');
    expect(await vault.read('server-2'), 'two');
  });

  group('with no keychain', () {
    setUp(() => store.available = false);

    test('store, read and delete all raise the typed failure', () async {
      await expectLater(
        vault.store('server-1', 'hunter2'),
        throwsA(isA<VaultUnavailableException>()),
      );
      await expectLater(
        vault.read('server-1'),
        throwsA(isA<VaultUnavailableException>()),
      );
      await expectLater(
        vault.delete('server-1'),
        throwsA(isA<VaultUnavailableException>()),
      );
    });

    test('nothing is written anywhere as a fallback', () async {
      await vault.store('server-1', 'hunter2').catchError((_) {});
      expect(store.entries, isEmpty);
    });

    test('the failure explains itself without naming a secret', () {
      const failure = VaultUnavailableException();
      expect(failure.message, contains('keychain'));
      expect(failure.toString(), contains('VaultUnavailableException'));
    });
  });

  test('a missing platform plugin becomes the same typed failure', () async {
    // No plugins are registered in a unit test, so the keychain-backed store
    // is talking to a channel with nothing on the other end — the same
    // situation as a Linux box with no keyring daemon.
    final keychain = KeychainSecretStore();
    await expectLater(
      keychain.read('retrobeat_server_x'),
      throwsA(isA<VaultUnavailableException>()),
    );
  });

  test('the vault never prints anything about its contents', () async {
    await vault.store('server-1', 'hunter2');
    expect(vault.toString(), isNot(contains('hunter2')));
    expect(vault.toString(), 'CredentialVault()');
  });
}
