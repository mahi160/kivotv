# Kivo — Fix Execution Plan (step-by-step)

> Audience: an automated coding agent (even a small model).
> Rules for the executor:
> 1. Do the tasks **in order**. Do not skip.
> 2. After **every** task run: `flutter analyze lib/` — it MUST print `No issues found!`.
>    If it does not, fix your last edit before moving on.
> 3. Only change the exact lines described. Do not reformat unrelated code.
> 4. Each task has: FILE, FIND (exact text), REPLACE (exact text), VERIFY.
> 5. Tick the checkbox `[x]` when a task passes VERIFY.
>
> UI consistency fixes (focus colour, spacing tokens, logo doc) are ALREADY DONE.
> This file covers the remaining **functional / data / performance** bugs.

---

## SECTION A — Database correctness (do first, highest risk)

### [ ] A1. Turn on SQLite foreign keys (fixes orphaned channels on delete)

**FILE:** `lib/core/db/database_service.dart`

**FIND:**
```dart
    final opened = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, _) => _createSchema(db),
```

**REPLACE:**
```dart
    final opened = await openDatabase(
      dbPath,
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => _createSchema(db),
```

**VERIFY:** `flutter analyze lib/` → `No issues found!`
**WHY:** Without this, `ON DELETE CASCADE` never runs, so deleting a playlist
leaves all its channels and recently-watched rows orphaned in the DB.

---

### [ ] A2. Make `replaceChannels` actually replace (stop unbounded DB growth)

**FILE:** `lib/core/db/database_service.dart`

**FIND:**
```dart
  Future<void> replaceChannels({
    required int playlistId,
    required List<Channel> channels,
  }) {
    return upsertChannels(playlistId: playlistId, channels: channels);
  }
```

**REPLACE:**
```dart
  /// Replaces ALL channels for [playlistId] with the supplied list inside a
  /// single transaction. Channels removed upstream are deleted; existing
  /// per-channel user flags (favourite / pinned) are preserved by re-applying
  /// them after the wipe.
  Future<void> replaceChannels({
    required int playlistId,
    required List<Channel> channels,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // Preserve user flags + watch history keyed by url before wiping.
      final prior = await txn.query(
        'channels',
        columns: ['url', 'is_favorite', 'is_pinned'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      final favorite = <String>{};
      final pinned = <String>{};
      for (final row in prior) {
        final url = row['url'] as String;
        if ((row['is_favorite'] as int? ?? 0) == 1) favorite.add(url);
        if ((row['is_pinned'] as int? ?? 0) == 1) pinned.add(url);
      }

      await txn.delete(
        'channels',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );

      final batch = txn.batch();
      for (final channel in channels) {
        final data = channel.toDb(playlistId: playlistId);
        final url = data['url'] as String;
        batch.insert('channels', {
          ...data,
          'is_favorite': favorite.contains(url) ? 1 : 0,
          'is_pinned': pinned.contains(url) ? 1 : 0,
          // is_broken intentionally reset to 0 on every refresh (see A3).
          'is_broken': 0,
        });
      }
      await batch.commit(noResult: true);
    });
  }
```

**VERIFY:** `flutter analyze lib/` → `No issues found!`
**NOTE:** `upsertChannels` may now be unused. Leave it (other code or tests may
reference it). Do NOT delete it in this task.

---

### [ ] A3. Confirm A2 resets `is_broken` on refresh

This is already handled inside the A2 replacement (`'is_broken': 0`).
No extra edit needed. Just confirm the line `'is_broken': 0,` exists in the new
`replaceChannels`.

**VERIFY:** `grep -n "is_broken': 0" lib/core/db/database_service.dart` returns a line.
**WHY:** Previously a channel marked broken (often a false positive from a slow
9-second timeout) stayed broken forever, even after a successful refresh.

---

### [ ] A4. Make the broken-stream timeout less aggressive

**FILE:** `lib/features/player/player_screen.dart`

**FIND:**
```dart
      _playbackFailureTimer = Timer(
        const Duration(seconds: 9),
        _handlePlaybackFailure,
      );
```

**REPLACE:**
```dart
      // Generous timeout — low-end TVs on slow IPTV CDNs need time before we
      // declare a stream dead. Too short = healthy channels flagged broken.
      _playbackFailureTimer = Timer(
        const Duration(seconds: 20),
        _handlePlaybackFailure,
      );
```

**VERIFY:** `flutter analyze lib/` → `No issues found!`

---

## SECTION B — Playlist / bootstrap logic

