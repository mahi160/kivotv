# Kivo TV

IPTV launcher for Android TV / Google TV.  
Built with Flutter · Targets Android TV 12+ (API 31+)

---

## Features

- **M3U playlist support** — add any M3U URL; channels merge into one guide
- **3-column channel grid** with logo images and letter-avatar fallbacks
- **Home dashboard** — Favourites, Recently Watched, Pinned rows (3-col grid)
- **Full-screen player** — stream error handling, auto-next on failure, retry
- **D-pad native** — all screens navigable without a pointer
- **Channel sidebar** — slide-in panel while watching; D-pad up/down to browse
- **Dark + Light themes** — system-following by default, manual override in Settings
- **Brand palette** — Ocean Deep Blue · Warm Sandy Beige · Golden Driftwood

## Architecture

```
lib/
  core/
    db/          SQLite (sqflite) database service
    router/      go_router route definitions
    theme/       AppColors · AppSpacing · AppTheme · GradientBackground
    widgets/     AppNavBar · ChannelCard · ChannelLogo · KivoLogo
  features/
    home/        Dashboard screen
    channels/    Paginated channel grid
    player/      Full-screen media player (media_kit)
    settings/    Theme picker · Playlist management
  models/        Channel · Playlist
  providers/     Riverpod: bootstrap · dashboard · channelCount · isFetching · theme
  services/      PlaylistRepository · PlaylistService (M3U parser)
```

## Building

```bash
# Debug (sideload)
flutter build apk

# Release (requires android/keystore.properties — see template)
flutter build apk --release
flutter build appbundle --release   # for Play Store
```

### Keystore setup

```bash
keytool -genkey -v \
  -keystore android/kivo-release.jks \
  -alias kivo -keyalg RSA -keysize 2048 -validity 10000

cp android/keystore.properties.template android/keystore.properties
# fill in storeFile / storePassword / keyAlias / keyPassword
```

## Sideloading

1. Enable **Unknown sources** on TV:  
   Settings → Device Preferences → Security & Restrictions → Unknown sources → ON  
2. Connect via ADB: `adb connect <TV_IP>:5555`  
3. Install: `adb install build/app/outputs/flutter-apk/app-release.apk`

## Tests

```bash
flutter test        # 22 unit tests
flutter analyze     # 0 warnings
```
