# Kivo — Implementation Plan (for Sonnet)

> Android-TV-only Flutter IPTV app. Two reported runtime bugs + a batch of
> audit findings. Implement **in priority order**. After every task:
> `flutter analyze lib/` must say `No issues found!`. Run `flutter test` at the
> end. Manual on-device checks are listed per section.
>
> Each task: **FILE → WHAT → CODE → VERIFY**. Code blocks are the intended end
> state; match surrounding style. Do not reformat untouched code.

---

# P0 — Video is black, audio plays (Android TV)

**Root cause (confirmed):** Flutter's **Impeller** renderer does not render
media_kit's video texture correctly on Android / Android TV — audio plays but
the surface stays black. (flutter/flutter#177319, media-kit/media-kit#707,
#955.) Fix = disable Impeller on Android. Secondary fallback = toggle hardware
decoding.

### [x] V1. Disable Impeller on Android  ← primary fix, do first

**FILE:** `android/app/src/main/AndroidManifest.xml`

**WHAT:** Add an `EnableImpeller=false` meta-data inside `<application>`, next to
the existing `flutterEmbedding` meta-data.

**CODE** — add this block right after the `flutterEmbedding` meta-data:
```xml
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
        <!-- media_kit video texture renders black under Impeller on Android TV.
             Force the Skia (GL) backend. See flutter/flutter#177319. -->
        <meta-data
            android:name="io.flutter.embedding.android.EnableImpeller"
            android:value="false" />
```

**VERIFY:**
- `flutter clean && flutter pub get`
- Run on the TV / TV emulator: `flutter run` → open a channel → **video is
  visible**. (If you normally pass flags, `flutter run --no-enable-impeller`
  is the equivalent one-off test.)

---

### [x] V2. Make the VideoController config explicit (fallback lever)

**FILE:** `lib/features/player/player_screen.dart` (in `initState`)

**WHAT:** Give `VideoController` an explicit configuration so hardware
acceleration can be toggled if any specific low-end box still shows black after
V1. Keep HW accel ON by default.

**CODE:**
```dart
    _player     = Player();
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        // If a specific old/low-end box STILL shows black video after the
        // Impeller fix (V1), flip this to false (software decode fallback).
        enableHardwareAcceleration: true,
      ),
    );
```

**VERIFY:** `flutter analyze lib/` clean; video still plays on device.

---

### [x] V0. Allow cleartext (HTTP) traffic  ← do alongside V1, critical for IPTV

**Problem:** Most real IPTV streams **and channel logos are plain `http://`**
(the bundled sample channel is `http://103.89.248.22...`). Android 9+ blocks
cleartext by default. `cached_network_image` (logos) uses the Android HTTP
stack, so **all http logos silently fall back to the placeholder icon**, and any
http playlist/logo fetch via `dart:io` fails. (libmpv does its own networking so
video may still play, but logos + http M3U fetches will not.)

**FILE:** `android/app/src/main/AndroidManifest.xml`

**WHAT:** Add `android:usesCleartextTraffic="true"` to the `<application>` tag.
```xml
    <application
        android:label="Kivo"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:banner="@drawable/tv_banner"
        android:usesCleartextTraffic="true">
```
(For a stricter setup use a `network_security_config.xml` allowing cleartext;
for an IPTV launcher that must reach arbitrary user-supplied hosts, the blanket
flag is the pragmatic choice.)

**VERIFY:** On device, channels whose logo URL is `http://` now show real logos;
adding an `http://` M3U works.

---

### [x] V3. Confirm the video is actually on screen (layout sanity)

**FILE:** `lib/features/player/player_screen.dart` (build → Stack)

**WHAT:** No code change expected — just confirm during V1 testing that the
`Video` widget is the first (bottom) child of the `Stack(fit: StackFit.expand)`
and the overlay gradient above it is still partly transparent (it is:
`[0xCC000000, transparent, 0xCC000000]`). If video shows only when the overlay
is hidden, the overlay is too opaque — not currently the case, leave as is.

**VERIFY:** Manual — video visible both with overlay shown and hidden.

---

# P0 — D-pad navigation is funky

**Root cause:** the overlay and the channel-list sidebar are **always mounted
and focusable**, even when hidden/off-screen. Directional focus traversal walks
into invisible widgets, so the remote appears dead or focus "disappears"
(e.g. pressing RIGHT on the favourite button jumps focus into the off-screen
sidebar). Fix = exclude hidden subtrees from focus and contain traversal.

### [x] N1. Exclude hidden overlay + sidebar from focus; contain traversal

**FILE:** `lib/features/player/player_screen.dart` (build method)

**WHAT:**
1. Wrap the overlay (`PlayerOverlay`) in `ExcludeFocus(excluding: !_showOverlay)`
   and a `FocusTraversalGroup` so D-pad can't leave the control row.
2. Wrap the sidebar `FocusScope` in `ExcludeFocus(excluding: !_showChannelList)`.

**CODE** — overlay section:
```dart
            // ── Main overlay (fades) ──────────────────────────────────────────
            AnimatedOpacity(
              opacity:  _showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: ExcludeFocus(
                excluding: !_showOverlay,
                child: IgnorePointer(
                  ignoring: !_showOverlay,
                  child: FocusTraversalGroup(
                    child: PlayerOverlay(
                      channel:          _currentChannel,
                      channelIndex:     _currentIndex,
                      channelTotal:     _channels.length,
                      player:           _player,
                      showingList:      _showChannelList,
                      onPrevious:       _playPrevious,
                      onNext:           _playNext,
                      onInteraction:    _scheduleOverlayHide,
                      onBack:           () => context.go('/channels'),
                      onToggleList:     _toggleChannelList,
                      playFocusNode:    _playFocusNode,
                      onToggleFavorite: _toggleCurrentFavorite, // see N3
                    ),
                  ),
                ),
              ),
            ),
```

**CODE** — sidebar section:
```dart
            // ── Channel list sidebar (slides in from right) ───────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve:    Curves.easeOut,
              top: 0, bottom: 0,
              right: _showChannelList ? 0 : -(AppSpacing.tvSidebarWidth + 20),
              child: ExcludeFocus(
                excluding: !_showChannelList,
                child: FocusScope(
                  node: _sidebarScopeNode,
                  child: ChannelListPanel(
                    channels:         _channels,
                    currentChannel:   _currentChannel,
                    scrollController: _sidebarScroll,
                    onSelectChannel: (ch) {
                      setState(() => _showChannelList = false);
                      _open(ch);
                    },
                    onToggleFavorite: _toggleSidebarFavorite, // see N3
                  ),
                ),
              ),
            ),
```

**VERIFY:** On device — with overlay open, LEFT/RIGHT cycles only the control
buttons and never loses focus; pressing RIGHT on the favourite (rightmost)
button does NOT jump into the sidebar.

---

### [x] N2. Keep root focus authoritative when nothing is shown

**FILE:** `lib/features/player/player_screen.dart` (`_onKeyEvent`)

**WHAT:** When the sidebar is closed, also consume `arrowLeft`/`arrowRight` at
the root so stray traversal can't move focus to the (now excluded, but still)
hidden overlay edges. Add this near the other arrow handlers, only for the
**overlay-hidden** case:

**CODE** — add after the Down handler block:
```dart
    // When the overlay is hidden, the root owns all directional keys so focus
    // can never wander into an invisible control. Left/Right are no-ops here.
    if (!_showOverlay &&
        (key == LogicalKeyboardKey.arrowLeft ||
         key == LogicalKeyboardKey.arrowRight)) {
      _showControls();
      return KeyEventResult.handled;
    }
```

**VERIFY:** With overlay hidden, any arrow press brings the overlay back and
focus lands on the play button — never nowhere.

---

### [x] N3. Make "favourite" reachable from the grid with a real remote + fix in-place update

**Problem:** Grid cards and sidebar rows expose favourite only via
`onLongPress`. A D-pad **OK** is a key event — `GestureDetector.onLongPress`
never fires from a remote, so favouriting is impossible on TV from the grid,
and the Home empty-state text ("Long press any channel…") is wrong.

**FILE 1:** `lib/core/widgets/focusable_tap.dart`

**WHAT:** Add an optional `onMenu` callback fired by the TV remote **menu**
button (`LogicalKeyboardKey.contextMenu`), keep `onLongPress` for touch.

**CODE** — extend the widget:
```dart
class FocusableTap extends StatefulWidget {
  const FocusableTap({
    super.key,
    required this.onTap,
    required this.builder,
    this.onLongPress,
    this.onMenu,
    this.focusNode,
    this.autofocus = false,
  });

  final VoidCallback  onTap;
  final VoidCallback? onLongPress;
  /// Fired by the TV remote MENU button (KEYCODE_MENU) while focused.
  final VoidCallback? onMenu;
  final FocusNode?    focusNode;
  final bool          autofocus;
  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}
```
And in `_FocusableTapState.build`, extend the key handler:
```dart
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (widget.onMenu != null && k == LogicalKeyboardKey.contextMenu) {
          widget.onMenu!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
```

**FILE 2:** `lib/core/widgets/channel_card.dart`

**WHAT:** Pass `onMenu` through so the focused card favourites on MENU. Add an
`onFavorite` param (alias of the long-press action) wired to both `onMenu` and
`onLongPress`.
```dart
    return FocusableTap(
      onTap:       isBroken ? () {} : onTap,
      onLongPress: onFavoriteLongPress,
      onMenu:      onFavoriteLongPress,
      builder: (context, focused) {
```

**FILE 3:** `lib/features/player/widgets/channel_list_panel.dart`

**WHAT:** Same — wire `onMenu: onLongPress` on the `_SidebarItem`'s
`FocusableTap`.

**FILE 4:** `lib/features/home/home_screen.dart`

**WHAT:** Fix the now-accurate hint text:
```dart
          emptyText: 'Open a channel and press the star, or press MENU on a channel, to favourite it.',
```

**FILE 5:** `lib/features/player/player_screen.dart`

**WHAT:** Extract the two inline `onToggleFavorite` closures referenced by N1
into named methods, and make them **patch in place** (see M1) instead of
reloading the whole list:
```dart
  Future<void> _toggleCurrentFavorite() async {
    final newValue = !_currentChannel.isFavorite;
    await PlaylistRepository.instance.setFavorite(_currentChannel, newValue);
    if (!mounted) return;
    final updated = _currentChannel.copyWith(isFavorite: newValue);
    setState(() {
      _currentChannel = updated;
      final i = _channels.indexWhere((c) => c.url == updated.url);
      if (i != -1) _channels[i] = updated;
    });
  }

  Future<void> _toggleSidebarFavorite(Channel ch) async {
    final newValue = !ch.isFavorite;
    await PlaylistRepository.instance.setFavorite(ch, newValue);
    if (!mounted) return;
    setState(() {
      final i = _channels.indexWhere((c) => c.url == ch.url);
      if (i != -1) _channels[i] = _channels[i].copyWith(isFavorite: newValue);
      if (ch.url == _currentChannel.url) {
        _currentChannel = _currentChannel.copyWith(isFavorite: newValue);
      }
    });
  }
```

**VERIFY:**
- `flutter analyze lib/` clean.
- On device: focus a grid card, press the remote MENU button → star appears,
  scroll position unchanged. In the player, the favourite button still works.
- Note: not all TV remotes have a MENU key. The player overlay star is the
  guaranteed path; MENU is the grid convenience. Keep both.

---

# P1 — Database regressions (data loss + add-playlist crash)

### [x] D1. Rewrite `replaceChannels` as a non-destructive diff

**Problem (two bugs):**
1. `batch.insert('channels', …)` has no conflict handling → a **duplicate URL**
   in the M3U (common in real provider playlists) or a URL shared with another
   playlist throws `UNIQUE` → adding a provider playlist fails entirely.
2. `txn.delete(channels where playlist_id)` + `PRAGMA foreign_keys=ON` →
   `recently_watched ... ON DELETE CASCADE` **wipes watch history** on every
   refresh.

**FILE:** `lib/core/db/database_service.dart`

**WHAT:** Add `import 'dart:math' as math;` at the top. Replace the whole
`replaceChannels` method with a diff: delete only URLs that disappeared upstream,
then upsert via `ON CONFLICT(url) DO UPDATE` (which does NOT delete rows → no
cascade → favourites/pinned/recently-watched all survive) and reset `is_broken`.

**CODE:**
```dart
  /// Reconciles the stored channels for [playlistId] with [channels].
  ///
  /// - Channels that disappeared upstream are deleted (their recently_watched
  ///   rows correctly cascade away).
  /// - Surviving / new channels are upserted via ON CONFLICT DO UPDATE, which
  ///   updates a row in place WITHOUT deleting it — so is_favorite, is_pinned
  ///   and recently_watched history are preserved, and is_broken is cleared.
  /// - Duplicate URLs within the payload, or URLs owned by another playlist,
  ///   are handled by the upsert instead of throwing a UNIQUE violation.
  Future<void> replaceChannels({
    required int playlistId,
    required List<Channel> channels,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final newUrls = channels.map((c) => c.url).toSet();

      // Delete only the channels that vanished from the new payload.
      final existing = await txn.query(
        'channels',
        columns: ['url'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      final toDelete = <String>[
        for (final row in existing)
          if (!newUrls.contains(row['url'] as String)) row['url'] as String,
      ];
      const chunk = 500; // stay under SQLite's variable limit
      for (var i = 0; i < toDelete.length; i += chunk) {
        final slice =
            toDelete.sublist(i, math.min(i + chunk, toDelete.length));
        final placeholders = List.filled(slice.length, '?').join(',');
        await txn.delete(
          'channels',
          where: 'url IN ($placeholders)',
          whereArgs: slice,
        );
      }

      // Upsert the payload. DO UPDATE leaves is_favorite / is_pinned untouched
      // and resets is_broken; duplicate URLs simply update the same row.
      final batch = txn.batch();
      for (final channel in channels) {
        final data = channel.toDb(playlistId: playlistId);
        batch.rawInsert(
          '''
INSERT INTO channels (id, playlist_id, name, url, logo, group_name, search_text, is_pinned, is_favorite, is_broken)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
ON CONFLICT(url) DO UPDATE SET
  id          = excluded.id,
  playlist_id = excluded.playlist_id,
  name        = excluded.name,
  logo        = excluded.logo,
  group_name  = excluded.group_name,
  search_text = excluded.search_text,
  is_broken   = 0
''',
          [
            data['id'],
            data['playlist_id'],
            data['name'],
            data['url'],
            data['logo'],
            data['group_name'],
            data['search_text'],
            data['is_pinned'],
            data['is_favorite'],
          ],
        );
      }
      await batch.commit(noResult: true);
    });
  }
```

**DO NOT** use `ConflictAlgorithm.replace` here — that is INSERT-OR-REPLACE which
deletes the conflicting row and re-triggers the recently_watched cascade. The
`DO UPDATE` form above is required.

**VERIFY:**
- `flutter analyze lib/` clean; `flutter test` green.
- Manual: add a provider M3U that contains duplicate stream URLs → it imports
  with no error. Watch a channel, then Settings → Refresh All → the channel is
  still under "Recently watched" on Home, and favourites are intact.

---

### [x] D2. Reset `is_broken` in `upsertChannels` too (samples + any upsert path)

**FILE:** `lib/core/db/database_service.dart` (`upsertChannels` raw SQL)

**WHAT:** Add `is_broken = 0` to the `ON CONFLICT(url) DO UPDATE SET` list so a
sample/built-in channel that was flagged broken can recover on re-seed.

**CODE** — append to the DO UPDATE SET clause:
```sql
ON CONFLICT(url) DO UPDATE SET
  id = excluded.id,
  playlist_id = excluded.playlist_id,
  name = excluded.name,
  logo = excluded.logo,
  group_name = excluded.group_name,
  search_text = excluded.search_text,
  is_broken = 0
```

**VERIFY:** `flutter analyze lib/` clean.

---

# P1 — Player performance (low-end TV)

### [x] PF1. Cache `_currentIndex` instead of scanning on every rebuild

**FILE:** `lib/features/player/player_screen.dart`

**WHAT:** `_currentIndex` does `indexWhere` over up to ~10k channels and is read
in `build` (rebuilt by the playing-stream, the 30 s clock, and buffering). Cache
it and recompute only when `_channels` or `_currentChannel` change.

**CODE:**
- Add a field: `int _currentIndexCache = -1;`
- Add a recompute helper:
```dart
  void _recomputeIndex() {
    _currentIndexCache =
        _channels.indexWhere((c) => c.url == _currentChannel.url);
  }
```
- Replace the getter:
```dart
  int get _currentIndex => _currentIndexCache;
```
- Call `_recomputeIndex()` at the end of `_loadChannels` (after `setState`),
  inside `_open` (after `_currentChannel` is set), and in the favourite helpers
  from N3 (after mutating `_channels`/`_currentChannel`).

**VERIFY:** `flutter analyze lib/` clean; channel up/down + sidebar jump still
land on the correct channel.

---

### [x] PF2. (already covered by N3) favourite toggles patch in place

No separate work — N3 replaced the two `await _loadChannels()` favourite paths
with in-place `setState`. Confirm there is no remaining `_loadChannels()` call
inside a favourite handler.

**VERIFY:** `grep -n "_loadChannels" lib/features/player/player_screen.dart`
shows it only in `initState` and (optionally) where channels are first loaded —
never inside a favourite callback.

---

# P2 — Robustness / polish

### [x] R1. Add an overall timeout to the playlist body download

**FILE:** `lib/services/playlist_service.dart`

**WHAT:** Headers are timed out but the body read (`.toList()`) is not, so a
server that stalls mid-stream hangs the fetch forever and leaves Home's
"Fetching channels…" bar stuck. Add a timeout around the body collection.

**CODE:**
```dart
      final lines = await response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList()
          .timeout(const Duration(seconds: 90));
```

**VERIFY:** `flutter analyze lib/` clean.

---

### [x] R2. Stop the Home dashboard flashing a spinner on reload

**FILE:** `lib/features/home/home_screen.dart`

**WHAT:** `dashboardProvider` re-enters loading when favourites/recent change;
`.when(loading:)` blanks the whole dashboard. Skip the reload spinner.

**CODE:**
```dart
                  child: ref.watch(dashboardProvider).when(
                    skipLoadingOnReload: true,
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('Failed to load dashboard: $e'),
                    ),
                    data: (data) => ListView(
```

**VERIFY:** Favourite a channel, return to Home → list updates without a flash.

---

### [x] R3. Parse M3U off the UI isolate

**FILE:** `lib/services/playlist_service.dart`

**WHAT:** `parseM3uLines` (regex per line over ~10k entries) runs on the main
isolate and janks the UI during fetch. Move it to a background isolate via
`compute`. Pass the **joined string** (isolate messaging handles a single String
far better than a 10k-element `List<String>`).

**CODE:**
```dart
import 'package:flutter/foundation.dart' show compute;
// ...
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 90));
      return compute(parseM3u, body);
```
`parseM3u(String)` already exists and calls `parseM3uLines`. Remove the now
unused `LineSplitter().transform` path if it becomes dead. Also update the
docstring on `fetchChannels` — it currently claims streaming/no-large-string,
which is no longer true; state plainly that the body is read fully then parsed
in a background isolate.

**VERIFY:** `flutter analyze lib/` clean; `flutter test` (parser tests) green;
adding a large playlist no longer freezes the UI.

---

### [x] R0. Keep the screen awake during playback  ← important on TV

**Problem:** Live TV plays with no D-pad input for long stretches; without a
wakelock the Android TV screensaver / display sleep can kick in mid-stream.
media_kit_video does not manage this for you.

**OPTION A (preferred, no new dependency):** set the Android window flag from
the player screen via a tiny platform call, or simplest — add the
`wakelock_plus` package:
```yaml
  wakelock_plus: ^1.2.8
```
**FILE:** `lib/features/player/player_screen.dart`
- `initState`: `WakelockPlus.enable();`
- `dispose`:  `WakelockPlus.disable();`
(Enable only while the player screen is mounted, so other screens can sleep.)

**OPTION B (no package):** in `android/.../MainActivity.kt`, but that keeps the
screen on app-wide — less precise. Prefer A.

**VERIFY:** `flutter analyze lib/` clean; leave a stream playing with no input →
the TV does not dim/screensaver. Leaving the player lets the screen sleep again.

---

### [x] R7. Don't declare "all streams failed" before the channel list has loaded

**Problem:** `_loadChannels()` is fire-and-forget while `_open()` runs in a
post-frame callback. If the first channel errors before `_channels` is
populated, `_nextAvailableChannel()` returns null → the "All streams
unavailable" dialog shows even though the list simply wasn't ready.

**FILE:** `lib/features/player/player_screen.dart` (`_handlePlaybackFailure`)

**WHAT:** If `_channels` is still empty, retry the current channel shortly
instead of giving up.
```dart
  Future<void> _handlePlaybackFailure() async {
    _playbackFailureTimer?.cancel();
    if (_failedUrls.contains(_currentChannel.url)) return;

    // List not loaded yet — can't pick a fallback; retry the current channel.
    if (_channels.isEmpty) {
      _playbackFailureTimer =
          Timer(const Duration(seconds: 5), _handlePlaybackFailure);
      return;
    }
    // ... existing logic ...
  }
```

**VERIFY:** Open a known-bad channel on a fresh launch → it doesn't instantly
show "All streams unavailable" before neighbours are known.

---

### [x] R8. Verify the release build plays video and keeps mpv symbols

**WHAT:** The release build enables R8 (`isMinifyEnabled = true`,
`isShrinkResources = true`). Confirm video still plays in release (the Impeller
meta-data from V1 applies to release too) and that `proguard-rules.pro` keeps
media_kit / libmpv JNI symbols (it currently does — don't remove those rules).

**VERIFY:** `flutter build apk --release` (or appbundle) installs and plays
video on the TV; no `UnsatisfiedLinkError` / black screen specific to release.

---

### [x] R4. Pause playback when the app is backgrounded

**FILE:** `lib/features/player/player_screen.dart`

**WHAT:** Pressing the TV Home button leaves media_kit decoding in the
background. Pause on lifecycle `paused`/`inactive`, resume on `resumed`.

**CODE:** make `_PlayerScreenState` a `WidgetsBindingObserver`:
```dart
class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  // initState: WidgetsBinding.instance.addObserver(this);
  // dispose:   WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _player.pause();
    } else if (state == AppLifecycleState.resumed) {
      _player.play();
    }
  }
}
```

**VERIFY:** `flutter analyze lib/` clean; background the app → audio stops;
foreground → resumes.

---

### [x] R5. Lower the image-cache cap for low-RAM boxes

**FILE:** `lib/main.dart`

**WHAT:** 80 MB is high alongside video buffers on 1 GB TV boxes.
```dart
  PaintingBinding.instance.imageCache
    ..maximumSize      = 150
    ..maximumSizeBytes = 48 << 20; // 48 MB
```

**VERIFY:** `flutter analyze lib/` clean.

---

### [x] R6. Small correctness / consistency nits

- **`lib/features/settings/settings_screen.dart` `_friendlyError`:** parenthesise
  the mixed boolean —
  `if (error is SocketException || (error is HttpException && error.message.contains('Failed host lookup')))`.
- **`lib/providers/dashboard_provider.dart`:** make `_dashboardVersionStreamProvider`
  `StreamProvider.autoDispose` so its controller/listener don't outlive the
  (autoDispose) dashboard provider.
- **Brand name:** pick one — nav says "Kivo TV", splash says "Kivo". Use "Kivo"
  in both `app_nav_bar.dart` and `main.dart` splash (or "Kivo TV" in both).

**VERIFY:** `flutter analyze lib/` clean.

---

# Final checklist
- [ ] `flutter analyze lib/` → No issues found!
- [ ] `flutter test` → all pass
- [ ] On a real Android TV / TV emulator:
  - [ ] Video is **visible** with audio (V1).
  - [ ] `http://` channel logos load (not just the placeholder) (V0).
  - [ ] Screen stays awake during playback, sleeps elsewhere (R0).
  - [ ] Release build (`flutter build apk --release`) plays video (R8).
  - [ ] D-pad: focus never disappears; RIGHT off the last overlay button stays
        in the overlay; sidebar open/close behaves (N1/N2).
  - [ ] MENU on a grid card toggles favourite; player star works (N3).
  - [ ] Add a provider M3U with duplicate URLs → imports OK (D1).
  - [ ] Watch a channel → Refresh All in Settings → it's still in
        "Recently watched" and favourites are intact (D1).
  - [ ] Background/foreground the app → playback pauses/resumes (R4).

# Notes for the implementer
- V1 (Impeller) is the single most important change — do it and test video
  before anything else.
- D1 must use `ON CONFLICT … DO UPDATE`, never `ConflictAlgorithm.replace`.
- N3 touches `FocusableTap`, which is shared by 6 widgets — after editing it,
  re-run `flutter analyze` to confirm none broke.
