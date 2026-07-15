# Kivo — Code Quality & Bug Audit

**Date:** 2026-07-14
**Scope:** Full codebase (`lib/` + `test/`, ~8 740 lines Dart)
**Method:** Manual read of every source file, `flutter analyze` (clean, 1 info), `flutter test` (55/55 pass)
**Baseline commit:** `f3dd60e`

---

## Summary

| Severity | Count | Theme |
|----------|-------|-------|
| 🔴 P0 — Correctness bugs | 3 | Refresh orchestration is broken for multi-source setups |
| 🟠 P1 — Design / dead code | 4 | Write-only state, disposed-player race, FTS churn, helper duplication |
| 🟡 P2 — Minor | 4 | Unreachable error paths, dead overload, paging race, lint |
| ✅ Strengths | — | Resolver dispatch, PlaybackSession extraction, testable parsers |

The architecture is healthy: clear layering (models → db → repository → providers → features), no file near 1 000 lines, pure parsers with unit tests, deliberate `ponytail:` ceilings documented. The rot is concentrated in **one area: playlist refresh orchestration**, where three independent flaws combine so that the app's core promise — fresh channels from every enabled source — is silently broken.

---

## 🔴 P0 — Correctness Bugs

### P0-1. Parallel refresh cancels itself: only the LAST playlist ever refreshes

**Files:** `lib/services/playlist_service.dart:26`, `lib/services/playlist_repository.dart:428, 489`, `lib/services/footmad_service.dart:57`

`PlaylistService` is a singleton with cancel-previous semantics:

```dart
Future<List<Channel>> fetchChannels({String url = playlistUrl}) async {
  _activeClient?.close(force: true);   // kills the previous fetch
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
  _activeClient = client;
  ...
}
```

But `refreshAllPlaylists()` fans out **concurrently**:

```dart
final fetched = await Future.wait(
  userPlaylists.map((p) async {
    try {
      return (p, await PlaylistService.instance.fetchChannels(url: p.url));
    } catch (_) {
      return (p, null);
    }
  }),
);
```

**Mechanics.** Each `async` closure runs its synchronous prefix immediately. So for playlists A, B, C:

1. Fetch A: closes nothing, sets `_activeClient = clientA`, suspends at `client.getUrl`.
2. Fetch B: **force-closes `clientA`**, sets `_activeClient = clientB`, suspends.
3. Fetch C: **force-closes `clientB`**, sets `_activeClient = clientC`, suspends.
4. A and B resume → their clients are closed → immediate exception → caught → `(p, null)` → counted as "failed".
5. Only C completes.

**Blast radius:**

- With N enabled user playlists, N−1 fail on *every* refresh wave.
- FootMad category refresh (`_refreshFootmadEnabled` → `fetchCategoryChannels`) fans out through the **same singleton**, so only the last category gets channels.
- `manualRefresh()` runs the FootMad wave and the user-playlist wave concurrently → they cancel each other **cross-source**.
- Error suppression: because exactly one fetch survives, `failed == userPlaylists.length` is false → `fetchError` is never set → the failure is invisible.

**Evidence it's vestigial:** `PlaylistService.cancel()` is never called anywhere in the codebase. The cancel-previous machinery exists only to cause this bug.

**Fix (code judo — pure deletion):**

- Delete `_activeClient`, delete `cancel()`, delete the `identical(...)` bookkeeping in `finally`.
- Create an `HttpClient` per call and `close(force: true)` it in `finally` — the exact pattern already used by `TflixService`, `FootmadService`, `LocalIptvService`, and `hls_probe`.
- ~15 lines removed. Bug gone. Singleton mutable state gone.

---

### P0-2. FootMad channels are NEVER fetched automatically; user-playlist staleness gate is permanently broken

**Files:** `lib/core/db/database_service.dart:296-310` (`upsertPlaylist`), `lib/services/playlist_repository.dart` (`_syncFootmadCategories`, `_refreshFootmadIfStale`, `refreshAllPlaylists`)

