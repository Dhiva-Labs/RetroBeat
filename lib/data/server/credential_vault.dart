import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants/app_constants.dart';

/// Thrown when the vault cannot be reached or used.
///
/// Messages describe the *keychain*, never the secret: nothing that passes
/// through this file may appear in an exception, a log line or a `toString`.
class VaultException implements Exception {
  const VaultException(this.message);

  /// Safe to show the user verbatim.
  final String message;

  @override
  String toString() => 'VaultException: $message';
}

/// The platform has no usable keychain — typically a Linux session with no
/// `gnome-keyring`/`kwallet` running, or a headless box.
///
/// There is no fallback: writing passwords to a plain file instead would make
/// "stored in your keychain" a lie. The UI should say what is missing and let
/// the user install or start it.
class VaultUnavailableException extends VaultException {
  const VaultUnavailableException([
    super.message = 'No system keychain is available, so server passwords '
        'cannot be stored. On Linux this usually means gnome-keyring or '
        'KWallet is not running.',
  ]);

  @override
  String toString() => 'VaultUnavailableException: $message';
}

/// The storage behind [CredentialVault].
///
/// Exists so tests can run without a keychain — see `FakeSecretStore` in
/// `test/server/`. Implementations must throw, never degrade, when they cannot
/// keep a secret secret.
abstract class SecretStore {
  Future<void> write(String key, String value);

  Future<String?> read(String key);

  Future<void> delete(String key);
}

/// [SecretStore] over the OS keychain: Keychain on macOS/iOS, DPAPI-backed
/// credential store on Windows, libsecret on Linux, EncryptedSharedPreferences
/// on Android.
class KeychainSecretStore implements SecretStore {
  KeychainSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) =>
      _guard(() => _storage.write(key: key, value: value));

  @override
  Future<String?> read(String key) => _guard(() => _storage.read(key: key));

  @override
  Future<void> delete(String key) => _guard(() => _storage.delete(key: key));

  /// The plugin reports a missing keychain as a [PlatformException] whose
  /// message quotes the platform's own error, and a missing plugin (desktop
  /// build without the plugin registered) as [MissingPluginException]. Neither
  /// is actionable as-is, and the platform message can be long and technical,
  /// so both become the one typed failure the UI knows how to explain.
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MissingPluginException {
      throw const VaultUnavailableException(
        'Secure storage is not available in this build, so server passwords '
        'cannot be stored.',
      );
    } on PlatformException {
      throw const VaultUnavailableException();
    }
  }
}

/// Server passwords, held in the OS keychain and keyed by server id.
///
/// The rest of the app never holds a password in a field: it asks for one at
/// the moment a request needs it and lets it go out of scope again. Nothing
/// here logs, and no method returns anything that would print a secret.
class CredentialVault {
  CredentialVault(this._store);

  /// The production vault.
  CredentialVault.keychain() : _store = KeychainSecretStore();

  final SecretStore _store;

  /// The keychain entry for [serverId]. Public because uninstall/diagnostic
  /// code needs to name the entry, not because callers should hand-roll it.
  static String keyFor(String serverId) =>
      '${AppConstants.serverSecretPrefix}$serverId';

  /// Stores (or replaces) the password for [serverId].
  ///
  /// Throws [VaultUnavailableException] if there is no keychain. Callers must
  /// let that reach the UI rather than carrying on — a server saved without
  /// its password can never connect.
  Future<void> store(String serverId, String password) =>
      _store.write(keyFor(serverId), password);

  /// The stored password for [serverId], or null if none was ever stored (or
  /// the user removed it from their keychain by hand).
  Future<String?> read(String serverId) => _store.read(keyFor(serverId));

  /// Removes the password for [serverId]. Deleting an absent entry succeeds,
  /// so this is safe to call on a half-created server.
  Future<void> delete(String serverId) => _store.delete(keyFor(serverId));

  @override
  String toString() => 'CredentialVault()';
}
