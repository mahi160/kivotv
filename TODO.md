# Kivo IPTV — Full Codebase Audit & Improvement Plan

> Target: Android/Google TV 12+, Flutter, performant, maintainable, themeable.  
> Colors: Deep Oceanic Blue (primary) + Desert-Beach-Sandy (accent). Dark + Light mode.

---

## 🔴 CRITICAL — Blockers for Android TV Release

### [TV-1] Add Android TV / Leanback launcher intent
**File:** `android/app/src/main/AndroidManifest.xml`  
**Problem:** App only declares `LAUNCHER` category. Android TV requires `LEANBACK_LAUNCHER`. Without it, the app won't appear in the TV home screen launcher.  
Also missing: TV banner asset (320×180px required), `android.hardware.touchscreen` uses-feature with `required=false`, `android.software.leanback` feature declaration.

```xml
<!-- Add inside <activity> intent-filter -->
<category android:name="android.intent.category.LEANBACK_LAUNCHER"/>

<!-- Add at manifest level -->
<uses-feature android:name="android.software.leanback" android:required="true"/>
<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>

<!-- Add to <application> -->
android:banner="@drawable/tv_banner"
```

**Action:**
- [ ] Add `LEANBACK_LAUNCHER` to existing intent-filter
- [ ] Add `uses-feature` for leanback + no-touchscreen
- [ ] Create `android/app/src/main/res/drawable/tv_banner.png` (320×180px)
- [ ] Add `android:banner` attribute to `<application>`

---

### [TV-2] Fix app ID and package name
**File:** `android/app/build.gradle.kts`  
**Problem:** `applicationId = "com.example.kivo"` — `com.example` is a reserved namespace that Google Play rejects.

- [ ] Change to `com.kivo.tv` (or your actual domain)
- [ ] Match `namespace` in `build.gradle.kts`

---

### [TV-3] Set explicit minSdk / targetSdk for Android TV 12+
**File:** `android/app/build.gradle.kts`  
**Problem:** Uses `flutter.minSdkVersion` which defaults to 21. Android TV 12 = API 31. `media_kit` also needs API 21+. Should pin explicitly.

- [ ] Set `minSdk = 21` (media_kit minimum)
- [ ] Set `targetSdk = 35` (Android 15, latest)
- [ ] Set `compileSdk = 35`

---

### [TV-4] D-pad back button handling missing on all screens
**Files:** `home_screen.dart`, `channel_list_screen.dart`, `settings_screen.dart`  
**Problem:** No `WillPopScope` / `PopScope` or key handler for `LogicalKeyboardKey.goBack` / `LogicalKeyboardKey.escape`. Pressing D-pad Back on Android TV does nothing on home/channel screens.

- [ ] Wrap root `Scaffold` in `PopScope` or handle back key in `Focus.onKeyEvent`
- [ ] Home screen: back = exit app confirmation dialog
- [ ] ChannelList/Settings: back = navigate to `'/'`

---

### [TV-5] Performance: `allChannels()` loads entire DB (100k rows) into RAM
**Files:** `channel_list_screen.dart`, `player_screen.dart`, `database_service.dart`  
**Problem:** `PlaylistRepository.allChannels()` calls DB with `limit: 100000`. On a large IPTV playlist (50k–200k channels), this allocates hundreds of MB and freezes the UI thread on Android TV.

- [ ] `ChannelListScreen`: switch to paginated `channels()` call (limit=50, offset)
- [ ] Use `ListView.builder` with `itemCount` from `channelCount` + load-more on scroll
- [ ] `PlayerScreen._loadChannels()`: load only channels in current search context, page-by-page
- [ ] Add `AsyncNotifierProvider` (Riverpod) to manage paginated channel state
- [ ] Remove `allChannels()` from all UI call-sites; keep only for internal export/test use

---

## 🟠 HIGH — Architecture & State Management

### [ARCH-1] Riverpod imported but never used for providers
**Files:** `main.dart`, all screens  
**Problem:** `flutter_riverpod` is a dependency and `ProviderScope` wraps the app, but **zero Riverpod providers exist**. All state lives in `DatabaseService.instance` / `PlaylistRepository.instance` singletons + `ValueNotifier` + `StatefulWidget`. This defeats the entire purpose of Riverpod and makes testing and state isolation impossible.

