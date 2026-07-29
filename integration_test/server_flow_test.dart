import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:retro_beat/data/server/credential_vault.dart';
import 'package:retro_beat/data/services/audio_handler.dart';
import 'package:retro_beat/main.dart' as app;
import 'package:retro_beat/providers/audio_provider.dart';
import 'package:retro_beat/providers/server_providers.dart';

import '../test/servers/fake_secret_store.dart';
import '../tool/dev_webdav_server.dart';

/// End-to-end proof that the server UI, the transfer engine and remote
/// playback work together against real sockets: two dev WebDAV servers are
/// added through the real Add-server form, connected, browsed, played from —
/// which also proves the auth header survives the just_audio_media_kit
/// pipeline — and a file is moved between them.
///
/// The credential vault is the one thing swapped for a fake, so the test
/// never touches the real OS keyring or pops an unlock dialog. Everything
/// else (Hive, the libmpv-backed player, the two dev servers) is real,
/// following the same philosophy as desktop_smoke_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userA = 'alice';
  const passA = 'alpha-secret';
  const userB = 'bob';
  const passB = 'beta-secret';
  const mp3Name = 'track.mp3';
  const binName = 'notes.bin';

  late Directory rootA;
  late Directory rootB;
  late HttpServer serverA;
  late HttpServer serverB;
  late bool ffmpegAvailable;
  late int mp3Size;

  setUp(() async {
    rootA = await Directory.systemTemp.createTemp('retrobeat_dav_a_');
    rootB = await Directory.systemTemp.createTemp('retrobeat_dav_b_');
    Directory('${rootB.path}/Incoming').createSync();

    ffmpegAvailable = await _generateMp3(rootA, mp3Name);
    if (ffmpegAvailable) {
      mp3Size = File('${rootA.path}/$mp3Name').lengthSync();
    }
    // A non-audio file alongside it: the browser must list it without
    // offering to play it, and the transfer path must not be mp3-specific.
    File('${rootA.path}/$binName')
        .writeAsBytesSync(List<int>.generate(2048, (i) => i % 256));

    serverA = await startDevWebDavServer(
      root: rootA.path,
      username: userA,
      password: passA,
    );
    serverB = await startDevWebDavServer(
      root: rootB.path,
      username: userB,
      password: passB,
    );
  });

  tearDown(() async {
    app.debugProviderOverrides = [];
    await serverA.close(force: true);
    await serverB.close(force: true);
    if (rootA.existsSync()) await rootA.delete(recursive: true);
    if (rootB.existsSync()) await rootB.delete(recursive: true);
  });

  testWidgets(
    'add two servers, play a remote track, then move it between them',
    (tester) async {
      if (!ffmpegAvailable) {
        markTestSkipped('ffmpeg is not on PATH; nothing to play.');
        return;
      }

      app.debugProviderOverrides = [
        credentialVaultProvider
            .overrideWithValue(CredentialVault(FakeSecretStore())),
      ];

      // Runs the exact entrypoint a real launch uses — Hive, the libmpv
      // backend, window_manager, RetroBeatAudioHandler, this feature's own
      // bootstrapServers call — rather than reconstructing a lookalike
      // widget tree by hand.
      app.main();
      await _pumpUntilFound(tester, find.byType(MaterialApp));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );

      // A clean slate regardless of what a previous run of this same test
      // left behind: Hive's servers box lives in a real per-user directory
      // on this machine, not a throwaway sandbox, so it persists across runs.
      for (final config in List.of(container.read(serverListProvider))) {
        await container.read(serverListProvider.notifier).remove(config.id);
      }

      // ---- Open the Servers area from the Home screen ----
      await _pumpUntilFound(tester, find.byTooltip('Servers'));
      await tester.tap(find.byTooltip('Servers'));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('serversScreen_addFab')),
      );

      // ---- Add server A through the real form: Test connection -> Save ----
      await tester.tap(find.byKey(const Key('serversScreen_addFab')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('serverForm_baseUrl')),
      );
      await _addServerThroughForm(
        tester,
        name: 'Server A',
        baseUrl: 'http://127.0.0.1:${serverA.port}',
        username: userA,
        password: passA,
      );
      // Waiting on the Add FAB rather than find.text('Server A') here: the
      // form's own Name field still holds that exact string for a moment
      // during the pop transition, and find.text also matches an
      // EditableText whose controller has that value — a false positive
      // that would fire before the form has actually closed.
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('serversScreen_addFab')),
      );
      // Scoped to a ListTile rather than a bare find.text: the closing
      // form's Name field can still be mid-transition and carries the same
      // text, but it is not inside any ListTile.
      expect(find.widgetWithText(ListTile, 'Server A'), findsOneWidget);

      // ---- Add server B the same way ----
      await tester.tap(find.byKey(const Key('serversScreen_addFab')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('serverForm_baseUrl')),
      );
      await _addServerThroughForm(
        tester,
        name: 'Server B',
        baseUrl: 'http://127.0.0.1:${serverB.port}',
        username: userB,
        password: passB,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('serversScreen_addFab')),
      );
      expect(find.widgetWithText(ListTile, 'Server B'), findsOneWidget);

      // ---- Connect B without leaving the Servers screen ----
      await _tapOverflowAction(tester, tileText: 'Server B', action: 'Connect');
      await _pumpUntilFound(tester, find.textContaining('Connected'));

      // ---- Tap Server A: connects it (A was not autoConnect-bootstrapped,
      // since it did not exist yet at startup) and opens its browser ----
      await tester.tap(
        find
            .ancestor(
              of: find.text('Server A'),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await _pumpUntilFound(tester, find.text(mp3Name));
      expect(
        find.text(binName),
        findsOneWidget,
        reason: 'the non-audio fixture file must still be listed',
      );

      // ---- Play the mp3: queue = audio files in this folder ----
      await tester.tap(find.text(mp3Name));
      final handler = container.read(audioHandlerProvider);
      final position = await _waitForPositionPast(
        tester,
        handler,
        const Duration(seconds: 1),
      );
      expect(
        position,
        greaterThan(const Duration(seconds: 1)),
        reason: 'playback position never advanced past 1s. If the '
            'Authorization header is not reaching mpv through '
            'just_audio_media_kit, that is a pipeline limitation to report '
            'prominently, not a bug to paper over.',
      );

      // ---- Move the mp3 to server B's Incoming folder ----
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(
                of: find.text(mp3Name),
                matching: find.byType(ListTile),
              )
              .first,
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      await _pumpUntilFound(tester, find.text('Move to…'));
      await tester.tap(find.text('Move to…'));

      await _pumpUntilFound(tester, find.text('Choose a destination'));
      // Scoped to the sheet itself: the browser screen it covers has its own
      // server-switcher chip, and it stays mounted (and findable) underneath
      // a modal bottom sheet, so a bare find.text('Server B') matches both.
      final sheet = find.byKey(const Key('destinationPicker'));
      await tester
          .tap(find.descendant(of: sheet, matching: find.text('Server B')));
      await _pumpUntilFound(
        tester,
        find.descendant(of: sheet, matching: find.text('Incoming')),
      );
      await tester
          .tap(find.descendant(of: sheet, matching: find.text('Incoming')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('destinationPicker_choose')),
      );
      await tester.tap(find.byKey(const Key('destinationPicker_choose')));

      // ---- Follow it into the Transfers panel and wait for completion ----
      await _pumpUntilFound(tester, find.text('View'));
      await tester.tap(find.text('View'));
      await _pumpUntilFound(tester, find.textContaining('Done'));

      // ---- Verify on the wire, independent of the UI's own belief ----
      final checkA = WebDavClient(
        baseUrl: Uri.parse('http://127.0.0.1:${serverA.port}'),
        username: userA,
        secret: () async => passA,
      );
      final checkB = WebDavClient(
        baseUrl: Uri.parse('http://127.0.0.1:${serverB.port}'),
        username: userB,
        secret: () async => passB,
      );
      try {
        expect(
          await checkA.exists('/$mp3Name'),
          isFalse,
          reason: 'a move must remove the source',
        );
        final landed = await checkB.stat('/Incoming/$mp3Name');
        expect(landed, isNotNull, reason: 'the file must exist on B');
        expect(
          landed!.size,
          mp3Size,
          reason: 'the moved copy must match in size',
        );
      } finally {
        checkA.close();
        checkB.close();
      }
    },
  );
}

