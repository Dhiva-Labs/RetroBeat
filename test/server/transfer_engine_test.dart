import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/data/server/transfer_engine.dart';
import 'package:retro_beat/data/server/webdav_client.dart';

import 'dev_server_fixture.dart';

void main() {
  late DevServer alpha;
  late DevServer beta;
  late WebDavClient clientAlpha;
  late WebDavClient clientBeta;
  late RecordingClient httpAlpha;
  late RecordingClient httpBeta;
  late List<String> trace;
  late TransferEngine engine;

  setUp(() async {
    alpha = await DevServer.start();
    beta = await DevServer.start();
    trace = [];
    httpAlpha = RecordingClient(label: 'A', log: trace);
    httpBeta = RecordingClient(label: 'B', log: trace);
    clientAlpha = WebDavClient(
      baseUrl: alpha.baseUrl,
      username: alpha.username,
      secret: () async => alpha.password,
      httpClient: httpAlpha,
    );
    clientBeta = WebDavClient(
      baseUrl: beta.baseUrl,
      username: beta.username,
      secret: () async => beta.password,
      httpClient: httpBeta,
    );
    engine = TransferEngine(
      clients: (id) => switch (id) {
        'alpha' => clientAlpha,
        'beta' => clientBeta,
        _ => null,
      },
    );
  });

  tearDown(() async {
    engine.dispose();
    clientAlpha.close();
    clientBeta.close();
    httpAlpha.close();
    httpBeta.close();
    await alpha.stop();
    await beta.stop();
  });

  TransferJob jobOf(String id) => engine.jobById(id)!;

  test('copies a file to another server and leaves the source', () async {
    alpha.writeText('song.mp3', 'the payload');

    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/song.mp3',
      dstServerId: 'beta',
      dstDir: '/',
    );
    await engine.whenIdle();

    expect(jobOf(id).status, TransferStatus.completed);
    expect(jobOf(id).error, isNull);
    expect(beta.readText('song.mp3'), 'the payload');
    expect(alpha.has('song.mp3'), isTrue);
    expect(jobOf(id).transferredBytes, jobOf(id).totalBytes);
  });

  test('copies into a subfolder, keeping the file name', () async {
    alpha.writeText('song.mp3', 'x');
    beta.makeDir('Inbox');

    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/song.mp3',
      dstServerId: 'beta',
      dstDir: '/Inbox',
    );
    await engine.whenIdle();

    expect(jobOf(id).status, TransferStatus.completed);
    expect(jobOf(id).dstPath, '/Inbox/song.mp3');
    expect(beta.has('Inbox/song.mp3'), isTrue);
  });

  test('a move deletes the source only after the upload is verified', () async {
    alpha.writeText('song.mp3', 'the payload');

    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/song.mp3',
      dstServerId: 'beta',
      dstDir: '/',
      mode: TransferMode.move,
    );
    await engine.whenIdle();

    expect(jobOf(id).status, TransferStatus.completed);
    expect(beta.readText('song.mp3'), 'the payload');
    expect(alpha.has('song.mp3'), isFalse);

    final put = trace.indexWhere((e) => e.startsWith('B PUT'));
    final verify = trace.lastIndexWhere((e) => e.startsWith('B PROPFIND'));
    final delete = trace.indexWhere((e) => e.startsWith('A DELETE'));
    expect(put, isNonNegative);
    expect(verify, greaterThan(put), reason: 'destination read back after PUT');
    expect(delete, greaterThan(verify), reason: 'source deleted last');
  });

  test('a name collision fails the job and touches nothing', () async {
    alpha.writeText('song.mp3', 'incoming');
    beta.writeText('song.mp3', 'already here');

    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/song.mp3',
      dstServerId: 'beta',
      dstDir: '/',
      mode: TransferMode.move,
    );
    await engine.whenIdle();

    expect(jobOf(id).status, TransferStatus.failed);
    expect(jobOf(id).failure, TransferFailure.collision);
    expect(jobOf(id).error, contains('already exists'));
    expect(beta.readText('song.mp3'), 'already here');
    expect(alpha.readText('song.mp3'), 'incoming');
  });

  test('overwrite replaces the destination', () async {
    alpha.writeText('song.mp3', 'incoming');
    beta.writeText('song.mp3', 'already here');

    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/song.mp3',
      dstServerId: 'beta',
      dstDir: '/',
      overwrite: true,
    );
    await engine.whenIdle();

    expect(jobOf(id).status, TransferStatus.completed);
    expect(beta.readText('song.mp3'), 'incoming');
  });

  test('cancelling mid-transfer leaves the source alone', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(6 * 1024 * 1024, (i) => i % 251),
    );
    alpha.writeBytes('big.bin', payload);

    final remove = engine.addListener(
      (jobs) {
        for (final job in jobs) {
          if (job.status == TransferStatus.running &&
              job.transferredBytes > 0 &&
              job.transferredBytes < (job.totalBytes ?? 0)) {
            engine.cancel(job.id);
          }
        }
      },
      fireImmediately: false,
    );

    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/big.bin',
      dstServerId: 'beta',
      dstDir: '/',
      mode: TransferMode.move,
    );
    await engine.whenIdle();
    remove();

    expect(jobOf(id).status, TransferStatus.cancelled);
    expect(
      alpha.fileAt('big.bin').lengthSync(),
      payload.length,
      reason: 'a cancelled move must never delete the source',
    );
    // The engine removes the part-written destination; the assertion allows
    // for the server closing its own handle a moment later, but never for a
    // complete copy being left behind.
    final leftover =
        beta.has('big.bin') ? beta.fileAt('big.bin').lengthSync() : 0;
    expect(leftover, lessThan(payload.length));
  });

  test('cancelling a queued job never starts it', () async {
    alpha
      ..writeText('a.mp3', 'a')
      ..writeText('b.mp3', 'b')
      ..writeText('c.mp3', 'c');

    final ids = [
      for (final name in ['a', 'b', 'c'])
        engine.enqueue(
          srcServerId: 'alpha',
          srcPath: '/$name.mp3',
          dstServerId: 'beta',
          dstDir: '/',
        ),
    ];
    engine.cancel(ids.last);
    await engine.whenIdle();

    expect(jobOf(ids.last).status, TransferStatus.cancelled);
    expect(beta.has('c.mp3'), isFalse);
    expect(beta.has('a.mp3'), isTrue);
  });

  test('progress only goes up and ends at the total', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(2 * 1024 * 1024, (i) => i % 251),
    );
    alpha.writeBytes('big.bin', payload);

    final seen = <int>[];
    final remove = engine.addListener(
      (jobs) {
        for (final job in jobs) {
          seen.add(job.transferredBytes);
        }
      },
      fireImmediately: false,
    );

    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/big.bin',
      dstServerId: 'beta',
      dstDir: '/',
    );
    await engine.whenIdle();
    remove();

    expect(jobOf(id).status, TransferStatus.completed);
    expect(jobOf(id).totalBytes, payload.length);
    expect(jobOf(id).transferredBytes, payload.length);
    expect(jobOf(id).progress, 1.0);
    expect(
      seen.length,
      greaterThan(2),
      reason: 'progress ticked while running',
    );
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
  });

  test('a move within one server uses MOVE, not a round trip', () async {
    alpha
      ..writeText('song.mp3', 'payload')
      ..makeDir('Archive');

    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/song.mp3',
      dstServerId: 'alpha',
      dstDir: '/Archive',
      mode: TransferMode.move,
    );
    await engine.whenIdle();

    expect(jobOf(id).status, TransferStatus.completed);
    expect(alpha.readText('Archive/song.mp3'), 'payload');
    expect(alpha.has('song.mp3'), isFalse);
    expect(httpAlpha.methods, contains('MOVE'));
    expect(
      httpAlpha.methods,
      isNot(contains('GET')),
      reason: 'the bytes must never leave the server',
    );
  });

  test('runs at most two at a time, in the order they were queued', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(512 * 1024, (i) => i % 251),
    );
    for (final name in ['one', 'two', 'three', 'four']) {
      alpha.writeBytes('$name.bin', payload);
    }

    final started = <String>[];
    var maxRunning = 0;
    final remove = engine.addListener(
      (jobs) {
        final running =
            jobs.where((j) => j.status == TransferStatus.running).toList();
        if (running.length > maxRunning) maxRunning = running.length;
        for (final job in running) {
          if (!started.contains(job.id)) started.add(job.id);
        }
      },
      fireImmediately: false,
    );

    final ids = [
      for (final name in ['one', 'two', 'three', 'four'])
        engine.enqueue(
          srcServerId: 'alpha',
          srcPath: '/$name.bin',
          dstServerId: 'beta',
          dstDir: '/',
        ),
    ];
    await engine.whenIdle();
    remove();

    expect(maxRunning, lessThanOrEqualTo(2));
    expect(started, ids, reason: 'FIFO');
    for (final id in ids) {
      expect(jobOf(id).status, TransferStatus.completed);
    }
  });

  test('a disconnected server fails the job without touching anything',
      () async {
    alpha.writeText('song.mp3', 'payload');

    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/song.mp3',
      dstServerId: 'gamma',
      dstDir: '/',
      mode: TransferMode.move,
    );
    await engine.whenIdle();

    expect(jobOf(id).status, TransferStatus.failed);
    expect(jobOf(id).failure, TransferFailure.notConnected);
    expect(alpha.has('song.mp3'), isTrue);
  });

  test('a source that vanished fails rather than half-transferring', () async {
    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/ghost.mp3',
      dstServerId: 'beta',
      dstDir: '/',
    );
    await engine.whenIdle();

    expect(jobOf(id).status, TransferStatus.failed);
    expect(jobOf(id).failure, TransferFailure.notFound);
  });

  test('clearFinished keeps only live jobs', () async {
    alpha.writeText('song.mp3', 'x');
    final id = engine.enqueue(
      srcServerId: 'alpha',
      srcPath: '/song.mp3',
      dstServerId: 'beta',
      dstDir: '/',
    );
    await engine.whenIdle();

    expect(engine.jobs, hasLength(1));
    engine.clearFinished();
    expect(engine.jobs, isEmpty);
    expect(engine.jobById(id), isNull);
  });
}
