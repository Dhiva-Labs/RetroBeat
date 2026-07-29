import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Where the app is running, so a platform branch is one call instead of a
/// repeated "check kIsWeb, then check Platform" dance scattered everywhere.
///
/// `dart:io`'s `Platform` getters are meant for native targets only, so every
/// check here tests [kIsWeb] first — a bare `Platform.isAndroid` anywhere else
/// in the app is a bug waiting for a web build.
class PlatformInfo {
  PlatformInfo._();

  static bool get isAndroid => !kIsWeb && io.Platform.isAndroid;
  static bool get isIOS => !kIsWeb && io.Platform.isIOS;
  static bool get isLinux => !kIsWeb && io.Platform.isLinux;
  static bool get isWindows => !kIsWeb && io.Platform.isWindows;
  static bool get isMacOS => !kIsWeb && io.Platform.isMacOS;

  /// Phone/tablet: touch UI, a MediaStore-backed library, permission prompts,
  /// a background playback service.
  static bool get isMobile => isAndroid || isIOS;

  /// Linux, Windows or macOS: pointer-and-keyboard UI, a library built from
  /// folders the user picks, a plain window instead of a foreground service.
  static bool get isDesktop => isLinux || isWindows || isMacOS;
}
