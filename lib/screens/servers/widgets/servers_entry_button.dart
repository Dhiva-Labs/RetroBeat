import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/transfer_indicators.dart';
import '../servers_screen.dart';

/// Opens the Servers area from anywhere in the app; the dot lights up while a
/// transfer is queued or running, so progress is visible without opening the
/// Servers screen first.
class ServersEntryButton extends ConsumerWidget {
  const ServersEntryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasActiveTransfers = ref.watch(activeTransferCountProvider) > 0;

    return IconButton(
      tooltip: 'Servers',
      icon: Badge(
        isLabelVisible: hasActiveTransfers,
        smallSize: 8,
        child: const Icon(Icons.dns_rounded),
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ServersScreen()),
      ),
    );
  }
}
