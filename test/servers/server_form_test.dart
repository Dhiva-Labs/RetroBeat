import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/providers/server_providers.dart';
import 'package:retro_beat/screens/servers/server_form_screen.dart';

/// Save short-circuits at `Form.validate()` before touching any provider that
/// would need Hive or a keychain, so a bare [ProviderScope] is enough here —
/// no server box, no vault override.
Future<void> _pumpForm(WidgetTester tester) {
  return tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: ServerFormScreen()),
    ),
  );
}

void main() {
  group('ServerFormScreen validation', () {
    testWidgets('a bad server address is rejected with the validator sentence',
        (tester) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.byKey(const Key('serverForm_baseUrl')),
        'nas.local',
      );
      await tester.enterText(
        find.byKey(const Key('serverForm_username')),
        'me',
      );
      await tester.enterText(
        find.byKey(const Key('serverForm_password')),
        'hunter2',
      );

      await tester.ensureVisible(find.byKey(const Key('serverForm_save')));
      await tester.tap(find.byKey(const Key('serverForm_save')));
      await tester.pump();

      // Whatever sentence the shared validator returns is what must appear —
      // this is the same rule ServerListNotifier.add enforces, so the form
      // and the notifier can never disagree about what counts as valid.
      final expected = ServerListNotifier.validateBaseUrl('nas.local');
      expect(expected, isNotNull);
      expect(find.text(expected!), findsOneWidget);
    });

    testWidgets('an empty server address is rejected too', (tester) async {
      await _pumpForm(tester);

      await tester.ensureVisible(find.byKey(const Key('serverForm_save')));
      await tester.tap(find.byKey(const Key('serverForm_save')));
      await tester.pump();

      final expected = ServerListNotifier.validateBaseUrl('');
      expect(find.text(expected!), findsOneWidget);
    });

    testWidgets('the password field is obscured by default', (tester) async {
      await _pumpForm(tester);

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('serverForm_password')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.obscureText, isTrue);
    });

    testWidgets('the reveal toggle un-obscures the password field',
        (tester) async {
      await _pumpForm(tester);

      await tester.tap(find.byIcon(Icons.visibility_rounded));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('serverForm_password')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.obscureText, isFalse);
    });

    testWidgets('adding requires a password, editing does not', (tester) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.byKey(const Key('serverForm_baseUrl')),
        'https://nas.local',
      );
      await tester.enterText(
        find.byKey(const Key('serverForm_username')),
        'me',
      );
      // Password left blank.

      await tester.ensureVisible(find.byKey(const Key('serverForm_save')));
      await tester.tap(find.byKey(const Key('serverForm_save')));
      await tester.pump();

      expect(find.text('Enter the password.'), findsOneWidget);
    });
  });
}