### [ ] B1. Stop the default "IPTV Org" playlist resurrecting after deletion

**FILE:** `lib/services/playlist_repository.dart`

**FIND:**
```dart
  Future<void> _bootstrap() async {
    // Ensure the default playlist record exists immediately so Settings
    // always shows it, even before channels have been fetched.
    await DatabaseService.instance.upsertPlaylist(
      name: 'IPTV Org',
      url: PlaylistService.playlistUrl,
    );

    final storedCount = await DatabaseService.instance.channelCount();
```

**REPLACE:**
```dart
  static const _defaultSeededKey = 'kivo_default_seeded';

  Future<void> _bootstrap() async {
    // Seed the default IPTV Org playlist ONLY the very first launch. After
    // that, respect the user's choice if they delete it (do not resurrect).
    final prefs = await SharedPreferences.getInstance();
    final alreadySeeded = prefs.getBool(_defaultSeededKey) ?? false;
    if (!alreadySeeded) {
      await DatabaseService.instance.upsertPlaylist(
        name: 'IPTV Org',
        url: PlaylistService.playlistUrl,
      );
      await prefs.setBool(_defaultSeededKey, true);
    }

    final storedCount = await DatabaseService.instance.channelCount();
```

**THEN** add this import at the TOP of the same file, directly under the
existing `import 'package:flutter/foundation.dart';` line:
```dart
import 'package:shared_preferences/shared_preferences.dart';
```

**VERIFY:** `flutter analyze lib/` → `No issues found!`
**WHY:** Bootstrap previously re-inserted IPTV Org on every launch, so a user
could never permanently remove it from Settings.

---

## SECTION C — Player behaviour

### [ ] C1. Mark "watched" once per channel open, not on every play/pause edge

**FILE:** `lib/features/player/player_screen.dart`

**STEP 1 — remove the markWatched from the playing stream listener.**

**FIND:**
```dart
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing) {
        _playbackFailureTimer?.cancel();
        PlaylistRepository.instance.markWatched(_currentChannel);
      }
    });
```

**REPLACE:**
```dart
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing) {
        _playbackFailureTimer?.cancel();
        // Mark watched once per channel, the first time it actually plays.
        if (!_markedWatched) {
          _markedWatched = true;
          PlaylistRepository.instance.markWatched(_currentChannel);
        }
      }
    });
```

**STEP 2 — add the flag field. FIND:**
```dart
  // ── playback failure detection ─────────────────────────────────────────────
  bool   _allStreamsFailed = false;
  Timer? _playbackFailureTimer;
```

**REPLACE:**
```dart
  // ── playback failure detection ─────────────────────────────────────────────
  bool   _allStreamsFailed = false;
  Timer? _playbackFailureTimer;
  // True once the current channel has been recorded as watched.
  bool   _markedWatched = false;
```

**STEP 3 — reset the flag whenever a new channel opens. FIND:**
```dart
  Future<void> _open(Channel channel) async {
    _playbackFailureTimer?.cancel();
    setState(() {
      _currentChannel    = channel;
      _allStreamsFailed  = false;
    });
```

**REPLACE:**
```dart
  Future<void> _open(Channel channel) async {
    _playbackFailureTimer?.cancel();
    _markedWatched = false;
    setState(() {
      _currentChannel    = channel;
      _allStreamsFailed  = false;
    });
```

**VERIFY:** `flutter analyze lib/` → `No issues found!`
**WHY:** `stream.playing` fires `true` on every resume; the old code wrote to
the DB and rebuilt the dashboard on every pause/resume.

---

### [ ] C2. Don't reset/scroll the channel grid to top when favouriting

**FILE:** `lib/features/channels/channel_list_screen.dart`

**STEP 1 — update the favourite in place instead of full reload. FIND:**
```dart
  Future<void> _toggleFavorite(Channel channel) async {
    await PlaylistRepository.instance.setFavorite(channel, !channel.isFavorite);
    _resetAndLoad();
  }
```

**REPLACE:**
```dart
  Future<void> _toggleFavorite(Channel channel) async {
    final newValue = !channel.isFavorite;
    await PlaylistRepository.instance.setFavorite(channel, newValue);
    if (!mounted) return;
    // Patch the single row in place — keeps scroll position intact.
    final idx = _channels.indexWhere((c) => c.url == channel.url);
    if (idx != -1) {
      setState(() {
        _channels[idx] = _channels[idx].copyWith(isFavorite: newValue);
      });
    }
  }
```

