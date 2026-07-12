# Privacy Policy

_Last updated: 2026-07-12_

RetroBeat is a music player that plays the audio files already stored on your
device.

## The app collects nothing

RetroBeat has **no network access**. It does not contain analytics, advertising,
crash reporting, or accounts. No data of any kind is transmitted off your device,
because there is nothing in the app capable of transmitting it.

Everything the app knows — your playlists, groups, liked songs, equalizer presets
and settings — is stored in a local database on your device and is removed when
you uninstall the app.

## Permissions, and why each one exists

**Music and audio (`READ_MEDIA_AUDIO`, or `READ_EXTERNAL_STORAGE` on Android 12
and below).** Required to find and play the songs on your device. Without it the
app has no library. Audio files are read for playback and for their titles,
artists, albums and cover art. They are never copied or uploaded.

**Microphone (`RECORD_AUDIO`) — optional, off by default.** This is only
requested if you turn on **Audio-reactive** under Settings → Retro mode, and only
at the moment you turn it on.

It exists for one reason: to draw a visualiser that responds to the music. Android
gates the API that exposes an audio waveform (`android.media.audiofx.Visualizer`)
behind the microphone permission, *even when the audio being analysed is the
app's own playback*. There is no way to read the spectrum of the song you are
playing without holding that permission.

The app does not record. The analysis data goes straight to the bars on screen
and is discarded frame by frame. Nothing is written to disk and nothing leaves
the device.

If you leave this setting off — which is the default — the permission is never
requested, and the visualiser is a decorative animation that does not read audio
at all. The app says so in Settings rather than implying otherwise.

## Children

The app collects no data from anyone, including children.

## Changes

Any change to this policy will be committed to this repository, so its history is
the record.

## Contact

Open an issue on the project's GitHub repository.
