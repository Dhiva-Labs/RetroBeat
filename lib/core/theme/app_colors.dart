import 'package:flutter/material.dart';

/// The app's colour system.
///
/// Deliberately near-monochrome: surfaces and text carry the layout, and the
/// single accent is spent only on what is *active* (the selected tab, the
/// playing state, a dragged slider). Nothing decorative is coloured, which is
/// what makes a dense library screen read as calm.
///
/// Screens should take colours from `Theme.of(context).colorScheme`, not from
/// here, so that light and dark both work. The constants below exist to build
/// the two schemes.
class AppColors {
  AppColors._();

  /// The one accent. A restrained blue rather than a saturated neon, so it can
  /// sit next to album art without fighting it.
  static const Color accent = Color(0xFF3479F6);
  static const Color accentDark = Color(0xFF6EA3FF);

  static const ColorScheme lightScheme = ColorScheme.light(
    primary: accent,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDDE8FD),
    onPrimaryContainer: Color(0xFF0B315F),
    secondary: Color(0xFF5A5F66),
    onSecondary: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF101012),
    // Secondary text: artist names, counts, timestamps.
    onSurfaceVariant: Color(0xFF6B6F76),
    // Tertiary text and inactive icons.
    outline: Color(0xFF9AA0A6),
    // Hairline dividers.
    outlineVariant: Color(0xFFE4E6EA),

    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAFAFB),
    surfaceContainer: Color(0xFFF3F4F6),
    surfaceContainerHigh: Color(0xFFEDEEF1),
    surfaceContainerHighest: Color(0xFFE7E9EC),

    error: Color(0xFFD93025),
    onError: Color(0xFFFFFFFF),
  );

  static const ColorScheme darkScheme = ColorScheme.dark(
    primary: accentDark,
    onPrimary: Color(0xFF06213F),
    primaryContainer: Color(0xFF1E3A63),
    onPrimaryContainer: Color(0xFFD6E4FF),
    secondary: Color(0xFFB9BEC6),
    onSecondary: Color(0xFF1B1C1E),

    // True black: One UI leans on it for OLED, and it makes album art pop.
    surface: Color(0xFF000000),
    onSurface: Color(0xFFF2F3F5),
    onSurfaceVariant: Color(0xFF9BA1A9),
    outline: Color(0xFF6E747C),
    outlineVariant: Color(0xFF2A2C30),

    surfaceContainerLowest: Color(0xFF000000),
    surfaceContainerLow: Color(0xFF0C0D0F),
    surfaceContainer: Color(0xFF141518),
    surfaceContainerHigh: Color(0xFF1D1F22),
    surfaceContainerHighest: Color(0xFF26282C),

    error: Color(0xFFFF6B60),
    onError: Color(0xFF3F0906),
  );

  /// The retro skin: Windows Media Player's dark chrome and phosphor glow.
  ///
  /// Deliberately breaks the app's own restraint — that is the point of it. It
  /// replaces light/dark entirely rather than layering on top, so there is only
  /// ever one palette in play.
  static const Color retroGlow = Color(0xFF3DE0B0);

  static const ColorScheme retroScheme = ColorScheme.dark(
    primary: retroGlow,
    onPrimary: Color(0xFF00201A),
    primaryContainer: Color(0xFF10453A),
    onPrimaryContainer: Color(0xFFA8F5DF),
    // The amber of an old level meter, for the second accent.
    secondary: Color(0xFFFFB648),
    onSecondary: Color(0xFF2A1A00),

    surface: Color(0xFF080B0E),
    onSurface: Color(0xFFDFE8EC),
    onSurfaceVariant: Color(0xFF8FA3AC),
    outline: Color(0xFF5C6E77),
    outlineVariant: Color(0xFF1E2A31),

    surfaceContainerLowest: Color(0xFF05080A),
    surfaceContainerLow: Color(0xFF0C1116),
    surfaceContainer: Color(0xFF121A20),
    surfaceContainerHigh: Color(0xFF1A252C),
    surfaceContainerHighest: Color(0xFF243139),

    error: Color(0xFFFF6B60),
    onError: Color(0xFF3F0906),
  );

  /// Palette offered when the user picks a colour for a custom group.
  static const List<Color> groupColors = [
    Color(0xFFE05C5C),
    Color(0xFFE08A3C),
    Color(0xFFD9B23C),
    Color(0xFF5CA85C),
    Color(0xFF3D9A8B),
    Color(0xFF3479F6),
    Color(0xFF6C63C4),
    Color(0xFFB05CA8),
    Color(0xFF7A8290),
    Color(0xFF5C6BC0),
    Color(0xFF4CA1AF),
    Color(0xFFC0705C),
  ];
}