`upsertPlaylist` unconditionally writes `last_refreshed_at = now` on **every** upsert — insert or metadata refresh — regardless of whether any channels were fetched:

```dart
await db.insert('playlists', { ..., 'last_refreshed_at': now, ... }, conflictAlgorithm: ConflictAlgorithm.ignore);
await db.update('playlists', {'name': name, 'last_refreshed_at': now}, where: 'url = ?', ...);
```

Meanwhile `Playlist.isStale()` reads that same column as "channels last stored". Two flows lie to each other through one column:

**Bug A — FootMad never refreshes.** Bootstrap runs:

```dart
_syncFootmadCategories().then((_) => _refreshFootmadIfStale()),
```

`_syncFootmadCategories` upserts every category → each gets `last_refreshed_at = now` → `_refreshFootmadIfStale` sees `anyStale == false` → `_refreshFootmadEnabled` (the *only* code path that calls `fetchCategoryChannels`) **never runs**. Verified by grep: `fetchCategoryChannels` is reachable only via `_refreshFootmadEnabled`, which fires only from the (dead) stale path and from `manualRefresh`.

**User-visible:** on a fresh install, the default-enabled *SportsOnly* category is **empty forever** until the user manually taps "Refresh now" in Settings. Same after every category catalog change.

**Bug B — user playlists are permanently stale.** `refreshAllPlaylists()` calls `replaceChannels` but never touches `last_refreshed_at` (only `addPlaylist`/`upsertPlaylist` do, at add time). So 24 h after install, every user playlist reads as stale **forever** → `_seedOrRefreshUserPlaylists` triggers a full re-download of every playlist on **every launch**. The 24 h throttle is decorative.

**Fix (code judo — move one write to its true owner):**

`last_refreshed_at` has exactly one honest meaning: *"channels were last stored successfully at T"*. Therefore:

1. Remove the `last_refreshed_at` writes from `upsertPlaylist` entirely.
2. Add `DatabaseService.markRefreshed(int playlistId)` (one `UPDATE`).
3. Call it after each successful `replaceChannels` in the repository (or fold it into `replaceChannels` itself — it already owns the transaction).

Both bugs disappear; the staleness model becomes truthful; no new branches.

---

### P0-3. `channels.url` is globally UNIQUE → playlists steal channels from each other

**Files:** `lib/core/db/database_service.dart` (schema `url TEXT NOT NULL UNIQUE`, `replaceChannels` step-2 UPDATE)

The diff-upsert's step 2 re-parents rows across playlists:

```dart
batch.rawUpdate(
  'UPDATE channels SET id=?, playlist_id=?, name=?, logo=?, group_name=?, search_text=? WHERE url=?',
  [..., data['playlist_id'], ..., data['url']],
);
```

If the same stream URL appears in two playlists — common in practice (FootMad dedup is per-category only; public IPTV M3Us overlap heavily) — every refresh **steals the row** into whichever playlist refreshed last. Combined with P0-1's concurrent waves, ownership ping-pongs nondeterministically.

**User-visible effects:**

