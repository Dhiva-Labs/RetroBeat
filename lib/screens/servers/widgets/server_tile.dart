import 'package:flutter/material.dart';

import '../../../providers/server_providers.dart';

/// One row on the Servers screen.
///
/// Deliberately not a [ConsumerWidget]: every action is a callback the caller
/// supplies, so the tile is testable by constructing it directly with a
/// [ServerSession] fixture rather than standing up Hive and a keychain.
class ServerTile extends StatelessWidget {
  const ServerTile({
    super.key,
    required this.config,
    required this.session,
    required this.onTap,
    required this.onConnect,
    required this.onDisconnect,
    required this.onEdit,
    required this.onRemove,
  });

  final ServerConfigModel config;

  /// Null before the session map has a chance to catch up with a
  /// freshly-added server; treated the same as disconnected.
  final ServerSession? session;

  final VoidCallback onTap;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  ServerConnectionStatus get _status =>
      session?.status ?? ServerConnectionStatus.disconnected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    final host = Uri.tryParse(config.baseUrl)?.host ?? config.baseUrl;

    return ListTile(
      key: ValueKey('serverTile_${config.id}'),
      onTap: onTap,
      leading: _StatusIcon(status: status, scheme: scheme),
      title: Row(
        children: [
          Flexible(
            child: Text(
              config.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!config.isSecure) ...[
            const SizedBox(width: 8),
            _Badge(
              label: 'Unencrypted',
              icon: Icons.lock_open_rounded,
              color: scheme.error,
            ),
          ],
          if (config.autoConnect) ...[
            const SizedBox(width: 8),
            _Badge(
              label: 'Auto',
              icon: Icons.bolt_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$host · ${_statusLabel(status)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (status == ServerConnectionStatus.error &&
              session?.message != null)
            Text(
              session!.message!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.error),
            ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_rounded, color: scheme.outline),
        onSelected: (value) => switch (value) {
          'connect' => onConnect(),
          'disconnect' => onDisconnect(),
          'edit' => onEdit(),
          'remove' => onRemove(),
          _ => null,
        },
        itemBuilder: (context) => [
          if (status != ServerConnectionStatus.connected &&
              status != ServerConnectionStatus.connecting)
            const PopupMenuItem(value: 'connect', child: Text('Connect')),
          if (status == ServerConnectionStatus.connected)
            const PopupMenuItem(
              value: 'disconnect',
              child: Text('Disconnect'),
            ),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(
            value: 'remove',
            child: Text('Remove', style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }

  String _statusLabel(ServerConnectionStatus status) => switch (status) {
        ServerConnectionStatus.disconnected => 'Not connected',
        ServerConnectionStatus.connecting => 'Connecting…',
        ServerConnectionStatus.connected => 'Connected',
        ServerConnectionStatus.error => 'Connection failed',
      };
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, required this.scheme});

  final ServerConnectionStatus status;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    if (status == ServerConnectionStatus.connecting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final (icon, color) = switch (status) {
      ServerConnectionStatus.connected => (Icons.dns_rounded, scheme.primary),
      ServerConnectionStatus.error => (
          Icons.error_outline_rounded,
          scheme.error,
        ),
      _ => (Icons.dns_outlined, scheme.onSurfaceVariant),
    };
    return Icon(icon, color: color);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}
