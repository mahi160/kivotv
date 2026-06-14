# Kivo — Fix Execution Plan  ✅ COMPLETE

All tasks below were executed and verified. Kept for audit trail.

---

## SECTION A — Database correctness  ✅

### [x] A1. FK pragma — `onConfigure: db.execute('PRAGMA foreign_keys = ON')`
**FILE:** `lib/core/db/database_service.dart`
Cascade deletes now fire when a playlist is deleted.

### [x] A2. Real `replaceChannels` — transactional delete + re-insert
**FILE:** `lib/core/db/database_service.dart`
Preserves per-channel favourite/pinned flags; clears is_broken on refresh;
removes stale channels that disappeared upstream.

### [x] A3. `is_broken` reset on refresh  ✅ (handled inside A2)

### [x] A4. Failure timeout 9 s → 20 s
**FILE:** `lib/features/player/player_screen.dart`

---

## SECTION B — Playlist / bootstrap  ✅

### [x] B1. Already done before this plan was written.
Bootstrap was refactored to use a `kivo://samples` built-in playlist instead
of resurrecting IPTV Org on every launch. No further change needed.

---

## SECTION C — Player behaviour  ✅

### [x] C1. `markWatched` fires once per channel open, not on every play/pause
**FILE:** `lib/features/player/player_screen.dart`
Added `_markedWatched` flag; reset in `_open`; guard in stream listener.

### [x] C2. Favouriting does not reset scroll to top
**FILE:** `lib/features/channels/channel_list_screen.dart`
`_toggleFavorite` patches the row in-place via `copyWith`.
Removed `ref.listen(dashboardProvider)` which was nuking the list.

---

## SECTION D — Provider cleanup  ✅

### [x] D1. Deleted unused `channel_count_provider.dart`

### [x] D2. Broadcast → single-subscription `StreamController` in both bridges
**FILES:** `lib/providers/fetch_status_provider.dart`,
           `lib/providers/dashboard_provider.dart`
Initial seeded value now buffered and delivered to the first subscriber.

---

## SECTION E — Android / build hygiene  ✅

### [x] E1. `targetSdk` aligned to 36 (matches `compileSdk`)
**FILE:** `android/app/build.gradle.kts`

### [x] E2. Settings URL field `autofocus: false` (was already false — no-op)

---

## SECTION F — Performance  ✅

### [x] F1. Inter font bundled as TTF assets — no network fetch at runtime
- Downloaded Inter 4.0 (Regular/Medium/SemiBold/Bold/Black) to `assets/fonts/`
- Declared in `pubspec.yaml` under `fonts:`
- Rewrote `lib/core/theme/app_theme.dart` — dropped `GoogleFonts.inter*`,
  replaced with `TextStyle(fontFamily: 'Inter', ...)` throughout
- Removed `google_fonts` dependency from `pubspec.yaml`
- `flutter pub get` completed; package removed from lockfile

### [ ] F2. Player channel-list memory — not implemented
  Large playlists (10k+ channels) still load fully into RAM. Safe for
  typical use. Track as a future optimisation if needed.

---

## SECTION G — Structural  ✅

### [x] G1. `player_screen.dart` split  (1108 → 508 lines)
Extracted into `lib/features/player/widgets/`:
- `player_overlay.dart`   — `PlayerOverlay`
- `ctrl_btn.dart`         — `CtrlBtn`
- `icon_action.dart`      — `IconAction`
- `live_clock.dart`       — `LiveClock`
- `stream_error_toast.dart` — `StreamErrorToast`
- `channel_list_panel.dart` — `ChannelListPanel` + `_SidebarItem`

### [x] G2. `FocusableTap` extracted → `lib/core/widgets/focusable_tap.dart`
All six stateful focus-boilerplate widgets converted to `StatelessWidget`:
- `ChannelCard`
- `_NavIcon`       → app_nav_bar.dart
- `_ThemeOption`   → settings_screen.dart
- `CtrlBtn`        → player/widgets/ctrl_btn.dart
- `IconAction`     → player/widgets/icon_action.dart
- `_SidebarItem`   → player/widgets/channel_list_panel.dart

---

## Final verification

- `flutter analyze lib/` → No issues found!
- `flutter test`         → 22/22 passed