- Disable playlist A → channels that also exist in enabled playlist B vanish or persist depending on who refreshed last (`_enabledFilter` checks the row's *current* owner).
- A playlist's own diff (`existing WHERE playlist_id = ?`) no longer sees the stolen URL → its bookkeeping is inconsistent across refreshes.
- `is_favorite` and `recently_watched` follow the stolen row to an arbitrary playlist.

**Fix options (in order of correctness):**

1. **Proper:** migrate to `UNIQUE(playlist_id, url)` (v9 migration: rebuild table, copy rows). `recently_watched`'s FK on `url` needs a decision (keep global-by-url is fine for watch history).
2. **Minimum:** drop `playlist_id=?` from the step-2 UPDATE so refresh can never re-parent, and document the "first playlist to store a URL owns it" invariant. Cheap, stops the ping-pong, but disabled-source filtering stays approximate for shared URLs.

Either way the invariant must become explicit — today it is implicit, undocumented, and load-order-dependent.

---

## 🟠 P1 — Design Problems / Dead Code

### P1-1. `channelCount` and `fetchError` are write-only state

**Files:** `lib/services/playlist_repository.dart`, `lib/providers/fetch_status_provider.dart`

- `PlaylistRepository.channelCount` — assigned in 5 places, **read nowhere** (grep-verified: no consumer outside the repository). Each assignment also costs a full `SELECT COUNT(*)` after every refresh wave. Delete the notifier and all 5 `channelCount.value = await _db.channelCount()` calls.
- `fetchErrorProvider` — defined in `fetch_status_provider.dart`, **never watched** by any widget. The entire `fetchError` notifier, the two "Couldn't fetch channels — check your connection." strings, and the failed-count bookkeeping in `refreshAllPlaylists` feed a UI that does not exist.

**Consequence:** all refresh failures are 100 % silent — which is exactly how P0-1 stayed hidden. Either surface `fetchError` in Home/Settings (a one-line banner) or delete the plumbing. Do not keep write-only observables.

### P1-2. `replaceChannels` rewrites the FTS index for every row on every refresh

**File:** `lib/core/db/database_service.dart` (`replaceChannels` + `channels_au` trigger)

The step-2 `UPDATE ... WHERE url=?` runs unconditionally for **all** channels, changed or not. Every row update fires the `channels_au` trigger → FTS delete + insert. A 10 k-channel playlist refresh = ~10 k row rewrites + ~20 k FTS index ops, on 1 GB Android-TV boxes, potentially while video is decoding (resume-triggered tflix refresh is guarded, but manual/stale refreshes are not).

**Fix:** make the UPDATE a no-op for unchanged rows:

```sql
UPDATE channels SET ... WHERE url=?
  AND (name IS NOT ? OR logo IS NOT ? OR group_name IS NOT ? OR id IS NOT ?)
```

(`search_text` is derived from name+group, so covered.) SQLite skips the trigger when zero rows match. One WHERE-clause change; no Dart diffing needed.

### P1-3. `PlaybackSession._load` can call `stop()` on a disposed player

**File:** `lib/features/player/playback_session.dart` (~line 226)

```dart
await player.open(Media(playable, httpHeaders: headers), play: true);
if (_disposed || gen != _loadGeneration) {
  player.stop();   // ← if _disposed, player.dispose() already ran
  return;
}
```

`dispose()` sets `_disposed = true` and then disposes the player while `_load` may be suspended inside `player.open(...)`. On resume, the `_disposed` branch calls `stop()` on a destroyed player — media_kit throws on disposed use → unhandled async error.

**Fix:** split the guard — `if (_disposed) return;` (player already dead) before the `gen != _loadGeneration → stop()` case (player alive, just superseded).

### P1-4. `_getLenient` duplicates the canonical `httpGetString`

**File:** `lib/services/streamcrichd_resolver.dart:~150`

A hand-rolled GET that differs from `http_get.dart`'s canonical helper only by additionally accepting HTTP 500 (fetch.php quirk). Bespoke near-duplicate of an existing canonical utility.

**Fix:** add a `bool lenient = false` (or `Set<int> extraOkStatuses`) param to `httpGetString`; delete `_getLenient`.

---

## 🟡 P2 — Minor Issues

### P2-1. `_seedAndRefresh`'s catch is unreachable-ish and misattributes errors

**File:** `lib/services/playlist_repository.dart` (`_seedAndRefresh`)

All four parallel flows swallow their own errors internally (`refreshTflixMatches` → bare catch; footmad → debugPrint; builtins fetch → returns `[]`; `refreshAllPlaylists` → per-playlist catch). The outer `catch (e) { fetchError.value = 'Couldn't fetch channels…' }` can fire only from the first-launch seed path (`addAndRefreshPlaylist` throws) — and then blames "connection" for any exception type, including `ArgumentError` on a bad seeded URL. Moot if P1-1 resolves by deleting `fetchError`; otherwise attribute honestly.

### P2-2. `parseM3uLines` streaming premise is dead

**File:** `lib/services/playlist_service.dart`

Doc says "Prefer this overload when the lines come from a streaming source" — no streaming caller exists; `parseM3u` is its only user. Collapse into one function (keep whichever signature the tests use).

### P2-3. Search paging can skip/duplicate rows during a background refresh

**File:** `lib/features/search/search_screen.dart`

`LIMIT/OFFSET` paging over a table being mutated by a concurrent refresh can skip or duplicate results between pages. Known, acceptable ceiling for a TV search box — but mark it with a `// ponytail:` comment so it reads as intent, not oversight.

### P2-4. Analyzer info

`lib/features/player/playback_session.dart:26` — `prefer_initializing_formals` (`this._repository`). Cosmetic; the explicit initializer list matches the surrounding style, waive or fix in passing.

---

## Observations (no action required)

- **`BackGuard` 600 ms swallow window** on Home mount means a fast legitimate double-back can't exit the app. Deliberate trade-off against TCL/Realtek key echo; documented in code.
- **`PersistedNotifier._load` race:** a `set()` racing the initial prefs load can be overwritten by the saved value. Window is milliseconds at app start; ignore.
- **Hardcoded `http://10.255.255.50`** (LocalIptvService) and AES key/IV in `FootmadService` — inherent to this app's personal-use scraping nature; already silently no-ops off-LAN.
- **`_streamcrichdChannelCount = 51` + seed-key bump mechanism** — manual but documented; fine.
- **No repository-level tests.** `PlaylistRepository` (the buggiest file per this audit) has zero coverage; all 55 tests target pure parsers/models. P0-1 and P0-2 would both have been caught by one fake-DB repository test asserting "N playlists → N replaceChannels calls" and "footmad channels stored after bootstrap". Recommend adding exactly those two when fixing.

---

## ✅ Strengths

- **`StreamResolver` dispatch table** — one entry per resolver, `isResolvable`/`resolve` can't drift apart.
- **`PlaybackSession` extraction** — generation-guarded async, watchdog, auto-skip and expiry-refresh all testable without a widget tree; dispose ordering documented.
- **`PersistedNotifier`** — one small base class instead of three copy-pasted prefs notifiers.
- **Granular `DebouncedVersion` notifiers** — dashboard sections rebuild independently; `markWatched` doesn't rebuild the world.
- **Pure, unit-tested parsers** (M3U, tflix, streamcrichd, iptvidn) separated from I/O.
- **File sizes healthy** — largest file 637 lines; no decomposition debt.
- **Comments explain *why*** (SQLite version constraints, Amlogic quirks, TV firmware back-echo), and deliberate ceilings are marked `ponytail:`.

---

## Recommended Fix Order

| # | Fix | Effort | Risk |
|---|-----|--------|------|
| 1 | P0-1: delete `_activeClient`/`cancel()`, per-call client | ~15 lines deleted | None — pattern already used by 4 sibling services |
| 2 | P0-2: move `last_refreshed_at` write to post-`replaceChannels` | ~10 lines moved | Low — one column, one meaning |
| 3 | P1-1: delete `channelCount`; wire or delete `fetchError` | Deletion | None |
| 4 | P1-3: split disposed/superseded guard in `_load` | 3 lines | None |
| 5 | P1-2: change-guard on `replaceChannels` UPDATE | 1 SQL clause | Low |
| 6 | P0-3: decide per-playlist uniqueness (v9 migration) or de-parent UPDATE | Migration or 1 line | Medium (migration) / Low (minimum fix) |
| 7 | P1-4, P2-x | Trivial | None |

Items 1–2 are **blockers**: the app's refresh pipeline does not do what it claims for any multi-source configuration, and the failures are silent by construction.