**Plan — introduce providers incrementally:**
- [ ] Create `lib/providers/channel_provider.dart` — `AsyncNotifierProvider<ChannelListNotifier, List<Channel>>` for paginated channel list
- [ ] Create `lib/providers/dashboard_provider.dart` — `FutureProvider<DashboardData>` for home screen sections
- [ ] Create `lib/providers/player_provider.dart` — `NotifierProvider<PlayerNotifier, PlayerState>` for current channel + playback state
- [ ] Create `lib/providers/playlist_provider.dart` — wraps `PlaylistRepository` actions
- [ ] Replace `ValueNotifier<int> dashboardVersion` hack with `ref.invalidate()` on providers
- [ ] Replace `FutureBuilder` in `HomeScreen` with `ref.watch(dashboardProvider)`
- [ ] Replace `StatefulWidget` channel list with `ConsumerWidget` + `ref.watch(channelListProvider)`

---

### [ARCH-2] Bootstrap called outside ProviderScope / fire-and-forget
**File:** `main.dart`  
**Problem:** `PlaylistRepository.instance.bootstrap()` is called after `runApp()` with `.catchError()`. Errors are silently swallowed. If bootstrap fails (e.g. DB migration error), the app shows empty state with no feedback.

- [ ] Move bootstrap into a `FutureProvider` (`appBootstrapProvider`) that the root widget watches
- [ ] Show a proper splash/loading screen while bootstrapping
- [ ] Surface errors to the user (not just `debugPrint`)

---

### [ARCH-3] Feature-first folder structure
**Problem:** Current flat `lib/ui/`, `lib/services/`, `lib/models/` doesn't scale. All domain logic mixes in one layer.

**Target structure:**
```
lib/
  core/
    theme/          ← AppTheme, AppColors, AppSpacing
    router/         ← app_router.dart
    db/             ← database_service.dart
  features/
    home/
      home_screen.dart
      dashboard_provider.dart
    channels/
      channel_list_screen.dart
      channel_provider.dart
    player/
      player_screen.dart
      player_provider.dart
    settings/
      settings_screen.dart
      playlist_provider.dart
  models/
    channel.dart
    playlist.dart
  services/
    playlist_service.dart   ← M3U fetcher/parser
    playlist_repository.dart
```

- [ ] Move files to feature-first structure
- [ ] Update all imports
- [ ] Keep models/ and services/ at root (shared)

---

### [ARCH-4] Channel model is immutable but has no `copyWith`
**File:** `models/channel.dart`  
**Problem:** `Channel` is `const`-constructible but lacks `copyWith`. Every toggle (pin, favorite, broken) requires a round-trip to DB and full list reload instead of local optimistic update.

- [ ] Add `Channel.copyWith({...})` method
- [ ] Enable optimistic UI updates (toggle pin → update local list immediately → persist in background)

---

### [ARCH-5] Playlist model missing
**Files:** `database_service.dart`, `playlist_repository.dart`  
**Problem:** Playlists are returned as raw `Map<String, Object?>` from DB. No typed `Playlist` model exists.

- [ ] Create `lib/models/playlist.dart` with `id`, `name`, `url`, `lastRefreshedAt`
- [ ] Add `Playlist.fromDb()` / `toDb()`
- [ ] Update `DatabaseService.playlists()` to return `List<Playlist>`
- [ ] Show playlist list in Settings screen

---

## 🟡 DESIGN — Theme System (Colors / Spacing / Typography)

### [THEME-1] Create centralized `AppColors` with brand palette
**New file:** `lib/core/theme/app_colors.dart`  
**Problem:** ~25 color literals scattered across 5 files. Zero traceability. Changing brand color = grep-and-pray.

