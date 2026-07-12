# R8 is enabled for release builds. These keeps exist because the libraries below
# resolve classes reflectively or by name, which the shrinker cannot see — the
# breakage only ever shows up in a release build, never in debug.

# ExoPlayer, which is just_audio's Android playback engine. It instantiates
# renderers and extractors by name.
-keep class com.google.android.exoplayer2.** { *; }
-keep interface com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# audio_service's foreground service, media session and media button receiver
# are named in AndroidManifest.xml and constructed by the framework.
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }

# androidx media/media3 session plumbing behind audio_service.
-keep class androidx.media.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# The native visualiser: MainActivity constructs it, and Android's audiofx
# classes are loaded by the platform.
-keep class com.retrobeat.retrobeat.** { *; }
-keep class android.media.audiofx.** { *; }

# Flutter plugin registration happens by reflection over generated code.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.embedding.**
