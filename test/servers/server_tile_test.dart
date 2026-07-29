import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/providers/server_providers.dart';
import 'package:retro_beat/screens/servers/widgets/server_tile.dart';

/// A [WebDavClient] that is never actually used to talk to anything — just a
/// non-null value for [ServerSession.connecting]/[ServerSession.connected],
/// which require one.
WebDavClient _inertClient() {
  return WebDavClient(
    baseUrl: Uri.parse('http://example.invalid'),
    username: 'someone',
    secret: () async => null,
  );
}

ServerConfigModel _config({
  String name = 'NAS',
  String baseUrl = 'https://nas.local',
  bool autoConnect = false,
}) {
  return ServerConfigModel(
    id: 'server-1',
    name: name,
    baseUrl: baseUrl,
    username: 'me',
    autoConnect: autoConnect,
  );
}

Future<void> _pump(WidgetTester tester, Widget tile) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: tile)));
}

void main() {
  group('ServerTile status rendering', () {
    testWidgets('disconnected shows "Not connected" and no badges',
        (tester) async {
      final config = _config();
      await _pump(
        tester,
        ServerTile(
          config: config,
          session: ServerSession.disconnected(config),
          onTap: () {},
          onConnect: () {},
          onDisconnect: () {},
          onEdit: () {},
          onRemove: () {},
        ),
      );

      expect(find.textContaining('Not connected'), findsOneWidget);
      expect(find.text('Unencrypted'), findsNothing);
      expect(find.text('Auto'), findsNothing);
    });

    testWidgets('connecting shows a spinner and "Connecting…"', (tester) async {
      final config = _config();
      await _pump(
        tester,
        ServerTile(
          config: config,
          session: ServerSession.connecting(config, _inertClient()),
          onTap: () {},
          onConnect: () {},
          onDisconnect: () {},
          onEdit: () {},
          onRemove: () {},
        ),
      );

      expect(find.textContaining('Connecting…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('connected shows "Connected" and offers Disconnect',
        (tester) async {
      final config = _config();
      await _pump(
        tester,
        ServerTile(
          config: config,
          session: ServerSession.connected(config, _inertClient()),
          onTap: () {},
          onConnect: () {},
          onDisconnect: () {},
          onEdit: () {},
          onRemove: () {},
        ),
      );

      expect(find.textContaining('Connected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
    });

    testWidgets('error status shows the session message', (tester) async {
      final config = _config();
      await _pump(
        tester,
        ServerTile(
          config: config,
          session:
              ServerSession.failed(config, 'The server refused the password.'),
          onTap: () {},
          onConnect: () {},
          onDisconnect: () {},
          onEdit: () {},
          onRemove: () {},
        ),
      );

      expect(
        find.text('The server refused the password.'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('a plain-http server gets the unencrypted badge',
        (tester) async {
      final config = _config(baseUrl: 'http://nas.local');
      await _pump(
        tester,
        ServerTile(
          config: config,
          session: ServerSession.disconnected(config),
          onTap: () {},
          onConnect: () {},
          onDisconnect: () {},
          onEdit: () {},
          onRemove: () {},
        ),
      );

      expect(find.text('Unencrypted'), findsOneWidget);
    });

    testWidgets('an https server gets no unencrypted badge', (tester) async {
      final config = _config(baseUrl: 'https://nas.local');
      await _pump(
        tester,
        ServerTile(
          config: config,
          session: ServerSession.disconnected(config),
          onTap: () {},
          onConnect: () {},
          onDisconnect: () {},
          onEdit: () {},
          onRemove: () {},
        ),
      );

      expect(find.text('Unencrypted'), findsNothing);
    });

    testWidgets('autoConnect shows the Auto indicator', (tester) async {
      final config = _config(autoConnect: true);
      await _pump(
        tester,
        ServerTile(
          config: config,
          session: ServerSession.disconnected(config),
          onTap: () {},
          onConnect: () {},
          onDisconnect: () {},
          onEdit: () {},
          onRemove: () {},
        ),
      );

      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('tapping the tile calls onTap', (tester) async {
      final config = _config();
      var tapped = false;
      await _pump(
        tester,
        ServerTile(
          config: config,
          session: ServerSession.disconnected(config),
          onTap: () => tapped = true,
          onConnect: () {},
          onDisconnect: () {},
          onEdit: () {},
          onRemove: () {},
        ),
      );

      await tester.tap(find.byType(ListTile).first);
      expect(tapped, isTrue);
    });

    testWidgets('Edit and Remove are always offered', (tester) async {
      final config = _config();
      var edited = false;
      var removed = false;
      await _pump(
        tester,
        ServerTile(
          config: config,
          session: ServerSession.disconnected(config),
          onTap: () {},
          onConnect: () {},
          onDisconnect: () {},
          onEdit: () => edited = true,
          onRemove: () => removed = true,
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(edited, isTrue);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(removed, isTrue);
    });
  });
}