```dart
// Target palette
class AppColors {
  // Primary — Deep Oceanic Blue
  static const oceanDeep    = Color(0xFF0A1628); // darkest bg
  static const oceanDark    = Color(0xFF0D1F3C); // card bg dark
  static const oceanMid     = Color(0xFF1A3A6B); // surface
  static const oceanLight   = Color(0xFF2D6AB4); // primary action
  static const oceanBright  = Color(0xFF5B9BD5); // highlight / focus ring

  // Accent — Desert-Beach-Sandy
  static const sandDark     = Color(0xFF8B6914); // deep sand
  static const sandMid      = Color(0xFFD4A84B); // warm amber
  static const sandLight    = Color(0xFFF2D07A); // sandy highlight
  static const sandPale     = Color(0xFFFAEEC4); // very light sand

  // Neutrals dark
  static const darkBg       = Color(0xFF070B16);
  static const darkSurface  = Color(0xFF111827);
  static const darkBorder   = Color(0x28FFFFFF); // white 16%

  // Neutrals light
  static const lightBg      = Color(0xFFF0F4F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder  = Color(0x1A0A1628); // ocean 10%

  // Semantic
  static const error        = Color(0xFFEF4444);
  static const success      = Color(0xFF22C55E);
  static const warning      = Color(0xFFF59E0B);
}
```

- [ ] Create `lib/core/theme/app_colors.dart`
- [ ] Replace every inline `Color(0xFF...)` in all files with `AppColors.*`

---

### [THEME-2] Create `AppSpacing` constants
**New file:** `lib/core/theme/app_spacing.dart`  
**Problem:** Magic numbers `28, 34, 40, 24, 18, 14, 12, 8` scattered everywhere.

```dart
class AppSpacing {
  static const xs  = 8.0;
  static const sm  = 14.0;
  static const md  = 24.0;
  static const lg  = 34.0;
  static const xl  = 48.0;
  static const xxl = 64.0;

  // TV-specific
  static const tvEdge        = 40.0;  // screen edge padding
  static const tvCardRadius  = 24.0;
  static const tvItemHeight  = 86.0;
  static const tvCardWidth   = 250.0;
  static const tvRowHeight   = 156.0;
}
```

- [ ] Create `lib/core/theme/app_spacing.dart`
- [ ] Replace all magic padding/margin numbers

---

### [THEME-3] Create `AppTheme` with dark + light `ThemeData`
**New file:** `lib/core/theme/app_theme.dart`  
**Problem:** Theme is defined inline in `KivoApp.build()`. No light mode exists.

```dart
class AppTheme {
  static ThemeData dark()  { ... }  // uses AppColors ocean + sand
  static ThemeData light() { ... }  // uses AppColors lightBg + ocean + sand
}
```

- [ ] Extract current dark theme into `AppTheme.dark()`
- [ ] Create `AppTheme.light()` using same token set
- [ ] Seed color = `AppColors.oceanLight` for both
- [ ] Accent/indicator color = `AppColors.sandMid`
- [ ] Update `KivoApp` to use `theme: AppTheme.light(), darkTheme: AppTheme.dark()`
- [ ] Add `themeMode: ThemeMode.system` (follow system setting)
- [ ] Add user-overridable `ThemeMode` setting in Settings screen (persisted via shared_preferences)

---

### [THEME-4] Remove inline gradient definitions from screens
**Files:** `home_screen.dart`, `channel_list_screen.dart`, `settings_screen.dart`  
**Problem:** Each screen re-declares its own `BoxDecoration(gradient: ...)` with raw colors.

- [ ] Add `AppTheme.backgroundGradient(Brightness brightness)` → `LinearGradient`
- [ ] Replace all `DecoratedBox(decoration: BoxDecoration(gradient: ...))` with shared widget `GradientBackground`
- [ ] Or use `scaffoldBackgroundColor` + a single `DecoratedBox` wrapper widget

---

### [THEME-5] Typography system
**Problem:** Font sizes hardcoded (42, 34, 26, 22, 19, 18, 16). Roboto specified by string with no asset — falls back to system font silently.

- [ ] Add `google_fonts` package (or bundle font files)
- [ ] Use `Nunito` or `Inter` (TV-legible, wide weight range) as display font
- [ ] Define `AppTextStyles` or use `ThemeData.textTheme` properly with named styles (`displayLarge`, `titleMedium`, etc.)
- [ ] Remove hardcoded `fontSize` from all widgets; use `Theme.of(context).textTheme.*`

