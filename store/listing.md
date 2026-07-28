# Play Store listing

Copy for the Play Console listing form. Everything below is drawn from
`README.md`, `PRIVACY.md` and `CHANGELOG.md` — nothing here claims more than
those files already document.

## App title (≤ 30 characters)

```
RetroBeat — Music Player
```

24 characters.

## Short description (≤ 80 characters)

```
Fully offline local music player with equalizer and a WMP-style Retro mode.
```

75 characters.

## Full description (≤ 4000 characters)

```
RetroBeat plays the music already on your device. There is no streaming, no
account, and no network access at all — the app requests no INTERNET
permission, so it has no way to send or receive anything.

LIBRARY
Your music is organised into Tracks, Albums, Artists, Genres, Liked, Playlists
and Groups — a One UI–inspired set of tabs over your library. Four are shown
by default (Tracks, Albums, Artists, Playlists); the rest are one toggle away
in Settings, and every tab can be reordered. Search finds a track, album or
artist without leaving the tab you're on. Playlists are hand-made; Groups
(Favorites, Most Played, Recently Added) fill themselves; Liked songs get
their own tab.

PLAYER
The full player tints its background from the current cover art. The queue
shows the current play order and can be dragged to reorder. Swipe the album
art, or the mini player, to skip — left for next, right for previous.

EQUALIZER
A real equalizer applied to the audio pipeline, not a cosmetic set of
sliders. Presets plus per-band control, with room to save your own.

RETRO MODE
An optional Windows-Media-Player-style skin with eight XP-era
visualisations: three continuous flowing fields (Ambience, Alchemy, Plenty)
plus Bars, Ocean Mist, Scope, Battery and Fire Storm. Tap the visualiser to
cycle through them.

FOLDER EXCLUSION
Any folder can be excluded from the library from Settings → Folders — useful
for ringtone or notification-sound directories you don't want mixed in with
your music. Excluded folders stay listed, so they can be turned back on, but
their songs disappear from your library immediately.

PRIVACY
RetroBeat collects nothing. No analytics, no advertising, no crash reporting,
no account. Everything the app knows — playlists, groups, liked songs,
equalizer presets and settings — lives in a local database on your device
and is removed when you uninstall the app.

The one permission that looks alarming, microphone, is optional and off by
default. It exists only because Android gates its audio-waveform API behind
it, even when the audio being analysed is the app's own playback — turning
on the optional audio-reactive visualiser is the only thing that requests
it, nothing is ever recorded or stored, and leaving it off (the default)
means it is never requested at all. See the in-app Privacy Policy for the
full explanation.
```

## Submission checklist

- **Category:** Music & Audio
- **Content rating questionnaire:** Everyone
- **Privacy policy URL:** https://github.com/Dhiva-Labs/RetroBeat/blob/main/PRIVACY.md
- **Data safety form:**
  - Data collected: none
  - Data shared: none
  - Network access: none — the app has no `INTERNET` permission

### Permission declarations

| Permission | Used for |
|---|---|
| `READ_MEDIA_AUDIO` (API 33+) / `READ_EXTERNAL_STORAGE` (`maxSdk` 32) | Reading the on-device music library. Without it the app has no library. |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK` | Background playback: media notification, lockscreen controls, headset/bluetooth buttons. |
| `RECORD_AUDIO` | Opt-in only, for the audio-reactive visualiser. Android gates `android.media.audiofx.Visualizer` behind `RECORD_AUDIO` even when the audio being analysed is the app's own playback. It is requested at the moment the user turns that setting on, never at launch, and nothing records or stores audio. Leave the setting off and it is never requested. |

(The `RECORD_AUDIO` wording mirrors the comment above that permission in
`android/app/src/main/AndroidManifest.xml`.)

### Assets

| Asset | Path | Notes |
|---|---|---|
| Listing icon | `store/icon-512.png` | 512 × 512 |
| Feature graphic | `store/feature-graphic-1024x500.png` | 1024 × 500 |
| Screenshot — Library | `store/screenshots/library.png` | 1280 × 2560 |
| Screenshot — Player | `store/screenshots/player.png` | 1280 × 2560 |
| Screenshot — Equalizer | `store/screenshots/equalizer.png` | 1280 × 2560 |
| Screenshot — Retro mode | `store/screenshots/retro.png` | 1280 × 2560 |

The `store/screenshots/` images are 2:1 center-crops of the full-height
originals in `docs/screenshots/` (which stay untouched there for the README),
cropped because Play's phone-screenshot limit is 2:1.
