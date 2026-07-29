import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/server_providers.dart';
import 'entry_format.dart';

/// One row in the Transfers panel.
///
/// Server names are passed in rather than looked up here, so this widget (and
/// its test) never needs the server list provider — only [_TrailingAction]
/// touches Riverpod, and only for cancel/overwrite.
class TransferRow extends StatelessWidget {
  const TransferRow({
    super.key,
    required this.job,
    required this.srcServerName,
    required this.dstServerName,
  });

  final TransferJob job;
  final String srcServerName;
  final String dstServerName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final modeLabel = job.mode == TransferMode.move ? 'Move' : 'Copy';

    return ListTile(
      key: ValueKey('transferRow_${job.id}'),
      leading: Icon(_iconFor(job.status), color: _colorFor(job.status, scheme)),
      title: Text(job.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          Text(
            '$modeLabel · $srcServerName → $dstServerName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          _ProgressLine(job: job, scheme: scheme),
        ],
      ),
      trailing: _TrailingAction(job: job),
    );
  }

  IconData _iconFor(TransferStatus status) => switch (status) {
        TransferStatus.queued => Icons.schedule_rounded,
        TransferStatus.running => Icons.sync_rounded,
        TransferStatus.completed => Icons.check_circle_rounded,
        TransferStatus.failed => Icons.error_rounded,
        TransferStatus.cancelled => Icons.block_rounded,
      };

  Color _colorFor(TransferStatus status, ColorScheme scheme) =>
      switch (status) {
        TransferStatus.completed => scheme.primary,
        TransferStatus.failed => scheme.error,
        _ => scheme.onSurfaceVariant,
      };
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.job, required this.scheme});

  final TransferJob job;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    switch (job.status) {
      case TransferStatus.queued:
        return Text(
          'Waiting…',
          style: TextStyle(color: scheme.onSurfaceVariant),
        );
      case TransferStatus.running:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              // A null value renders Flutter's own indeterminate animation —
              // exactly the "unknown total" case this bar has to show.
              child: LinearProgressIndicator(value: job.progress, minHeight: 4),
            ),
            const SizedBox(height: 4),
            Text(
              job.totalBytes == null
                  ? formatBytes(job.transferredBytes)
                  : '${formatBytes(job.transferredBytes)} / '
                      '${formatBytes(job.totalBytes)}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      case TransferStatus.completed:
        return Text(
          'Done · ${formatBytes(job.transferredBytes)}',
          style: TextStyle(color: scheme.onSurfaceVariant),
        );
      case TransferStatus.failed:
        return Text(
          job.error ?? 'Failed.',
          style: TextStyle(color: scheme.error),
        );
      case TransferStatus.cancelled:
        return Text(
          'Cancelled.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        );
    }
  }
}

/// Cancel while it can still matter, or Overwrite when the one failure that
/// deserves a fix stares back — everything else just explains itself.
class _TrailingAction extends ConsumerWidget {
  const _TrailingAction({required this.job});

  final TransferJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (job.status == TransferStatus.queued ||
        job.status == TransferStatus.running) {
      return IconButton(
        key: ValueKey('transferCancel_${job.id}'),
        tooltip: 'Cancel',
        icon: const Icon(Icons.close_rounded),
        onPressed: () =>
            ref.read(transferEngineProvider.notifier).cancel(job.id),
      );
    }
    if (job.status == TransferStatus.failed &&
        job.failure == TransferFailure.collision) {
      return TextButton(
        key: ValueKey('transferOverwrite_${job.id}'),
        onPressed: () => ref.read(transferEngineProvider.notifier).enqueue(
              srcServerId: job.srcServerId,
              srcPath: job.srcPath,
              dstServerId: job.dstServerId,
              dstDir: job.dstDir,
              mode: job.mode,
              overwrite: true,
              totalBytes: job.totalBytes,
            ),
        child: const Text('Overwrite'),
      );
    }
    return const SizedBox.shrink();
  }
}
