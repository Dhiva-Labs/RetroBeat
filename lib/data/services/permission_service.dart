import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/platform_info.dart';

/// The outcome of asking for access to the user's audio library.
///
/// [permanentlyDenied] is distinct from [denied] because it cannot be recovered
/// by asking again — the user has to change it in system settings.
enum MediaPermissionStatus { granted, denied, permanentlyDenied }

/// Runtime permissions for reading the user's audio library.
///
/// Desktop has no such permission — the library is whatever folders the user
/// explicitly picks — so every entry point below returns granted immediately
/// on Linux/Windows/macOS without ever touching permission_handler or
/// device_info_plus, both of which are mobile-only concerns.
class PermissionService {
  static int? _cachedSdkInt;

  /// The device's Android API level.
  ///
  /// This decides which permission even exists: READ_MEDIA_AUDIO was introduced
  /// in API 33 and READ_EXTERNAL_STORAGE stopped granting audio access there, so
  /// requesting the wrong one silently yields no access.
  static Future<int> _androidSdkInt() async {
    if (!PlatformInfo.isAndroid) return 0;
    _cachedSdkInt ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    return _cachedSdkInt!;
  }

  /// The permission that actually governs audio access on this device.
  static Future<Permission> _audioPermission() async {
    if (PlatformInfo.isIOS) return Permission.mediaLibrary;
    final sdkInt = await _androidSdkInt();
    return sdkInt >= 33 ? Permission.audio : Permission.storage;
  }

  static MediaPermissionStatus _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return MediaPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied) {
      return MediaPermissionStatus.permanentlyDenied;
    }
    return MediaPermissionStatus.denied;
  }

  /// Ask for audio library access.
  static Future<MediaPermissionStatus> request() async {
    if (!PlatformInfo.isMobile) return MediaPermissionStatus.granted;
    final permission = await _audioPermission();
    return _map(await permission.request());
  }

  /// Check access without prompting.
  static Future<MediaPermissionStatus> check() async {
    if (!PlatformInfo.isMobile) return MediaPermissionStatus.granted;
    final permission = await _audioPermission();
    return _map(await permission.status);
  }

  /// Open the system settings page so a permanently-denied permission can be
  /// granted by hand.
  static Future<bool> openSettings() => openAppSettings();
}
