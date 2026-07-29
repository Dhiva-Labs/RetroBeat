import 'package:retro_beat/data/server/credential_vault.dart';

/// A vault backed by a map, for tests that must not touch a real keychain.
///
/// A separate fixture from `test/server/dev_server_fixture.dart`'s
/// `FakeSecretStore`: that suite covers the non-UI server layer and is not
/// this feature's to touch, so the UI tests in `test/servers/` and
/// `integration_test/server_flow_test.dart` get their own copy.
class FakeSecretStore implements SecretStore {
  final Map<String, String> entries = {};

  @override
  Future<void> write(String key, String value) async {
    entries[key] = value;
  }

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<void> delete(String key) async {
    entries.remove(key);
  }
}
