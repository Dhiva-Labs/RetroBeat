import 'package:flutter_test/flutter_test.dart';
import 'package:retro_beat/core/utils/platform_info.dart';

/// `flutter test` runs on whatever host happens to be running it, not on the
/// platform under development — so nothing here can assert a specific OS.
/// What has to hold everywhere is the relationship between the helpers.
void main() {
  test('isMobile is exactly Android or iOS', () {
    expect(
      PlatformInfo.isMobile,
      PlatformInfo.isAndroid || PlatformInfo.isIOS,
    );
  });

  test('isDesktop is exactly Linux, Windows or macOS', () {
    expect(
      PlatformInfo.isDesktop,
      PlatformInfo.isLinux || PlatformInfo.isWindows || PlatformInfo.isMacOS,
    );
  });

  test('mobile and desktop never overlap', () {
    expect(PlatformInfo.isMobile && PlatformInfo.isDesktop, isFalse);
  });

  test('exactly one platform is reported on a native (non-web) run', () {
    final flags = [
      PlatformInfo.isAndroid,
      PlatformInfo.isIOS,
      PlatformInfo.isLinux,
      PlatformInfo.isWindows,
      PlatformInfo.isMacOS,
    ];
    expect(flags.where((flag) => flag).length, 1);
  });
}
