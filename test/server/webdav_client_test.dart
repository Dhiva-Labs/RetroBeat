import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/data/server/webdav_client.dart';

import 'dev_server_fixture.dart';

void main() {
  late DevServer server;
  late WebDavClient client;

  WebDavClient clientWith(String? password) => WebDavClient(
        baseUrl: server.baseUrl,
        username: server.username,
        secret: () async => password,
      );

  setUp(() async {
    server = await DevServer.start();
    client = clientWith(server.password);
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  group('url handling', () {
    test('encodes each path segment', () {
      expect(
        client.resolveUrl('/Music/Song #1 (100%).mp3').path,
        '/Music/Song%20%231%20(100%25).mp3',
      );
    });

    test('keeps a base path prefix', () {
      final nested = WebDavClient(
        baseUrl: Uri.parse('http://host/remote.php/dav/files/me'),
        username: 'me',
        secret: () async => 'x',
      );
      expect(
        nested.resolveUrl('/Music').toString(),
        'http://host/remote.php/dav/files/me/Music',
      );
      expect(nested.pathFromHref('/remote.php/dav/files/me/Music/'), '/Music');
      nested.close();
    });

    test('decodes an href back to a plain path', () {
      expect(
        client.pathFromHref('/Music/Bj%C3%B6rk%20-%20J%C3%B3ga.flac'),
        '/Music/Björk - Jóga.flac',
      );
    });
  });

  group('testConnection', () {
    test('succeeds against a reachable server', () async {
      await expectLater(client.testConnection(), completes);
    });

    test('a wrong password is an auth failure', () async {
      final wrong = clientWith('not-the-password');
      await expectLater(
        wrong.testConnection(),
        throwsA(isA<WebDavAuthException>()),
      );
      wrong.close();
    });

    test('no stored password is an auth failure, not a crash', () async {
      final empty = clientWith(null);
      await expectLater(
        empty.testConnection(),
        throwsA(isA<WebDavAuthException>()),
      );
      empty.close();
    });

    test('a missing root folder is a not-found failure', () async {
      await expectLater(
        client.testConnection(path: '/nope'),
        throwsA(isA<WebDavNotFoundException>()),
      );
    });
  });

  group('list', () {
    test('returns children and leaves out the folder itself', () async {
      server
        ..makeDir('Music')
        ..writeText('Music/one.mp3', 'aaa')
        ..writeText('Music/two.flac', 'bbbb')
        ..makeDir('Music/Live');

      final entries = await client.list('/Music');
      expect(entries.map((e) => e.path), isNot(contains('/Music')));
      expect(
        entries.map((e) => e.name).toList()..sort(),
        ['Live', 'one.mp3', 'two.flac'],
      );

      final live = entries.firstWhere((e) => e.name == 'Live');
      expect(live.isDir, isTrue);
      expect(live.path, '/Music/Live');

      final one = entries.firstWhere((e) => e.name == 'one.mp3');
      expect(one.isDir, isFalse);
      expect(one.size, 3);
      expect(one.contentType, 'audio/mpeg');
      expect(one.lastModified, isNotNull);
    });

    test('handles spaces, unicode and reserved characters in names', () async {
      const awkward = 'Björk — Jóga #1 (100%).mp3';
      server
        ..makeDir('Odd Folder')
        ..writeText('Odd Folder/$awkward', 'unicode payload');

      final entries = await client.list('/Odd Folder');
      expect(entries.single.name, awkward);
      expect(entries.single.path, '/Odd Folder/$awkward');

      final download = await client.download(entries.single.path);
      expect(await _collect(download.stream), utf8.encode('unicode payload'));
    });

    test('a missing folder is a not-found failure', () async {
      await expectLater(
        client.list('/absent'),
        throwsA(isA<WebDavNotFoundException>()),
      );
    });

    test('a wrong password is an auth failure', () async {
      server.makeDir('Music');
      final wrong = clientWith('nope');
      await expectLater(
        wrong.list('/Music'),
        throwsA(isA<WebDavAuthException>()),
      );
      wrong.close();
    });
  });

  group('stat and exists', () {
    test('reports a file, a folder, and an absence', () async {
      server
        ..makeDir('Music')
        ..writeText('Music/one.mp3', 'aaa');

      final file = await client.stat('/Music/one.mp3');
      expect(file, isNotNull);
      expect(file!.isDir, isFalse);
      expect(file.size, 3);

      final dir = await client.stat('/Music');
      expect(dir!.isDir, isTrue);

      expect(await client.stat('/Music/absent.mp3'), isNull);
      expect(await client.exists('/Music/one.mp3'), isTrue);
      expect(await client.exists('/Music/absent.mp3'), isFalse);
    });
  });

  group('download', () {
    test('streams the body with its length', () async {
      final payload = Uint8List.fromList(
        List<int>.generate(200000, (i) => i % 251),
      );
      server.writeBytes('big.bin', payload);

      final download = await client.download('/big.bin');
      expect(download.contentLength, payload.length);
      expect(download.isPartial, isFalse);
      expect(await _collect(download.stream), payload);
    });

    test('honours a byte range, which is what seeking needs', () async {
      final payload = Uint8List.fromList(
        List<int>.generate(5000, (i) => i % 251),
      );
      server.writeBytes('big.bin', payload);

      final slice = await client.download(
        '/big.bin',
        rangeStart: 1000,
        rangeEnd: 1099,
      );
      expect(slice.isPartial, isTrue);
      expect(slice.contentLength, 100);
      expect(await _collect(slice.stream), payload.sublist(1000, 1100));

      final tail = await client.download('/big.bin', rangeStart: 4900);
      expect(tail.isPartial, isTrue);
      expect(await _collect(tail.stream), payload.sublist(4900));
    });

    test('a missing file is a not-found failure', () async {
      await expectLater(
        client.download('/absent.mp3'),
        throwsA(isA<WebDavNotFoundException>()),
      );
    });
  });

  group('upload', () {
    test('writes a streamed body', () async {
      final chunks = [
        utf8.encode('first '),
        utf8.encode('second '),
        utf8.encode('third'),
      ];
      final length = chunks.fold<int>(0, (sum, c) => sum + c.length);

      await client.upload('/notes.txt', Stream.fromIterable(chunks), length);

      expect(server.readText('notes.txt'), 'first second third');
    });

    test('replaces an existing file by default', () async {
      server.writeText('notes.txt', 'old');
      await client.upload(
        '/notes.txt',
        Stream.value(utf8.encode('new')),
        3,
      );
      expect(server.readText('notes.txt'), 'new');
    });

    test('refuses to replace one when overwrite is off', () async {
      server.writeText('notes.txt', 'old');
      await expectLater(
        client.upload(
          '/notes.txt',
          Stream.value(utf8.encode('new')),
          3,
          overwrite: false,
        ),
        throwsA(isA<WebDavConflictException>()),
      );
      expect(server.readText('notes.txt'), 'old');
    });

    test('a missing parent folder is a conflict', () async {
      await expectLater(
        client.upload('/nope/notes.txt', Stream.value(const [1]), 1),
        throwsA(isA<WebDavConflictException>()),
      );
    });
  });

  group('delete, mkcol and move', () {
    test('delete removes a file', () async {
      server.writeText('gone.txt', 'x');
      await client.delete('/gone.txt');
      expect(server.has('gone.txt'), isFalse);
    });

    test('deleting something absent is a not-found failure', () async {
      await expectLater(
        client.delete('/absent.txt'),
        throwsA(isA<WebDavNotFoundException>()),
      );
    });

    test('mkcol creates a folder and refuses to recreate it', () async {
      await client.mkcol('/New Folder');
      expect(server.dirAt('New Folder').existsSync(), isTrue);
      await expectLater(
        client.mkcol('/New Folder'),
        throwsA(isA<WebDavConflictException>()),
      );
    });

    test('move renames within the server', () async {
      server
        ..makeDir('Music')
        ..writeText('Music/one.mp3', 'payload')
        ..makeDir('Archive');

      await client.moveSameServer('/Music/one.mp3', '/Archive/one.mp3');

      expect(server.has('Music/one.mp3'), isFalse);
      expect(server.readText('Archive/one.mp3'), 'payload');
    });

    test('move onto an existing name fails unless overwrite is asked for',
        () async {
      server
        ..writeText('a.txt', 'source')
        ..writeText('b.txt', 'target');

      await expectLater(
        client.moveSameServer('/a.txt', '/b.txt'),
        throwsA(isA<WebDavConflictException>()),
      );
      expect(server.readText('a.txt'), 'source');
      expect(server.readText('b.txt'), 'target');

      await client.moveSameServer('/a.txt', '/b.txt', overwrite: true);
      expect(server.has('a.txt'), isFalse);
      expect(server.readText('b.txt'), 'source');
    });
  });

  group('streamSpec', () {
    test('puts the credential in a header and never in the URL', () async {
      server.writeText('one.mp3', 'x');
      final spec = await client.streamSpec('/one.mp3');

      expect(spec.url.toString(), '${server.baseUrl}/one.mp3');
      expect(spec.url.userInfo, isEmpty);
      expect(spec.headers['authorization'], basicHeaderFor(server));
      expect(spec.toString(), isNot(contains(server.password)));
    });
  });
}

Future<List<int>> _collect(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return bytes;
}