/// Fills in and saves the Add-server form: Test connection first (asserting
/// it succeeds), then Save — the same order a real user follows.
Future<void> _addServerThroughForm(
  WidgetTester tester, {
  required String name,
  required String baseUrl,
  required String username,
  required String password,
}) async {
  await tester.enterText(find.byKey(const Key('serverForm_name')), name);
  await tester.pump();
  await tester.enterText(find.byKey(const Key('serverForm_baseUrl')), baseUrl);
  await tester.pump();
  await tester.enterText(
    find.byKey(const Key('serverForm_username')),
    username,
  );
  await tester.pump();
  await tester.enterText(
    find.byKey(const Key('serverForm_password')),
    password,
  );
  await tester.pump();

  await tester.ensureVisible(
    find.byKey(const Key('serverForm_testConnection')),
  );
  await tester.tap(find.byKey(const Key('serverForm_testConnection')));
  await _pumpUntilFound(tester, find.text('Connected successfully.'));

  await tester.ensureVisible(find.byKey(const Key('serverForm_save')));
  await tester.tap(find.byKey(const Key('serverForm_save')));
}

/// Opens the overflow menu on the server tile titled [tileText] and taps the
/// menu item labelled [action].
Future<void> _tapOverflowAction(
  WidgetTester tester, {
  required String tileText,
  required String action,
}) async {
  final tile = find
      .ancestor(of: find.text(tileText), matching: find.byType(ListTile))
      .first;
  final menuButton =
      find.descendant(of: tile, matching: find.byIcon(Icons.more_vert_rounded));
  await tester.ensureVisible(menuButton);
  await tester.tap(menuButton);
  await _pumpUntilFound(tester, find.text(action));
  await tester.tap(find.text(action));
}

