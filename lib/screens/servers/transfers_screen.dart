import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/empty_state.dart';
import '../../providers/server_providers.dart';
import '../home/widgets/mini_player.dart';
import 'widgets/transfer_row.dart';

/// Every copy/move, live. Reachable from the Servers screen; this plus
/// browsing continuing underneath is the point of the whole feature.
class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(transferEngineProvider);
    final configs = ref.watch(serverListProvider);
    // Newest first: a move you just started is more interesting right now
    // than one that finished five minutes ago.
    final ordered = jobs.reversed.toList();

    String nameFor(String serverId) =>
        configs.where((c) => c.id == serverId).firstOrNull?.name ??
        'Unknown server';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: [
          if (jobs.any((job) => job.isFinished))
            TextButton(
              onPressed: () =>
                  ref.read(transferEngineProvider.notifier).clearFinished(),
              child: const Text('Clear finished'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          ordered.isEmpty
              ? const EmptyState(
                  icon: Icons.swap_vert_rounded,
                  message: 'No transfers yet.\nCopy or move a file from a '
                      'server to see it here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96, top: 8),
                  itemCount: ordered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final job = ordered[index];
                    return TransferRow(
                      job: job,
                      srcServerName: nameFor(job.srcServerId),
                      dstServerName: nameFor(job.dstServerId),
                    );
                  },
                ),
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }
}