---

## 🟡 TV UX — Focus, Navigation & Polish

### [UX-1] Channel list: D-pad navigation should work naturally
**File:** `channel_list_screen.dart`  
**Problem:** `ListView.builder` with `FocusableActionDetector` works for enter/select but D-pad left/right isn't handled. On Android TV, users expect D-pad Up/Down to scroll the list and D-pad Right to access action buttons (pin/favorite).

- [ ] Add `FocusScopeNode` or use `FocusTraversalGroup` to separate list items from search bar
- [ ] Map D-pad Right on a channel tile to focus the trailing action buttons
- [ ] Map D-pad Left to return focus to the tile
- [ ] Test with Android TV emulator (API 31+)

---

### [UX-2] Home screen channel cards: use `ListView` not `GridView`
**File:** `home_screen.dart`  
**Problem:** `_DashboardSection` uses `GridView.builder(scrollDirection: Axis.horizontal, crossAxisCount: 1)`. `crossAxisCount: 1` makes this functionally identical to a horizontal `ListView` but with `GridView` overhead. Also nested scrollables on Android TV are problematic for D-pad focus.

- [ ] Replace `GridView.builder` with `ListView.builder(scrollDirection: Axis.horizontal)`
- [ ] Set `itemExtent: AppSpacing.tvCardWidth + AppSpacing.sm`
- [ ] Ensure D-pad Left/Right moves focus between cards

---

### [UX-3] Player screen: add channel info bar + volume/back navigation
**File:** `player_screen.dart`  
**Problem:** Standard Android TV UX expectations not met:
- No channel number shown (users expect "CH 42 — BBC News")
- No back-to-list button in overlay
- No volume display (media_kit supports it)
- Overlay appears/disappears abruptly (no fade)

- [ ] Add `AnimatedOpacity` around `_PlayerOverlay` for smooth fade
- [ ] Add channel index indicator (e.g. "12 / 450")
- [ ] Add Back button in overlay → navigate to `/channels`
- [ ] Wrap `_PlayerOverlay` in `AnimatedSlide` from bottom

---

### [UX-4] Player: handle MEDIA key events
**File:** `player_screen.dart`  
**Problem:** Only handles `select`/`enter`/`gameButtonA`. Android TV remotes have dedicated media keys.

- [ ] Handle `LogicalKeyboardKey.mediaPlayPause` → `player.playOrPause()`
- [ ] Handle `LogicalKeyboardKey.mediaStop` → `player.stop()`
- [ ] Handle `LogicalKeyboardKey.channelUp` / `channelDown` → next/previous channel
- [ ] Handle `LogicalKeyboardKey.goBack` → exit player

---

### [UX-5] Remove `SafeArea` from TV screens
**Files:** `home_screen.dart`, `channel_list_screen.dart`, `settings_screen.dart`  
**Problem:** `SafeArea` is for mobile notch avoidance. Android TV screens don't have notches. It wastes ~20–44px on all sides and fights with TV overscan.

- [ ] Remove all `SafeArea` wrappers
- [ ] Instead add explicit `AppSpacing.tvEdge` padding where needed

---

### [UX-6] Settings: show existing playlists list
**File:** `settings_screen.dart`  
**Problem:** User can add playlists but can't see what's already added, can't delete them, can't see last-refresh time.

- [ ] Add `FutureProvider` or query for current playlists
- [ ] Show `ListView` of playlists with name + URL + last refreshed + delete button
- [ ] Add delete playlist action → cascade deletes channels (DB already supports via FK)

---

### [UX-7] Search: `autofocus: false` on channel list blocks keyboard users
**File:** `channel_list_screen.dart`  
**Problem:** `autofocus: false` on search field. TV users navigating with D-pad can't reach search without understanding the focus system.

- [ ] Set `autofocus: true` on search when arriving from Home (or make it the first focusable item via `FocusTraversalOrder`)
- [ ] Add shortcut: D-pad Up from list scrolls to top AND focuses search

---

## 🟢 MEDIUM — Code Quality & Maintainability

