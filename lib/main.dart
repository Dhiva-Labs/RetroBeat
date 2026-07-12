import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'data/services/storage_service.dart';
import 'data/services/audio_handler.dart';
import 'providers/audio_provider.dart';
import 'app.dart';

late RetroBeatAudioHandler _audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // The overlay style follows the theme, so it is set in RetroBeatApp rather
    // than pinned to dark here.

    // Set preferred orientations
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Initialize Hive storage
    await StorageService.init();

    // Initialize audio service
    _audioHandler = await AudioService.init(
      builder: () => RetroBeatAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.retrobeat.player.audio',
        androidNotificationChannelName: 'RetroBeat Audio',
        androidNotificationOngoing: true,
      ),
    );

    runApp(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(_audioHandler),
        ],
        child: const RetroBeatApp(),
      ),
    );
  } catch (e, stack) {
    debugPrint('FAILED TO INITIALIZE APP: $e');
    debugPrint(stack.toString());
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to start RetroBeat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