**STEP 2 — stop the dashboard listener from nuking the grid. FIND:**
```dart
    ref.listen<AsyncValue<DashboardData>>(dashboardProvider, (prev, next) {
      if (next is AsyncData) _resetAndLoad();
    });
```

**REPLACE:**
```dart
    // NOTE: intentionally NOT reloading the grid on every dashboard change.
    // Favouriting patches the row in place (see _toggleFavorite); a full
    // _resetAndLoad here would reset scroll position to the top.
```

**VERIFY:** `flutter analyze lib/` → `No issues found!`
**IMPORTANT:** After STEP 2, the variable `dashboardProvider` import may become
unused IF it is referenced nowhere else in this file. Run analyze; if it warns
"unused import", remove the line `import '../../providers/dashboard_provider.dart';`
from this file's imports. If no warning, leave it.

---

## SECTION D — Provider cleanup

### [ ] D1. Delete the unused channel-count provider

**FILE:** `lib/providers/channel_count_provider.dart`

**ACTION:** First confirm it is unused:
```
grep -rn "channelCountProvider" lib/
```
If the ONLY match is its own definition file, delete the whole file:
```
rm lib/providers/channel_count_provider.dart
```
If there are other matches, STOP and skip this task.

**VERIFY:** `flutter analyze lib/` → `No issues found!`

---

### [ ] D2. Fix the lost-initial-value bug in the provider bridges

The bridges add the initial value to a broadcast `StreamController` *before*
anyone subscribes, so that first value is dropped (Riverpod sits in loading).

**FILE:** `lib/providers/fetch_status_provider.dart`

**FIND:**
```dart
final isFetchingProvider = StreamProvider<bool>((ref) {
  final notifier = PlaylistRepository.instance.isFetching;
  final ctrl = StreamController<bool>.broadcast();
  ctrl.add(notifier.value);

  void listener() => ctrl.add(notifier.value);
  notifier.addListener(listener);
  ref.onDispose(() {
    notifier.removeListener(listener);
    ctrl.close();
  });

  return ctrl.stream;
});
```

**REPLACE:**
```dart
final isFetchingProvider = StreamProvider<bool>((ref) {
  final notifier = PlaylistRepository.instance.isFetching;
  final ctrl = StreamController<bool>();
  // Seed the current value AFTER the subscription exists so it isn't dropped.
  ctrl.add(notifier.value);

  void listener() => ctrl.add(notifier.value);
  notifier.addListener(listener);
  ref.onDispose(() {
    notifier.removeListener(listener);
    ctrl.close();
  });

  return ctrl.stream;
});
```

**VERIFY:** `flutter analyze lib/` → `No issues found!`
**WHY:** A non-broadcast `StreamController` buffers events until the first
listener attaches, so the seeded value is delivered. (`StreamProvider` only
listens once, so a single-subscription controller is correct here.)

**THEN** apply the IDENTICAL change (just delete the word `.broadcast`) in:
- `lib/providers/dashboard_provider.dart` — the line
  `final ctrl = StreamController<int>.broadcast();` → `final ctrl = StreamController<int>();`

**VERIFY again:** `flutter analyze lib/` → `No issues found!`

---

## SECTION E — Android / build hygiene

### [ ] E1. Align targetSdk with compileSdk

**FILE:** `android/app/build.gradle.kts`

**FIND:**
```kotlin
        targetSdk = 35   // Android 15
```

**REPLACE:**
```kotlin
        targetSdk = 36
```

**VERIFY:** `cd android && ./gradlew tasks >/dev/null 2>&1; cd ..` runs without a
config error (network/SDK availability permitting). If gradle can't run in this
environment, skip the verify but keep the edit.

---

### [ ] E2. Settings screen — don't auto-open the keyboard on entry

**FILE:** `lib/features/settings/settings_screen.dart`

**FIND:**
```dart
                  TextField(
                    controller: _playlistUrlController,
                    autofocus: true,
                    decoration: const InputDecoration(
```

**REPLACE:**
```dart
                  TextField(
                    controller: _playlistUrlController,
                    autofocus: false,
                    decoration: const InputDecoration(
```

**VERIFY:** `flutter analyze lib/` → `No issues found!`
**WHY:** The active nav icon already autofocuses; two autofocus targets compete,
and forcing focus into the URL field pops the on-screen keyboard immediately on
a TV, which is jarring.

---

## SECTION F — Performance (larger; do last, test carefully)

### [ ] F1. Bundle the Inter font instead of fetching it at runtime