### [QUAL-1] `upsertPlaylist` does insert-then-update (two queries)
**File:** `database_service.dart`  
**Problem:** `upsertPlaylist` does `INSERT ... IGNORE` then `UPDATE`. This is 2 round-trips to DB where 1 would do with proper upsert.

- [ ] Replace with single `INSERT ... ON CONFLICT(url) DO UPDATE SET ...`

---

### [QUAL-2] `PlaylistService._downloadPlaylist` loads entire M3U into String
**File:** `services/playlist_service.dart`  
**Problem:** `response.transform(utf8.decoder).join()` reads the entire file (can be 50–200MB for large IPTV lists) into a single `String` in memory before parsing begins. On Android TV with 2GB RAM this can OOM.

- [ ] Stream-parse with line-by-line processing
- [ ] Use `response.transform(utf8.decoder).transform(const LineSplitter())` and emit channels as stream
- [ ] Or at minimum: read in chunks, detect `#EXTINF` boundaries

---

### [QUAL-3] Network request not cancellable
**File:** `services/playlist_service.dart`  
**Problem:** `HttpClient` request has no cancellation. If user navigates away during a large playlist download, the request continues in background indefinitely.

- [ ] Replace `dart:io HttpClient` with `package:http` or `package:dio` (supports cancel tokens)
- [ ] Add `CancelToken` passed from repository to service
- [ ] Cancel in-flight requests when `PlaylistRepository` is disposed or new request starts

---

### [QUAL-4] Error messages shown raw to user
**Files:** `settings_screen.dart`, `home_screen.dart`  
**Problem:** `setState(() => _error = error.toString())` exposes internal error details.

- [ ] Map common errors to user-friendly messages:
  - `SocketException` → "No internet connection"
  - `HttpException` → "Server error (check URL)"
  - `ArgumentError` → show message directly (already user-safe)
  - Otherwise → "Unexpected error. Try again."

---

### [QUAL-5] `PlaylistRepository.exampleChannel` is a public API with a hardcoded real URL
**File:** `services/playlist_repository.dart`  
**Problem:** Hardcoded `'https://owrcovcrpy.gpcdn.net/bpk-tv/1711/output/index.m3u8'` in public source. URL will rot, and it's not configurable.

- [ ] Move to a `lib/core/constants.dart` file
- [ ] Make it easy to disable/replace without touching repository logic

---

### [QUAL-6] `description` and `applicationId` still have default values
**Files:** `pubspec.yaml`, `android/app/build.gradle.kts`  
- [ ] Update `pubspec.yaml` description: `"Kivo — IPTV launcher for Android TV"`
- [ ] Update `applicationId` to non-`com.example` namespace

---

### [QUAL-7] Add `prefer_single_quotes`, `avoid_print` lints
**File:** `analysis_options.yaml`  
**Problem:** `debugPrint` used extensively in production code paths. `avoid_print` lint is commented out.

- [ ] Enable `avoid_print: true`
- [ ] Enable `prefer_single_quotes: true`
- [ ] Replace all `debugPrint` in production code with a proper logger (e.g. `package:logging` or `package:logger`)

---

### [QUAL-8] Release signing config uses debug keys
**File:** `android/app/build.gradle.kts`  
**Problem:** `signingConfig = signingConfigs.getByName("debug")` — release builds signed with debug keys won't be accepted by Google Play.

- [ ] Create proper keystore + `release` signing config
- [ ] Store credentials in `local.properties` (git-ignored)

---

## 🔵 LOW — Missing Features & Future Work

### [FEAT-1] Channel group/category browser
- [ ] Add Groups screen: query `SELECT DISTINCT group_name FROM channels`
- [ ] Route `/groups` → shows group tiles → tap → filters channel list by group
- [ ] Add group filter chips to channel list header

---

### [FEAT-2] Channel logo images
**Problem:** All channel cards show `Icons.live_tv_rounded` placeholder. Most IPTV channels provide `tvg-logo` URLs.

- [ ] Add `cached_network_image` package
- [ ] Replace icon placeholder with `CachedNetworkImage` + icon fallback
- [ ] Add memory cache size limit (important for TV with many channels visible)

---

