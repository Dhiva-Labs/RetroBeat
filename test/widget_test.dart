import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/core/widgets/empty_state.dart';

/// A plain widget test, deliberately kept clear of app bootstrap (Hive,
/// audio_service, window_manager) — that full startup path is only exercised
/// for real by `integration_test/desktop_smoke_test.dart`, which runs against
/// an actual platform instead of the simulated one `flutter test` uses.
void main() {
  testWidgets('EmptyState shows its message and falls back to an icon',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.music_off_rounded,
            message: 'No music found on your device.',
          ),
        ),
      ),
    );

    expect(find.text('No music found on your device.'), findsOneWidget);
    expect(find.byIcon(Icons.music_off_rounded), findsOneWidget);
  });

  testWidgets('EmptyState renders an action when one is supplied',
      (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.create_new_folder_outlined,
            message: 'No music yet.\nAdd a folder to build your library.',
            action: FilledButton(
              onPressed: () => tapped = true,
              child: const Text('Add folder'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add folder'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
