import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/empty_state.dart';
import '../../providers/audio_provider.dart';
import '../../providers/server_providers.dart';
import '../home/widgets/mini_player.dart';
import 'providers/transfer_indicators.dart';
import 'server_browser_screen.dart';
import 'server_form_screen.dart';
import 'transfers_screen.dart';
import 'widgets/server_tile.dart';

/// Every saved server: its connection state, and the door into browsing,
/// editing or removing it.
class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(serverListProvider);
    final sessions = ref.watch(serverSessionsProvider);
    final hasNowPlaying = ref.watch(currentSongProvider) != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        actions: const [_TransfersButton(), SizedBox(width: 4)],
      ),
      floatingActionButton: Padding(
        // Clears the mini player rather than sitting on top of it.
        padding: EdgeInsets.only(bottom: hasNowPlaying ? 64 : 0),
        child: FloatingActionButton(
          key: const Key('serversScreen_addFab'),
          tooltip: 'Add server',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ServerFormScreen()),
          ),
          child: const Icon(Icons.add_rounded),
        ),
      ),
      body: Stack(
        children: [
          configs.isEmpty
              ? EmptyState(
                  icon: Icons.dns_rounded,
                  message: 'No servers yet.\nAdd one to browse and stream '
                      'your music over WebDAV.',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServerFormScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add server'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: configs.length,
                  itemBuilder: (context, index) {
                    final config = configs[index];
                    return ServerTile(
                      config: config,
                      session: sessions[config.id],
                      onTap: () => _open(context, ref, config),
                      onConnect: () => ref
                          .read(serverSessionsProvider.notifier)
                          .connect(config.id),
                      onDisconnect: () => ref
                          .read(serverSessionsProvider.notifier)
                          .disconnect(config.id),
                      onEdit: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServerFormScreen(existing: config),
                        ),
                      ),
                      onRemove: () => _confirmRemove(context, ref, config),
                    );
                  },
                ),
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }

  /// Makes [config] the active server, connecting first if it is not already,
  /// then opens its browser — or explains why not, since [connect] never
  /// throws and a failure otherwise vanishes silently.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    ServerConfigModel config,
  ) async {
    ref.read(activeServerProvider.notifier).state = config.id;

    final sessionsNotifier = ref.read(serverSessionsProvider.notifier);
    var session = ref.read(serverSessionsProvider)[config.id];
    if (session == null || !session.isConnected) {
      await sessionsNotifier.connect(config.id);
    }
    if (!context.mounted) return;

    session = ref.read(serverSessionsProvider)[config.id];
    if (session != null && session.isConnected) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ServerBrowserScreen()),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(session?.message ?? 'Could not connect.')),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ServerConfigModel config,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${config.name}?'),
        content: const Text(
          'This removes the server and its saved password from your '
          "system's keychain too.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(serverListProvider.notifier).remove(config.id);
    } on VaultUnavailableException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearMaterialBanners();
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text(error.message),
          actions: [
            TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
    }
  }
}

class _TransfersButton extends ConsumerWidget {
  const _TransfersButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(activeTransferCountProvider);
    return IconButton(
      tooltip: 'Transfers',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.swap_vert_rounded),
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TransfersScreen()),
      ),
    );
  }
}
