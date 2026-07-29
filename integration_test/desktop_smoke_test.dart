import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:retro_beat/data/services/audio_handler.dart';
import 'package:retro_beat/main.dart' as app;
import 'package:retro_beat/providers/audio_provider.dart';
import 'package:retro_beat/providers/folders_provider.dart';

/// Runs the real app end to end on a real desktop backend: scans a folder of
/// generated audio into the library and plays one back.
///
/// This is the one check in the repo that nothing here mocks — Hive, the
/// libmpv-backed player, window_manager, the actual file scan — because the
/// desktop port lives or dies on those working together, and a widget test
/// with faked plugins cannot tell you that they do.
///
/// Fixtures are generated with `ffmpeg` rather than checked in as binary
/// files, and the test skips (does not fail) if `ffmpeg` is not on PATH —
/// there is nothing meaningful to assert about the scanner without real,
/// decodable audio to feed it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const titles = ['Smoke One', 'Smoke Two', 'Smoke Three'];

  late Directory fixtureDir;
  late bool ffmpegAvailable;

  setUp(() async {
    fixtureDir = await Directory.systemTemp.createTemp('retrobeat_smoke_test_');
    ffmpegAvailable = await _generateFixtures(fixtureDir, titles);
  });

  tearDown(() async {
    if (fixtureDir.existsSync()) {
      await fixtureDir.delete(recursive: true);
    }
  });

  testWidgets(
    'scans a folder, lists its songs, and plays one back',
    (tester) async {
      if (!ffmpegAvailable) {
        markTestSkipped('ffmpeg is not on PATH; nothing to scan.');
        return;
      }

      // Runs the exact entrypoint a real launch uses — Hive, the libmpv
      // backend, window_manager, RetroBeatAudioHandler — rather than
      // reconstructing a lookalike widget tree by hand.
      app.main();
      await _pumpUntilFound(tester, find.byType(MaterialApp));

      // listen: false — this is a one-off imperative read from test code, not
      // a widget rebuilding itself, so there is nothing for it to depend on.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );

      // Point the scanner at the fixtures directly instead of driving
      // file_selector's native folder picker, which opens a separate
      // top-level window no test harness can click through.
      await container
          .read(desktopScanFoldersProvider.notifier)
          .addFolder(fixtureDir.path);
      await container.read(libraryLoaderProvider).load(prompt: false);

      for (final title in titles) {
        await _pumpUntilFound(tester, find.text(title));
      }
      expect(container.read(songsProvider).length, titles.length);

      await tester.ensureVisible(find.text(titles.first));
      await tester.tap(find.text(titles.first));
      await tester.pump(const Duration(seconds: 1));

      final handler = container.read(audioHandlerProvider);
      final position = await _waitForPositionPast(
        tester,
        handler,
        const Duration(seconds: 1),
      );

      expect(
        position,
        greaterThan(const Duration(seconds: 1)),
        reason: 'playback position never advanced past 1s',
      );
    },
  );
}

/// Three short, distinctly-titled tracks — long enough (35s) to clear the
/// "hide short audio" cutoff (30s) with room to spare.
Future<bool> _generateFixtures(Directory dir, List<String> titles) async {
  for (var i = 0; i < titles.length; i++) {
    try {
      final result = await Process.run('ffmpeg', [
        '-y',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=${440 + i * 110}:duration=35',
        '-metadata',
        'title=${titles[i]}',
        '-metadata',
        'artist=RetroBeat Smoke Test',
        '-metadata',
        'album=Fixtures',
        '${dir.path}/track_$i.mp3',
      ]);
      if (result.exitCode != 0) return false;
    } on ProcessException {
      return false; // ffmpeg is not installed on this machine.
    }
  }
  return true;
}

/// Pumps in bounded steps rather than `pumpAndSettle` — the splash screen's
/// indeterminate spinner never stops scheduling frames on its own, so
/// `pumpAndSettle` would just time out waiting for it to.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 250),
  int maxTries = 120,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
  }
  throw TestFailure('Timed out waiting to find $finder');
}

/// Polls the handler's own playback state rather than reading it once after a
/// fixed delay, so the assertion is not a guess about how long libmpv takes to
/// open and start decoding a file on whatever machine is running this.
Future<Duration> _waitForPositionPast(
  WidgetTester tester,
  RetroBeatAudioHandler handler,
  Duration threshold, {
  Duration step = const Duration(milliseconds: 500),
  int maxTries = 40,
}) async {
  var last = Duration.zero;
  for (var i = 0; i < maxTries; i++) {
    last = handler.playbackState.valueOrNull?.updatePosition ?? Duration.zero;
    if (last > threshold) return last;
    await tester.pump(step);
  }
  return last;
}
