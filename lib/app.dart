import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_beat/core/constants/app_constants.dart';
import 'package:retro_beat/core/theme/app_colors.dart';
import 'package:retro_beat/core/theme/app_theme.dart';
import 'package:retro_beat/core/utils/platform_info.dart';
import 'package:retro_beat/data/services/permission_service.dart';
import 'package:retro_beat/providers/audio_provider.dart';
import 'package:retro_beat/providers/server_providers.dart';
import 'package:retro_beat/providers/settings_provider.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/home/home_screen.dart';

class RetroBeatApp extends ConsumerStatefulWidget {
  const RetroBeatApp({super.key});

  @override
  ConsumerState<RetroBeatApp> createState() => _RetroBeatAppState();
}

class _RetroBeatAppState extends ConsumerState<RetroBeatApp>
    with WidgetsBindingObserver {
  bool _initialized = false;

  /// Debounces auto-rescan so a quick glance at the notification shade (which
  /// briefly pauses then resumes the app) does not trigger back-to-back scans.
  DateTime? _lastAutoRescan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeAutoRescan();
    }
  }

  Future<void> _initializeApp() async {
    // Requests access, then loads the library (or records why it could not).
    await ref.read(libraryLoaderProvider).load();

    // Fire-and-forget: an unreachable autoConnect server must not hold up the
    // splash screen, and connect() already turns every failure into a
    // per-server session state rather than an exception.
    unawaited(bootstrapServers(ref));

    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  Future<void> _maybeAutoRescan() async {
    if (!_initialized || !ref.read(autoRescanProvider)) return;

    // Never prompt on a resume — only rescan if access was already granted.
    if (ref.read(mediaPermissionProvider) != MediaPermissionStatus.granted) {
      return;
    }

    final now = DateTime.now();
    if (_lastAutoRescan != null &&
        now.difference(_lastAutoRescan!) < const Duration(seconds: 30)) {
      return;
    }
    _lastAutoRescan = now;

    await ref.read(libraryLoaderProvider).load(prompt: false);
  }

  @override
  Widget build(BuildContext context) {
    final isRetro = ref.watch(retroModeProvider);
    final isDarkMode = ref.watch(themeProvider);

    // Retro replaces light/dark rather than sitting on top of it, so there is
    // only ever one palette in play.
    final scheme = isRetro
        ? AppColors.retroScheme
        : (isDarkMode ? AppColors.darkScheme : AppColors.lightScheme);

    // The status/nav bar icons have to invert with the theme, or one of the
    // modes ends up with white icons on a white bar. Desktop has neither, so
    // there is nothing for this call to do there.
    if (PlatformInfo.isMobile) {
      SystemChrome.setSystemUIOverlayStyle(
        (scheme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: scheme.surface,
        ),
      );
    }

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // In retro mode both slots get the same theme, so the light/dark switch
      // simply has nothing to choose between.
      theme: isRetro ? AppTheme.retroTheme : AppTheme.lightTheme,
      darkTheme: isRetro ? AppTheme.retroTheme : AppTheme.darkTheme,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: _initialized ? const HomeScreen() : const SplashScreen(),
    );
  }
}
