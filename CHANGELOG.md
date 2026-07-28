# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-29

### Changed
- Renamed the project from SonicFlow to **RetroBeat**. This touched the Android
  `applicationId` (`com.sonicflow.sonic_flow` → `com.retrobeat.retrobeat`) and the
  iOS bundle identifier, so it lands as a new install rather than an update —
  anyone testing an existing SonicFlow build needs to uninstall it first, and
  this must happen before the first Play Store submission or it can never
  happen again without losing the update path.
- New app icon: a vinyl record whose label gradient runs from the app's default
  accent into the Retro mode glow, ties the two looks the app actually has into
  one mark. Regenerated at every density, adaptive and legacy, plus the Play
  Store listing assets, via `tool/generate_icons.py`.

### Added
- One UI–inspired library: Tracks, Albums, Artists, Genres, Liked, Playlists
  and Groups, with four tabs shown by default and the rest one toggle away in
  Settings. Tabs are reorderable; Tracks and Playlists cannot be hidden.
- Full player with a background tinted from the current cover art, a queue with
  drag-to-reorder, and swipe-to-change-track on both the player and the mini
  player.
- Retro mode: a Windows Media Player skin with eight XP-era visualisations —
  three continuous flowing fields (Ambience, Alchemy, Plenty) plus Bars, Ocean
  Mist, Scope, Battery and Fire Storm. Tap the visualiser to cycle.
- Optional audio-reactive visualiser driven by a real FFT of the playing audio,
  via a native channel to `android.media.audiofx.Visualizer`. Off by default; the
  microphone permission it requires is requested only when it is switched on.
- App icon, adaptive and legacy, plus a launch screen that no longer flashes
  white before a black app.
- Light theme (there previously was not one, despite the switch).
- Release signing config, R8 with keep rules, CI, and a Play Store checklist.

### Fixed
- **The equalizer did nothing.** `equalizer_flutter` was declared in `pubspec.yaml`
  and never imported; moving the sliders only wrote numbers to a database. It now
  runs through just_audio's `AndroidEqualizer` in an `AudioPipeline`, with bands
  and gain range read from the device and preset curves resampled onto them.
- **Album art flickered continuously during playback.** `QueryArtworkWidget`
  builds its `FutureBuilder` future inside `build()`, so every rebuild restarted
  the query and flashed the placeholder — and the mini player rebuilt on every
  position tick. Art is now cached in a provider.
- **The "Dark mode" switch did nothing**, because every screen hardcoded the dark
  palette and there was no light theme to switch to.
- **Three items in the song menu did nothing** — no `onSelected` handler.
- **The search icon did nothing** — empty `onPressed`.
- **The "Hide short audio" setting did nothing** — the 30-second cutoff was
  hardcoded in the scanner.
- **Audio permission was broken on Android 12 and below.** The SDK check was
  hardcoded to `33`, so those devices were asked for a permission that does not
  exist there and silently ended up with an empty library.
- Playlist reorder dropped items one slot off when dragged downwards (the index
  was adjusted twice).
- Custom equalizer presets could be saved but never deleted.

### Removed
- Seven unused dependencies (`go_router`, `shimmer`, `flutter_slidable`,
  `cached_network_image`, `collection`, `path_provider`, `audio_session`) and
  `equalizer_flutter`, which was never imported.
- `MANAGE_EXTERNAL_STORAGE` — broad all-files access that reading a music library
  does not need, and a Play Store rejection risk.