/// A real, ffmpeg-generated mp3 — 35 seconds, long enough for the position
/// assertion to have room to run. Mirrors desktop_smoke_test.dart's fixture
/// generation; returns false (never throws) if ffmpeg is not on PATH, which
/// the test turns into a skip rather than a failure.
Future<bool> _generateMp3(Directory dir, String filename) async {
  try {
    final result = await Process.run('ffmpeg', [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:duration=35',
      '-metadata',
      'title=Server Flow Test Track',
      '${dir.path}/$filename',
    ]);
    return result.exitCode == 0;
  } on ProcessException {
    return false; // ffmpeg is not installed on this machine.
  }
}

/// Pumps in bounded steps rather than `pumpAndSettle` — a popup menu
/// transition, an indeterminate progress bar or the splash screen's spinner
/// can all be mid-animation at any point in this flow, and any of them would
/// make `pumpAndSettle` hang forever waiting for a frame that never stops
/// being scheduled on its own.
///
/// Once found, pumps a short, fixed settle on top: a route or sheet
/// transition can still be mid-flight for a few frames after the widget it
/// reveals first becomes findable, and tapping into that tail end can hit the
/// outgoing route's transition barrier instead of the widget underneath —
/// every call site here immediately interacts with whatever it just waited
/// for, so this is the one place to cover that rather than sprinkling
/// extra pumps after every wait.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 250),
  int maxTries = 240,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().isNotEmpty) {
      for (var settle = 0; settle < 4; settle++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return;
    }
    await tester.pump(step);
  }
  throw TestFailure('Timed out waiting to find $finder');
}

/// Polls the handler's own playback state rather than reading it once after a
/// fixed delay, so the assertion is not a guess about how long mpv takes to
/// open and start decoding a remote file on whatever machine is running this.
Future<Duration> _waitForPositionPast(
  WidgetTester tester,
  RetroBeatAudioHandler handler,
  Duration threshold, {
  Duration step = const Duration(milliseconds: 500),
  int maxTries = 60,
}) async {
  var last = Duration.zero;
  for (var i = 0; i < maxTries; i++) {
    last = handler.playbackState.valueOrNull?.updatePosition ?? Duration.zero;
    if (last > threshold) return last;
    await tester.pump(step);
  }
  return last;
}