### [FEAT-3] EPG (Electronic Program Guide) — basic
- [ ] Parse `tvg-id` from M3U (already done)
- [ ] Fetch XMLTV data from EPG source URL (configurable in Settings)
- [ ] Show current programme name in channel card and player overlay

---

### [FEAT-4] Channel number navigation in player
- [ ] Type digits on remote → accumulate for 1.5s → jump to channel by index
- [ ] Show channel number in overlay

---

### [FEAT-5] Auto-refresh playlists on app start
**Problem:** `bootstrap()` only loads cached data. Playlists never auto-refresh unless user taps "Refresh All".

- [ ] Add background refresh if `last_refreshed_at` > 24h ago
- [ ] Show "Updating..." indicator on home screen non-blocking

---

### [FEAT-6] Tests — expand coverage
**Current:** Only `parseM3u` tested (3 test cases).  
**Missing:**
- [ ] `DatabaseService` — upsert, migration, search, pagination
- [ ] `PlaylistRepository` — add, refresh, pin/favorite toggle
- [ ] `AppRouter` — route resolution, extra params
- [ ] Widget tests — `HomeScreen` sections, `ChannelListScreen` search
- [ ] Golden tests — theme dark/light renders

---

## 📋 Implementation Order (Recommended)

| Priority | Task | Effort |
|----------|------|--------|
| 1 | [TV-1] Add LEANBACK_LAUNCHER to Android manifest | 30 min |
| 2 | [TV-2] Fix app ID | 5 min |
| 3 | [TV-3] Set explicit SDK versions | 5 min |
| 4 | [THEME-1] Create AppColors with oceanic + sandy palette | 1h |
| 5 | [THEME-2] Create AppSpacing constants | 30 min |
| 6 | [THEME-3] Create AppTheme dark + light | 2h |
| 7 | [THEME-4] GradientBackground widget | 30 min |
| 8 | [THEME-5] Typography with Google Fonts | 1h |
| 9 | [TV-5] Fix allChannels() pagination (CRITICAL perf) | 2h |
| 10 | [ARCH-1] Introduce Riverpod providers (channel, dashboard) | 3h |
| 11 | [ARCH-2] Bootstrap as FutureProvider + splash screen | 1h |
| 12 | [TV-4] D-pad back handling on all screens | 1h |
| 13 | [UX-5] Remove SafeArea from TV screens | 15 min |
| 14 | [UX-2] Fix home cards: GridView → ListView | 30 min |
| 15 | [UX-3] Player overlay fade + channel info | 1h |
| 16 | [UX-4] Player media key handling | 45 min |
| 17 | [ARCH-3] Feature-first folder restructure | 2h |
| 18 | [ARCH-4] Channel.copyWith() | 15 min |
| 19 | [ARCH-5] Playlist model | 30 min |
| 20 | [QUAL-2] Stream M3U parsing | 2h |
| 21 | [QUAL-3] Cancellable network requests | 1h |
| 22 | [QUAL-4] User-friendly error messages | 30 min |
| 23 | [UX-6] Settings: show playlist list + delete | 1h |
| 24 | [FEAT-2] Channel logos with cached_network_image | 1h |
| 25 | [FEAT-1] Group browser screen | 2h |
| 26 | [FEAT-5] Auto-refresh on startup | 1h |
| 27 | [FEAT-6] Expand test coverage | 3h |

---

## 🎨 Color Reference

```
Primary "Deep Oceanic Blue":
  #0A1628  darkest background
  #0D1F3C  card/surface dark
  #1A3A6B  elevated surface
  #2D6AB4  primary buttons / interactive
  #5B9BD5  focus rings / highlights

Accent "Desert-Beach-Sandy":
  #8B6914  deep sand (dark mode accent text)
  #D4A84B  warm amber (icons, active states)
  #F2D07A  sandy highlight (focus in dark)
  #FAE8C4  pale sand (light mode accent bg)

Semantic:
  Error   #EF4444
  Success #22C55E
  Warning #F59E0B
```

---

*Skills installed: `flutter/skills@flutter-theming-apps` (9.5K installs), `madteacher/mad-agents-skills@flutter-architecture` (1.5K installs)*
