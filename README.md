# Kivo

IPTV launcher for Android TV: a hardcoded set of playlists whose channels are
browsed, favourited, and played full-screen on a TV remote.

Built with Flutter, driven entirely by the D-pad — no pointer, no on-screen
back button, no assumption of a touchscreen anywhere in the app.

---

## What it does

Kivo isn't a bring-your-own-playlist app in the usual sense. It ships with a
curated set of live-TV sources baked in, seeds them on first launch, and keeps
them fresh in the background — the user's job is to browse, favourite, and
watch, not manage URLs.

- **Netflix-style home dashboard** — horizontal rows for Live Now, Favourites,
  Recently Watched, and the top channel groups by size, all D-pad navigable
  left/right within a row and up/down between rows.
- **Global search** — debounced, paginated, full-text across every channel
  and live match.
- **Full-screen player** with:
  - auto-skip to the next channel on stream failure (404, refused, stalled
    >20s), with a brief "Skipped · X unavailable" toast, capped at one lap
    through the zap list so a dead playlist can't loop forever
  - one silent re-resolve before giving up, in case a mid-watch drop was
    actually a token expiring
  - proactive token refresh scheduled 60s before a resolved stream's expiry
  - live-edge drift tracking ("12s behind live · Sync") and a manual
    "snap to live" action
  - a slide-in channel sidebar for browsing without leaving the stream
  - per-user audio delay (A/V sync) for TVs/soundbars whose HDMI audio
    pipeline adds latency the player can't otherwise see
- **Favourites & watch history**, persisted per channel URL.
- **Per-source toggles** in Settings — disable a noisy source without
  deleting it; disabled sources vanish from every screen instantly.
- **Dark / light theme**, alphabetical-vs-provider-order sort, all persisted.
- **Built to survive weak hardware**: tuned for 1 GB-RAM Android TV boxes —
  bounded demuxer buffers, MediaCodec direct rendering, capped image cache,
  paginated DB reads, debounced UI invalidation.

## Channel sources

Seeded automatically, refreshed on a schedule, individually toggleable in
Settings:

| Source | What it is | Resolution |
|---|---|---|
| **Ultimate IPTV** / **Bengali (IPTV-org)** | Public M3U playlists | Direct — URL is already playable |
| **TFLIX Live** | Scraped live sports fixtures, re-scraped on app resume (throttled) | `tflix://` — iframe → XOR-decrypted player page → HLS or DRM'd DASH |
| **FootMad** | An encrypted multi-category sports catalog; each visible category becomes its own toggleable playlist | Direct M3U per category |
| **IPTV IDN** | A bundled channel list | `iptvidn://` — per-slug Flussonic token, rotates every play |
| **StreamCricHD** | A numbered channel range | Direct URL → resolver extracts the real HLS host + expiry from the player page |
| **Local IPTV** | A LAN-only Flussonic panel (10.255.255.50), silently skipped when unreachable | Direct |

A **channel reference** (the stable string stored as a channel's `url`, and
the key for favourites/history) is either already playable, or a
scheme-prefixed reference a **resolver** turns into a playable URL *at play
time* — because the underlying host, token, or DRM key is short-lived and
can't be precomputed. See `CONTEXT.md` for the full glossary.

## Architecture

```
lib/
  core/
    db/               DatabaseService — sqflite, FTS5 search w/ LIKE fallback,
                       versioned schema migrations
    router/            go_router routes (AppRoutes + currentRoutePath)
    theme/              AppColors (Palette bundle) · AppSpacing · AppTheme
    widgets/            ChannelCard · SettingsDrawer · FocusableTap (D-pad
                        focus/activate wrapper used by every tappable widget)
    image_cache_util.dart  UI-layer image-cache purge (kept out of the repo)
    back_guard.dart     Swallows duplicate KEYCODE_BACK from flaky TV firmware
  features/
    home/               Dashboard (Live / Favourites / Recent / Groups rows)
    search/              Debounced, paginated global search
    player/
      player_screen.dart     Screen-only state: overlay, sidebar, focus
      playback_session.dart  Player, stream resolution, watchdog, auto-skip,
                              re-resolve, expiry refresh — everything about
                              "playing one channel and zapping through a list"
      drift_tracker.dart      Live-edge drift + "playing for X" clock
      widgets/                Overlay, channel sidebar, status views
  models/               Channel · Playlist (both DB row ⇄ model, no ORM)
  providers/            Riverpod glue — see below
  services/
    playlist_repository.dart   Seeds/refreshes every source, owns the five
                                per-section version notifiers the dashboard
                                watches
    stream_resolver.dart       Dispatch table: reference → owning resolver
    *_resolver.dart            One resolver per scheme (tflix / iptvidn /
                                streamcrichd) — pure parsers, unit-tested
    *_service.dart              One fetch-only service per source (footmad /
                                tflix / local_iptv / playlist M3U parser)
    player_tuning.dart          libmpv property tuning for low-end Android TV
                                SoCs (hwdec, cache bounds, A/V sync, DRM keys)
```

### Providers (Riverpod)

- `repositoryProvider` — the single app-wide `PlaylistRepository`.
- `bootstrapProvider` — one-time DB open + seed; gates the splash screen.
- `dashboard_provider.dart` — `liveMatchesProvider`, `favoritesProvider`,
  `recentProvider`, `groupsProvider`, `playlistsProvider`: each bridges one
  `DebouncedVersion` notifier from the repository so only the section that
  actually changed re-fetches and rebuilds.
- `sortAlphaProvider`, `audioDelayProvider`, `themeModeProvider` — persisted
  user settings, all built on the shared `PersistedNotifier<T>` base
  (`providers/persisted_notifier.dart`): load-once-from-prefs, write-through
  on every change.
- `fetch_status_provider.dart` — `isFetchingProvider` / `fetchErrorProvider`,
  surfaced as the Settings "Updating channels…" spinner.

## Building

```bash
flutter pub get

# Debug (sideload)
flutter build apk

# Release (requires android/keystore.properties — see template)
flutter build apk --release
flutter build appbundle --release   # Play Store
```

### Keystore setup

```bash
keytool -genkey -v \
  -keystore android/kivo-release.jks \
  -alias kivo -keyalg RSA -keysize 2048 -validity 10000

cp android/keystore.properties.template android/keystore.properties
# fill in storePassword / keyAlias / keyPassword — storeFile stays
# "../kivo-release.jks" (resolved relative to android/app/)
```

### CI release

`.github/workflows/release.yml` builds signed, split-per-ABI release APKs on
every push to `prod` and attaches them to a GitHub Release. It needs four
repo secrets — `KEYSTORE_BASE64` (the `.jks` file, base64-encoded),
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` — mirroring the same
`keystore.properties` fields used locally.

## Sideloading

```bash
adb connect <TV_IP>:5555
adb install build/app/outputs/flutter-apk/app-release.apk
```

(Enable **Settings → Device Preferences → Security & Restrictions → Unknown
sources** first.) `deploy.sh` wraps build + install + launch for the TV at a
fixed LAN IP.

## Tests

```bash
flutter test        # pure parsers/resolvers/models — no device needed
flutter analyze
```

Coverage is deliberately weighted toward the pure, network-independent logic
(M3U/resolver parsing, DB models, color tokens); anything that needs a live
`media_kit` player or a real SQLite file is exercised on-device instead.

## Language

See `CONTEXT.md` for the project's controlled vocabulary — channel
reference, resolver, stream resolution, stream token, slug — so code,
comments, and commits stay consistent about what things are called.