`google_fonts` downloads Inter over the network on first use. TVs often have
slow/flaky wifi, causing a font flash or stall on first launch.

**STEPS:**
1. Download the Inter static `.ttf` files (Regular 400, Medium 500, SemiBold
   600, Bold 700, Black 900) from https://fonts.google.com/specimen/Inter .
2. Put them in a new folder `assets/fonts/`.
3. In `pubspec.yaml`, under the existing `flutter:` section, add:
   ```yaml
   fonts:
     - family: Inter
       fonts:
         - asset: assets/fonts/Inter-Regular.ttf
         - asset: assets/fonts/Inter-Medium.ttf
           weight: 500
         - asset: assets/fonts/Inter-SemiBold.ttf
           weight: 600
         - asset: assets/fonts/Inter-Bold.ttf
           weight: 700
         - asset: assets/fonts/Inter-Black.ttf
           weight: 900
   ```
4. In `lib/core/theme/app_theme.dart` replace every `GoogleFonts.inter(...)`
   call with `TextStyle(fontFamily: 'Inter', ...)` keeping the same fontSize /
   fontWeight / color args, and replace `GoogleFonts.interTextTheme()` with
   `const TextTheme()` (let the per-style overrides fill it in).
5. Remove `google_fonts` from `pubspec.yaml` dependencies.
6. Run `flutter pub get`.

**VERIFY:** `flutter analyze lib/` → `No issues found!` AND the app text still
renders. This is a bigger change — if unsure, leave google_fonts and just note
it; do not half-apply.

---

### [ ] F2. (Optional, advanced) Avoid loading the entire channel list in the player

**FILE:** `lib/features/player/player_screen.dart`, method `_loadChannels`.

Currently it pages through the WHOLE table (10k+ rows) into memory on open.
This is acceptable for small playlists but heavy on low-end TVs with the full
IPTV Org list.

Only attempt this if comfortable: change prev/next navigation to query the DB by
ordered offset instead of holding the full list, and make the sidebar a lazily
paged list. This is a design change — leave a note for a human if unsure rather
than half-implementing.

**VERIFY (if attempted):** manual playback test — up/down channel switching and
the sidebar still work.

---

## SECTION G — Structural (optional, after everything above is green)

### [ ] G1. Split `player_screen.dart` (1091 lines) into smaller files

Move these private widgets out of `player_screen.dart` into new files under
`lib/features/player/widgets/`, one per file, keeping them identical:
- `_PlayerOverlay`  → `widgets/player_overlay.dart`
- `_CtrlBtn`        → `widgets/ctrl_btn.dart`
- `_IconAction`     → `widgets/icon_action.dart`
- `_LiveClock`      → `widgets/live_clock.dart`
- `_StreamErrorToast` → `widgets/stream_error_toast.dart`
- `_ChannelListPanel` + `_SidebarItem` → `widgets/channel_list_panel.dart`

Rename each from `_Name` to `Name` (drop the leading underscore) since they move
to another file, add the needed imports, and import them back into
`player_screen.dart`. Run `flutter analyze lib/` after EACH move.

**VERIFY:** `flutter analyze lib/` → `No issues found!` after every single move.

### [ ] G2. Extract a shared `FocusableTap` widget

Six widgets repeat the same `Focus` + `onFocusChange(setState _focused)` +
`onKeyEvent(select/enter → onTap)` pattern: `ChannelCard`, `_NavIcon`,
`_ThemeOption`, `_CtrlBtn`, `_IconAction`, `_SidebarItem`.

Create `lib/core/widgets/focusable_tap.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a focusable, D-pad-activatable region. Calls [onTap] on
/// select/enter, and rebuilds [builder] with the current focus state.
class FocusableTap extends StatefulWidget {
  const FocusableTap({
    super.key,
    required this.onTap,
    required this.builder,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
  });

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
```
Then refactor the six widgets to use it, ONE at a time, running
`flutter analyze lib/` after each. This is purely structural — visuals must not
change.

---

## Final checklist
- [ ] `flutter analyze lib/` → `No issues found!`
- [ ] `flutter test` → all tests pass (`flutter test`)
- [ ] Manual: delete a playlist in Settings, restart app → it stays deleted (B1).
- [ ] Manual: delete a playlist → its channels disappear from Channels (A1).
- [ ] Manual: favourite a channel deep in the grid → scroll position holds (C2).
- [ ] Manual: D-pad around every screen → focus highlight is the SAME colour
      family everywhere (gold on dark, ocean-blue on light).
