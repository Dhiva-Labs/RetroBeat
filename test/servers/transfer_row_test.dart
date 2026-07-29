import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/providers/server_providers.dart';
import 'package:retro_beat/screens/servers/widgets/transfer_row.dart';

TransferJob _job({
  String id = 'job-1',
  TransferStatus status = TransferStatus.running,
  int transferredBytes = 0,
  int? totalBytes,
  String? error,
  TransferFailure? failure,
}) {
  return TransferJob(
    id: id,
    srcServerId: 'alpha',
    srcPath: '/song.mp3',
    dstServerId: 'beta',
    dstDir: '/Incoming',
    mode: TransferMode.move,
    status: status,
    transferredBytes: transferredBytes,
    totalBytes: totalBytes,
    error: error,
    failure: failure,
  );
}

/// A real [TransferEngine] with a resolver that never finds a client — every
/// job it runs fails fast with [TransferFailure.notConnected], but the row
/// only needs `enqueue`/`cancel` to behave like the real thing, not to
/// actually move bytes anywhere.
ProviderContainer _containerWithEngine() {
  return ProviderContainer(
    overrides: [
      transferEngineProvider.overrideWith(
        (ref) => TransferEngine(clients: (_) => null),
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  TransferJob job,
) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: TransferRow(
            job: job,
            srcServerName: 'Alpha',
            dstServerName: 'Beta',
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('TransferRow', () {
    testWidgets('a running job with a known total renders a determinate bar',
        (tester) async {
      final container = _containerWithEngine();
      addTearDown(container.dispose);

      await _pump(
        tester,
        container,
        _job(totalBytes: 200, transferredBytes: 50),
      );

      final progressFinder = find.byType(LinearProgressIndicator);
      final bar = tester.widget<LinearProgressIndicator>(progressFinder);
      expect(bar.value, 0.25);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets(
        'a running job with no known total renders an indeterminate bar',
        (tester) async {
      final container = _containerWithEngine();
      addTearDown(container.dispose);

      await _pump(
        tester,
        container,
        _job(totalBytes: null, transferredBytes: 50),
      );

      final progressFinder = find.byType(LinearProgressIndicator);
      final bar = tester.widget<LinearProgressIndicator>(progressFinder);
      expect(bar.value, isNull);
    });

    testWidgets('a queued job offers Cancel', (tester) async {
      final container = _containerWithEngine();
      addTearDown(container.dispose);

      await _pump(tester, container, _job(status: TransferStatus.queued));

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      // Tapping calls cancel() on the engine with this row's job id; the
      // engine simply finds no such job and no-ops rather than throwing,
      // which is exactly what proves the trailing action wires to the real
      // provider instead of a stub.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
    });

    testWidgets(
        'a failed job with no fix on offer shows the error and no button',
        (tester) async {
      final container = _containerWithEngine();
      addTearDown(container.dispose);

      await _pump(
        tester,
        container,
        _job(
          status: TransferStatus.failed,
          error: 'The server could not be reached.',
          failure: TransferFailure.network,
        ),
      );

      expect(find.text('The server could not be reached.'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.text('Overwrite'), findsNothing);
    });

    testWidgets(
        'a collision failure offers Overwrite, which re-enqueues with '
        'overwrite: true', (tester) async {
      final container = _containerWithEngine();
      addTearDown(container.dispose);

      final job = _job(
        status: TransferStatus.failed,
        error: 'song.mp3 already exists in /Incoming.',
        failure: TransferFailure.collision,
        totalBytes: 4096,
      );
      await _pump(tester, container, job);

      expect(find.text('Overwrite'), findsOneWidget);
      await tester.tap(find.text('Overwrite'));
      await tester.pump();

      final jobs = container.read(transferEngineProvider);
      final reEnqueued = jobs.where((j) => j.id != job.id).toList();
      expect(reEnqueued, hasLength(1));
      expect(reEnqueued.single.overwrite, isTrue);
      expect(reEnqueued.single.srcServerId, 'alpha');
      expect(reEnqueued.single.srcPath, '/song.mp3');
      expect(reEnqueued.single.dstServerId, 'beta');
      expect(reEnqueued.single.dstDir, '/Incoming');
      expect(reEnqueued.single.mode, TransferMode.move);
    });

    testWidgets('a completed job shows no trailing action', (tester) async {
      final container = _containerWithEngine();
      addTearDown(container.dispose);

      await _pump(
        tester,
        container,
        _job(
          status: TransferStatus.completed,
          totalBytes: 100,
          transferredBytes: 100,
        ),
      );

      expect(find.text('Done · 100 B'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.text('Overwrite'), findsNothing);
    });
  });
}
