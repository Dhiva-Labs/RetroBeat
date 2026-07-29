import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/server/credential_vault.dart';
import '../../providers/server_providers.dart';

/// Add a server, or edit one already saved.
///
/// "Test connection" never touches the real keychain: it feeds whatever is
/// currently typed into a throwaway [WebDavClient] via an in-memory
/// [SecretStore], so it works before Save and never conflates "the keychain
/// is unavailable" with "the password is wrong".
class ServerFormScreen extends ConsumerStatefulWidget {
  const ServerFormScreen({super.key, this.existing});

  /// Null to add a new server; the server being edited otherwise.
  final ServerConfigModel? existing;

  @override
  ConsumerState<ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends ConsumerState<ServerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _rootPathController;
  late bool _autoConnect;
  bool _obscurePassword = true;

  bool _testing = false;
  bool? _testOk;
  String? _testMessage;

  bool _saving = false;
  String? _saveError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _baseUrlController = TextEditingController(text: existing?.baseUrl ?? '');
    _usernameController = TextEditingController(text: existing?.username ?? '');
    // Never echoed: blank means "leave the stored password alone" on save,
    // and the field starts blank whether adding or editing.
    _passwordController = TextEditingController();
    _rootPathController =
        TextEditingController(text: existing?.rootPath ?? '/');
    _autoConnect = existing?.autoConnect ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _rootPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit server' : 'Add server')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('serverForm_save'),
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Save'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          children: [
            TextFormField(
              key: const Key('serverForm_name'),
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Defaults to the server address',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('serverForm_baseUrl'),
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'https://nas.local:5006/dav',
              ),
              validator: (value) =>
                  ServerListNotifier.validateBaseUrl(value ?? ''),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('serverForm_username'),
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter a username.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('serverForm_password'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: _isEditing ? 'Unchanged' : null,
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (!_isEditing && (value == null || value.isEmpty)) {
                  return 'Enter the password.';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              key: const Key('serverForm_advanced'),
              title: const Text('Advanced'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                TextFormField(
                  key: const Key('serverForm_rootPath'),
                  controller: _rootPathController,
                  decoration: const InputDecoration(
                    labelText: 'Root path',
                    hintText: '/',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('serverForm_autoConnect'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Connect automatically'),
                  subtitle: const Text('Connect this server on startup'),
                  value: _autoConnect,
                  onChanged: (value) => setState(() => _autoConnect = value),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('serverForm_testConnection'),
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering_rounded),
              label: const Text('Test connection'),
            ),
            if (_testMessage != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _testOk == true
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: _testOk == true ? scheme.primary : scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testMessage!,
                      style: TextStyle(
                        color: _testOk == true ? scheme.primary : scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_saveError != null) ...[
              const SizedBox(height: 12),
              Text(_saveError!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    final urlError =
        ServerListNotifier.validateBaseUrl(_baseUrlController.text);
    if (urlError != null) {
      setState(() {
        _testOk = false;
        _testMessage = urlError;
      });
      return;
    }

    setState(() {
      _testing = true;
      _testOk = null;
      _testMessage = null;
    });

    // A blank password while editing means "unchanged" everywhere else in
    // this form, so testing has to mean the same thing — otherwise every
    // edit would need the password retyped just to confirm the server is
    // still reachable.
    var password = _passwordController.text;
    final existing = widget.existing;
    if (password.isEmpty && existing != null) {
      password =
          await ref.read(credentialVaultProvider).read(existing.id) ?? '';
    }

    final candidate = ServerConfigModel(
      id: 'preview',
      name: _nameController.text,
      baseUrl: _baseUrlController.text,
      username: _usernameController.text,
      rootPath:
          _rootPathController.text.isEmpty ? '/' : _rootPathController.text,
    );
    final vault = CredentialVault(_TypedPasswordStore(password));
    final client = ref.read(webDavClientFactoryProvider)(candidate, vault);

    try {
      await client.testConnection(path: candidate.rootPath);
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMessage = 'Connected successfully.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = describeServerError(error);
      });
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    final rootPath =
        _rootPathController.text.isEmpty ? '/' : _rootPathController.text;

    try {
      final existing = widget.existing;
      if (existing != null) {
        final updated = existing.copyWith(
          name: _nameController.text,
          baseUrl: _baseUrlController.text,
          username: _usernameController.text,
          rootPath: rootPath,
          autoConnect: _autoConnect,
        );
        await ref.read(serverListProvider.notifier).update(
              updated,
              password: _passwordController.text.isEmpty
                  ? null
                  : _passwordController.text,
            );
      } else {
        await ref.read(serverListProvider.notifier).add(
              name: _nameController.text,
              baseUrl: _baseUrlController.text,
              username: _usernameController.text,
              password: _passwordController.text,
              rootPath: rootPath,
              autoConnect: _autoConnect,
            );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = describeServerError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Feeds one already-typed password to a throwaway [WebDavClient], so "Test
/// connection" can prove the current form values work without writing
/// anything to the real keychain.
class _TypedPasswordStore implements SecretStore {
  const _TypedPasswordStore(this._password);

  final String _password;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<String?> read(String key) async => _password;

  @override
  Future<void> delete(String key) async {}
}
