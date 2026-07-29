import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'dev_server_fixture.dart';

/// The dev server is test infrastructure, so it gets its own tests: a bug in
/// it would show up as a bug in the client, in the wrong file.
void main() {
  late DevServer server;
  late http.Client client;
  late Map<String, String> auth;

  Uri url(String path) => Uri.parse('${server.baseUrl}$path');

  Future<http.Response> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, url(path))..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    return http.Response.fromStream(await client.send(request));
  }

  setUp(() async {
    server = await DevServer.start();
    client = http.Client();
    auth = {'authorization': basicHeaderFor(server)};
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  test('every verb needs credentials', () async {
    server.writeText('one.txt', 'x');
    for (final method in [
      'OPTIONS',
      'HEAD',
      'GET',
      'PROPFIND',
      'PUT',
      'DELETE',
      'MKCOL',
      'MOVE',
    ]) {
      final response = await send(method, '/one.txt');
      expect(response.statusCode, 401, reason: method);
      expect(response.headers['www-authenticate'], contains('Basic'));
    }
    expect(server.readText('one.txt'), 'x');
  });

  test('a wrong password is refused', () async {
    final response = await send(
      'OPTIONS',
      '/',
      headers: {'authorization': 'Basic ${base64Encode(utf8.encode('a:b'))}'},
    );
    expect(response.statusCode, 401);
  });

  test('OPTIONS advertises WebDAV', () async {
    final response = await send('OPTIONS', '/', headers: auth);
    expect(response.statusCode, 200);
    expect(response.headers['dav'], contains('1'));
    expect(response.headers['allow'], contains('PROPFIND'));
  });

  test('HEAD reports the size without sending the file', () async {
    server.writeText('one.txt', 'twelve chars');
    final response = await send('HEAD', '/one.txt', headers: auth);

    expect(response.statusCode, 200);
    expect(response.headers['content-length'], '12');
    expect(response.headers['accept-ranges'], 'bytes');
    expect(response.bodyBytes, isEmpty);
  });

  test('GET honours a range, which is how mpv seeks', () async {
    server.writeText('one.txt', '0123456789');

    final middle = await send(
      'GET',
      '/one.txt',
      headers: {...auth, 'range': 'bytes=2-5'},
    );
    expect(middle.statusCode, 206);
    expect(middle.body, '2345');
    expect(middle.headers['content-range'], 'bytes 2-5/10');

    final open = await send(
      'GET',
      '/one.txt',
      headers: {...auth, 'range': 'bytes=7-'},
    );
    expect(open.statusCode, 206);
    expect(open.body, '789');

    final suffix = await send(
      'GET',
      '/one.txt',
      headers: {...auth, 'range': 'bytes=-3'},
    );
    expect(suffix.statusCode, 206);
    expect(suffix.body, '789');

    final beyond = await send(
      'GET',
      '/one.txt',
      headers: {...auth, 'range': 'bytes=99-200'},
    );
    expect(beyond.statusCode, 416);
    expect(beyond.headers['content-range'], 'bytes */10');
  });

  test('PROPFIND depth 0 describes only the folder itself', () async {
    server
      ..makeDir('Music')
      ..writeText('Music/one.mp3', 'x');

    final zero = await send(
      'PROPFIND',
      '/Music',
      headers: {...auth, 'depth': '0'},
    );
    expect(zero.statusCode, 207);
    expect('<D:href>'.allMatches(zero.body).length, 1);

    final one = await send(
      'PROPFIND',
      '/Music',
      headers: {...auth, 'depth': '1'},
    );
    expect(one.statusCode, 207);
    expect('<D:href>'.allMatches(one.body).length, 2);
    expect(one.body, contains('one.mp3'));
  });

  test('PROPFIND on something absent is a 404', () async {
    final response = await send(
      'PROPFIND',
      '/absent',
      headers: {...auth, 'depth': '1'},
    );
    expect(response.statusCode, 404);
  });

  test('a path that climbs out of the root never reads the file', () async {
    File('${server.root.parent.path}/escape.txt').writeAsStringSync('secret');
    addTearDown(() {
      final leak = File('${server.root.parent.path}/escape.txt');
      if (leak.existsSync()) leak.deleteSync();
    });

    // Written to the socket by hand: Uri normalises `..` away long before a
    // request built through package:http would leave the machine.
    final socket = await Socket.connect('127.0.0.1', server.baseUrl.port);
    socket.write(
      'GET /../escape.txt HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\n'
      'authorization: ${basicHeaderFor(server)}\r\n'
      'connection: close\r\n\r\n',
    );
    final reply = await utf8.decoder.bind(socket).join();

    expect(reply, isNot(contains('secret')));
  });

  test('MOVE refuses a destination on another host', () async {
    server.writeText('one.txt', 'x');
    final response = await send(
      'MOVE',
      '/one.txt',
      headers: {...auth, 'destination': 'http://elsewhere.invalid/two.txt'},
    );

    expect(response.statusCode, 502);
    expect(server.has('one.txt'), isTrue);
    expect(server.has('two.txt'), isFalse);
  });

  test('MOVE with a same-host destination works', () async {
    server.writeText('one.txt', 'payload');
    final response = await send(
      'MOVE',
      '/one.txt',
      headers: {...auth, 'destination': '${server.baseUrl}/two.txt'},
    );

    expect(response.statusCode, 201);
    expect(server.has('one.txt'), isFalse);
    expect(server.readText('two.txt'), 'payload');
  });
}
