import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/constants/app_constants.dart';
import 'core/utils/platform_info.dart';
import 'data/services/storage_service.dart';
import 'data/services/audio_handler.dart';
import 'providers/audio_provider.dart';
import 'app.dart';

late RetroBeatAudioHandler _audioHandler;

/// Provider overrides applied on top of the ones below. Empty in a real run;
/// an integration test sets this before calling [main] so it can swap in a
/// fake keychain (or any other fake) without touching a real one or popping
/// an unlock dialog — `main()` itself takes no arguments, since it doubles as
/// the platform entrypoint, so this is the only hook available for that.
@visibleForTesting
List<Override> debugProviderOverrides = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // The overlay style follows the theme, so it is set in RetroBeatApp rather
    // than pinned to dark here.

    if (PlatformInfo.isMobile) {
      // Desktop windows are resizable and have no "orientation" of their own —
      // the phone layout just stretches into whatever size the window is.
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }

    // Initialize Hive storage
    await StorageService.init();

    if (PlatformInfo.isLinux || PlatformInfo.isWindows) {
      // just_audio has no backend of its own on Linux/Windows; this installs
      // the libmpv-backed one before any AudioPlayer is created. Must run
      // before RetroBeatAudioHandler below, whose player is built the moment
      // the handler is constructed. macOS instead uses just_audio's native
      // Darwin implementation, so it is left out here.
      JustAudioMediaKit.ensureInitialized();
    }

    if (PlatformInfo.isDesktop) {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: Size(1280, 840),
          minimumSize: Size(400, 640),
          center: true,
          title: AppConstants.appName,
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
    }

    if (PlatformInfo.isMobile) {
      // audio_service puts playback in a foreground service so it survives
      // backgrounding and drives the lockscreen/headset controls. Desktop has
      // no equivalent service model to join, and RetroBeatAudioHandler needs
      // none of it — it is a plain BaseAudioHandler whose streams work
      // standalone — so it is constructed directly instead.
      _audioHandler = await AudioService.init(
        builder: () => RetroBeatAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.retrobeat.player.audio',
          androidNotificationChannelName: 'RetroBeat Audio',
          androidNotificationOngoing: true,
        ),
      );
    } else {
      _audioHandler = RetroBeatAudioHandler();
    }

    runApp(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(_audioHandler),
          ...debugProviderOverrides,
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
