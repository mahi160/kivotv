import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/channel.dart';
import '../../models/playlist.dart';

class DatabaseService {
  DatabaseService._({this._testDbPath});

  static final DatabaseService instance = DatabaseService._();

  /// Isolated instance for tests — bypasses the app-wide singleton and its
  /// cached connection so each test gets its own database instead of sharing
  /// (and accumulating state in) [instance]'s. Defaults to an in-memory
  /// SQLite database, so tests never touch disk or leak into each other.
  @visibleForTesting
  factory DatabaseService.forTesting({String dbPath = ':memory:'}) =>
      DatabaseService._(testDbPath: dbPath);

  final String? _testDbPath;

  Database? _db;

  // Cached FTS availability — checked once on first search, then re-used.
  // null = not yet checked, true/false = result.
  bool? _ftsEnabled;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;

    final dbPath = _testDbPath ?? p.join(await getDatabasesPath(), 'kivo.db');
    final opened = await openDatabase(
      dbPath,
      version: 9,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
      onCreate: (db, _) => _createSchema(db),
      onUpgrade: (db, oldVersion, _) async {
        // v1 → v2: added is_pinned, is_broken, recently_watched table.
        // is_broken column stays in old DBs (can't DROP COLUMN in old SQLite)
        // but is no longer read or written by the app as of v4.
        if (oldVersion < 2) {
          await _addColumnIfMissing(
            db,
            'channels',
            'is_pinned',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _addColumnIfMissing(
            db,
            'channels',
            'is_broken',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('''
CREATE TABLE IF NOT EXISTS recently_watched (
  channel_url TEXT PRIMARY KEY,
  watched_at  INTEGER NOT NULL,
  FOREIGN KEY (channel_url) REFERENCES channels (url) ON DELETE CASCADE
)''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_recent_watched_at'
            ' ON recently_watched(watched_at DESC)',
          );
        }
        // v2 → v3: added is_favorite.
        if (oldVersion < 3) {
          await _addColumnIfMissing(
            db,
            'channels',
            'is_favorite',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_channels_favorite'
            ' ON channels(is_favorite)',
          );
        }
        // v3 → v4: removed broken-channel tracking from the app layer.
        // The is_broken column is left in existing DBs but ignored.
        // Clear any leftover flags so those channels become visible again.
        if (oldVersion < 4) {
          await db.execute(
            'UPDATE channels SET is_broken = 0 WHERE is_broken = 1',
          );
        }
        // v4 → v5: composite index so channelsByGroup() ORDER BY group_name,
        // name can use an index scan instead of sorting all rows in memory.
        // On a 10 k-channel playlist this eliminates the filesort on every
        // home-screen load.
        if (oldVersion < 5) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_channels_group_name'
            ' ON channels(group_name COLLATE NOCASE, name COLLATE NOCASE)',
          );
        }
        // v5 → v6: FTS5 virtual table for fast full-text search.
        // Replaces the O(n) `LIKE '%query%'` scan (leading wildcard kills the
        // index) with an O(log n) FTS index query. The content table is backed
        // by `channels`, so it stores only the inverted index, not the text.
        // Requires SQLite 3.9+ / Android 7+. Gracefully skipped on older
        // devices — search falls back to LIKE automatically.
        if (oldVersion < 6) {
          try {
            await db.execute(_ftsCreateSql);
            // Populate the index from existing rows.
            await db.execute(
              "INSERT INTO channels_fts(channels_fts) VALUES('rebuild')",
            );
          } catch (_) {
            // FTS5 unavailable — hasFts() will return false and search
            // transparently falls back to the old LIKE path.
          }
        }
        // v6 → v7: FTS5 triggers — incremental index maintenance. Existing FTS
        // data stays valid; the triggers keep it in sync going forward so
        // replaceChannels no longer needs a full 'rebuild' after every write.
        if (oldVersion < 7) {
          final hasFts = (await db.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='channels_fts' LIMIT 1",
          )).isNotEmpty;
          if (hasFts) {
            try {
              await db.execute(_ftsAiTriggerSql);
              await db.execute(_ftsAdTriggerSql);
              await db.execute(_ftsAuTriggerSql);
            } catch (_) {}
          }
        }
        // v7 → v8: source toggle — enabled column on playlists.
        if (oldVersion < 8) {
          await _addColumnIfMissing(
            db,
            'playlists',
            'enabled',
            'INTEGER NOT NULL DEFAULT 1',
          );
        }
        // v8 → v9: channel_playlists join table. `channels.url` is globally
        // UNIQUE and stays that way (one metadata row per URL, owned by
        // whichever playlist first stored it — see replaceChannels), but the
        // *same URL* can legitimately be listed by more than one playlist
        // (public IPTV lists overlap; FootMad categories can share a feed).
        // Before this table existed, a channel's visibility was tied only to
        // its single metadata owner's enabled state, so disabling the owner
        // hid the channel even if another enabled playlist also listed it.
        // channel_playlists records every (url, playlist_id) pair each
        // playlist's latest refresh actually saw, independent of metadata
        // ownership; _enabledFilter now checks this table instead of the
        // owner's playlist_id directly (see AUDIT.md P0-3).
        if (oldVersion < 9) {
          await db.execute(_channelPlaylistsCreateSql);
          await db.execute(_channelPlaylistsIndexSql);
          // Backfill: each existing row's current (single) owner becomes its
          // first membership entry. Any other playlist that also lists the
          // same url reclaims membership the next time it refreshes.
          await db.execute(
            'INSERT OR IGNORE INTO channel_playlists (channel_url, playlist_id)'
            ' SELECT url, playlist_id FROM channels',
          );
        }
      },
    );
    _db = opened;
    // Best-effort performance tuning. Silently ignored on devices whose
    // SQLite build doesn't support WAL (returns 'delete' instead of 'wal')
    // or rejects cache_size — DB still works with default settings.
    try {
      await opened.rawQuery('PRAGMA journal_mode=WAL');
      await opened.execute('PRAGMA synchronous=NORMAL');
      await opened.execute('PRAGMA cache_size=-8000');
    } catch (_) {}
    return opened;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE playlists (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT    NOT NULL,
  url               TEXT    NOT NULL UNIQUE,
  last_refreshed_at INTEGER,
  enabled           INTEGER NOT NULL DEFAULT 1
)''');
    // is_pinned / is_broken were dropped from the app layer; new installs
    // never create those columns (legacy DBs keep them, harmlessly ignored).
    await db.execute('''
CREATE TABLE channels (
  id          TEXT    NOT NULL,
  playlist_id INTEGER NOT NULL,
  name        TEXT    NOT NULL,
  url         TEXT    NOT NULL UNIQUE,
  logo        TEXT,
  group_name  TEXT,
  search_text TEXT    NOT NULL,
  is_favorite INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE
)''');
    await db.execute('''
CREATE TABLE recently_watched (
  channel_url TEXT PRIMARY KEY,
  watched_at  INTEGER NOT NULL,
  FOREIGN KEY (channel_url) REFERENCES channels (url) ON DELETE CASCADE
)''');
    await db.execute(_channelPlaylistsCreateSql);
    await db.execute(_channelPlaylistsIndexSql);
    await db.execute('CREATE INDEX idx_channels_name      ON channels(name)');
    await db.execute(
      'CREATE INDEX idx_channels_group     ON channels(group_name)',
    );
    // Composite index for ORDER BY group_name, name (home dashboard).
    await db.execute(
      'CREATE INDEX idx_channels_group_name'
      ' ON channels(group_name COLLATE NOCASE, name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE INDEX idx_channels_search    ON channels(search_text)',
    );
    await db.execute(
      'CREATE INDEX idx_channels_favorite  ON channels(is_favorite)',
    );
    await db.execute(
      'CREATE INDEX idx_recent_watched_at ON recently_watched(watched_at DESC)',
    );
    // FTS5 virtual table + sync triggers. Skipped gracefully when FTS5 is
    // unavailable (SQLite < 3.9 / Android < 7) — search falls back to LIKE.
    try {
      await db.execute(_ftsCreateSql);
      await db.execute(_ftsAiTriggerSql);
      await db.execute(_ftsAdTriggerSql);
      await db.execute(_ftsAuTriggerSql);
    } catch (_) {}
  }

  // Join table recording which playlists currently list which channel URLs —
  // see the v8 → v9 migration comment above for why this exists alongside
  // channels.playlist_id (metadata ownership vs. visibility).
  static const _channelPlaylistsCreateSql = '''
CREATE TABLE IF NOT EXISTS channel_playlists (
  channel_url TEXT    NOT NULL,
  playlist_id INTEGER NOT NULL,
  PRIMARY KEY (channel_url, playlist_id),
  FOREIGN KEY (channel_url) REFERENCES channels (url) ON DELETE CASCADE,
  FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE
)''';
  static const _channelPlaylistsIndexSql =
      'CREATE INDEX IF NOT EXISTS idx_channel_playlists_playlist'
      ' ON channel_playlists(playlist_id)';

  // FTS5 virtual table definition. Content table = channels, so FTS5 reads
  // the actual text by rowid from `channels` and stores only the index.
  static const _ftsCreateSql = '''
CREATE VIRTUAL TABLE IF NOT EXISTS channels_fts USING fts5(
  search_text,
  content='channels',
  content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 1'
)''';

  // FTS5 content-table sync triggers. Keep these in sync with _createSchema.
  // INSERT: add new row to the FTS index.
  // DELETE: remove the row from the index.
  // UPDATE: remove old entry then add the new one (handles search_text changes).
  static const _ftsAiTriggerSql = '''
CREATE TRIGGER IF NOT EXISTS channels_ai AFTER INSERT ON channels BEGIN
  INSERT INTO channels_fts(rowid, search_text) VALUES (new.rowid, new.search_text);
END''';

  static const _ftsAdTriggerSql = '''
CREATE TRIGGER IF NOT EXISTS channels_ad AFTER DELETE ON channels BEGIN
  INSERT INTO channels_fts(channels_fts, rowid, search_text) VALUES('delete', old.rowid, old.search_text);
END''';

  static const _ftsAuTriggerSql = '''
CREATE TRIGGER IF NOT EXISTS channels_au AFTER UPDATE ON channels BEGIN
  INSERT INTO channels_fts(channels_fts, rowid, search_text) VALUES('delete', old.rowid, old.search_text);
  INSERT INTO channels_fts(rowid, search_text) VALUES (new.rowid, new.search_text);
END''';

  /// SQL fragment restricting channel rows to ones listed by at least one
  /// enabled playlist. [prefix] is the table-alias dot-prefix for the `url`
  /// column being compared (e.g. `_enabledFilter('c.')` when the query
  /// aliases channels as `c`). Defaults to the real table name, `channels.`
  /// — NOT `''` — because the subquery's own `playlists` table also has a
  /// `url` column; a bare, unqualified `url` reference would resolve to
  /// `playlists.url` (the innermost matching scope) instead of correlating
  /// out to the intended channels row, silently matching nothing.
  ///
  /// A channel row's own `playlist_id` is only its *metadata owner* (see
  /// [replaceChannels]) — the same url can also be listed by other playlists
  /// via `channel_playlists`, and any one of them being enabled is enough to
  /// keep the channel visible. This is what stops disabling the metadata
  /// owner from hiding a url another enabled playlist also lists.
  static String _enabledFilter([String prefix = 'channels.']) =>
      'EXISTS (SELECT 1 FROM channel_playlists cp'
      ' JOIN playlists p ON p.id = cp.playlist_id'
      ' WHERE cp.channel_url = ${prefix}url AND p.enabled = 1)';

  /// True if the FTS5 table exists in this database (SQLite 3.9+ / Android 7+).
  /// Result is cached after the first check.
  Future<bool> _hasFts() async {
    if (_ftsEnabled != null) return _ftsEnabled!;
    final db = await database;
    final r = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='channels_fts' LIMIT 1",
    );
    return _ftsEnabled = r.isNotEmpty;
  }

  /// Converts user input into an FTS5 MATCH query with per-word prefix
  /// wildcards. Each space-separated token gets a trailing `*`, so typing
  /// "bbc" matches "BBC One", "BBC News", "BBC World", etc.
  /// Special FTS5 characters are neutralised by double-quoting each token.
  static String _ftsQuery(String input) {
    final tokens = input
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        // Strip characters that have FTS5 syntax meaning outside quotes.
        .map((t) => t.replaceAll('"', ''))
        .where((t) => t.isNotEmpty)
        .map((t) => '"$t"*') // quoted token + prefix wildcard
        .toList();
    return tokens.join(' '); // implicit AND between tokens
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  // ── Playlists ──────────────────────────────────────────────────────────────

  Future<void> setPlaylistEnabled(int id, {required bool enabled}) async {
    final db = await database;
    await db.update(
      'playlists',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Upserts a playlist row's identity (name/url/enabled default).
  /// Does NOT touch [Playlist.lastRefreshedAt] — that column means "channels
  /// were last stored for this playlist" and is stamped only by
  /// [replaceChannels], which is the only place channels actually get
  /// written. Stamping it here (as this used to) marked a playlist "fresh"
  /// before any channel had been fetched, which broke the staleness check
  /// that gates auto-refresh.
  Future<int> upsertPlaylist({
    required String name,
    required String url,
    bool defaultEnabled = true, // only applied on INSERT; existing rows keep their enabled state
  }) async {
    final db = await database;
    await db.insert('playlists', {
      'name': name,
      'url': url,
      'enabled': defaultEnabled ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update(
      'playlists',
      {'name': name},
      where: 'url = ?',
      whereArgs: [url],
    );
    final rows = await db.query(
      'playlists',
      columns: ['id'],
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    return rows.single['id'] as int;
  }

  Future<void> deletePlaylistById(int id) => _deletePlaylist('id', id);

  Future<void> deletePlaylistByUrl(String url) =>
      _deletePlaylist('url', url);

  /// Deletes the playlist matched by [column] = [value]. Channels *owned* by
  /// it (see [replaceChannels]) are removed by the ON DELETE CASCADE foreign
  /// key — including a channel another, still-enabled playlist also lists via
  /// `channel_playlists`, since that row's metadata has nowhere else to live.
  /// Not currently reachable from the UI (Settings only ever toggles
  /// [setPlaylistEnabled]); if a "remove playlist" action is added, ownership
  /// should be handed to a remaining member of `channel_playlists` before
  /// this delete runs, instead of losing the row.
  Future<void> _deletePlaylist(String column, Object value) async {
    final db = await database;
    await db.delete('playlists', where: '$column = ?', whereArgs: [value]);
  }

  Future<List<Playlist>> playlists() async {
    final db = await database;
    final rows = await db.query(
      'playlists',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Playlist.fromDb).toList();
  }

  // ── Channels — replace (diff-upsert) ──────────────────────────────────────

  /// Reconciles stored channels for [playlistId] with the new [channels] list.
  /// Deletes only URLs that disappeared upstream; upserts the rest in-place so
  /// is_favorite / recently_watched history are preserved.
  ///
  /// `channels.url` is globally UNIQUE, so a URL already stored under a
  /// *different* playlist is left untouched here — the first playlist to
  /// store a URL owns its metadata; refresh never re-parents or overwrites it
  /// away from that owner (see the step-2 UPDATE below). Separately, this
  /// playlist's own claim on every url in [channels] is recorded in
  /// `channel_playlists` regardless of who owns the metadata — that's what
  /// [_enabledFilter] checks for visibility, so a url another playlist owns
  /// stays visible through *this* playlist too, independent of the owner's
  /// enabled state.
  Future<void> replaceChannels({
    required int playlistId,
    required List<Channel> channels,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final newUrls = {for (final c in channels) c.url};

      final existing = await txn.query(
        'channels',
        columns: ['url'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      final toDelete = [
        for (final row in existing)
          if (!newUrls.contains(row['url'] as String)) row['url'] as String,
      ];
      await _deleteStaleUrls(txn, table: 'channels', urlColumn: 'url', staleUrls: toDelete);

      // This playlist's own channel_playlists membership diffs the same way:
      // drop urls it no longer lists, upsert the rest below.
      final existingMembership = await txn.query(
        'channel_playlists',
        columns: ['channel_url'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      final staleMembership = [
        for (final row in existingMembership)
          if (!newUrls.contains(row['channel_url'] as String))
            row['channel_url'] as String,
      ];
      await _deleteStaleUrls(
        txn,
        table: 'channel_playlists',
        urlColumn: 'channel_url',
        staleUrls: staleMembership,
        extraWhere: 'playlist_id = ?',
        extraWhereArgs: [playlistId],
      );

      // Two-step upsert compatible with all SQLite versions (no 3.24+ upsert
      // syntax needed). INSERT OR IGNORE adds new rows; UPDATE refreshes
      // metadata on existing rows. is_favorite is never touched by either.
      final batch = txn.batch();
      for (final channel in channels) {
        final data = channel.toDb(playlistId: playlistId);
        // Step 1: insert if not already present (conflict = skip).
        batch.rawInsert(
          'INSERT OR IGNORE INTO channels'
          ' (id, playlist_id, name, url, logo, group_name, search_text, is_favorite)'
          ' VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            data['id'], data['playlist_id'], data['name'], data['url'],
            data['logo'], data['group_name'], data['search_text'],
            data['is_favorite'],
          ],
        );
        // Step 2: refresh metadata for rows that already existed *under this
        // playlist*. The `AND playlist_id=?` guard is deliberate: `url` is
        // globally UNIQUE, so the same stream URL can legitimately appear in
        // two playlists' upstream data (public IPTV lists overlap heavily).
        // Without this guard, whichever playlist refreshes last would
        // silently re-parent the row (playlist_id=?, plus overwrite its
        // metadata) away from the playlist that first stored it — disabling
        // one playlist could then hide a channel that another enabled
        // playlist also lists. First-to-store-a-URL owns it; refresh never
        // steals it. is_favorite is intentionally excluded so user choices
        // survive a playlist refresh.
        //
        // The trailing WHERE clause also makes this a no-op for unchanged
        // rows — every UPDATE that actually runs fires the channels_au FTS
        // trigger (delete+insert), so on a large playlist where most rows are
        // identical to last refresh, matching them out here avoids rewriting
        // the whole FTS index for nothing.
        batch.rawUpdate(
          'UPDATE channels'
          ' SET id=?, name=?, logo=?, group_name=?, search_text=?'
          ' WHERE url=? AND playlist_id=?'
          ' AND (id IS NOT ? OR name IS NOT ? OR logo IS NOT ?'
          ' OR group_name IS NOT ? OR search_text IS NOT ?)',
          [
            data['id'], data['name'],
            data['logo'], data['group_name'], data['search_text'],
            data['url'], data['playlist_id'],
            data['id'], data['name'],
            data['logo'], data['group_name'], data['search_text'],
          ],
        );
        // Step 3: record this playlist's claim on the url regardless of who
        // owns its metadata (steps 1–2 above). Idempotent — the composite
        // PK already prevents duplicates and there's no metadata to refresh.
        batch.rawInsert(
          'INSERT OR IGNORE INTO channel_playlists (channel_url, playlist_id)'
          ' VALUES (?, ?)',
          [data['url'], playlistId],
        );
      }
      await batch.commit(noResult: true);

      // Stamp "refreshed now" only when channels were actually stored for
      // this playlist — same transaction, so a crash between the two can't
      // leave a stale timestamp paired with fresh data or vice versa.
      await txn.update(
        'playlists',
        {'last_refreshed_at': now},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    });

    // FTS index is kept in sync automatically by the triggers added in v7.
  }

  /// Deletes rows from [table] whose [urlColumn] value is in [staleUrls],
  /// chunked to stay under SQLite's default per-statement variable limit.
  /// [extraWhere]/[extraWhereArgs] add an additional AND condition (e.g.
  /// scoping the delete to one playlist_id). Shared by the two diff-deletes
  /// in [replaceChannels] (owned channel rows, and this playlist's own
  /// channel_playlists membership).
  Future<void> _deleteStaleUrls(
    Transaction txn, {
    required String table,
    required String urlColumn,
    required List<String> staleUrls,
    String? extraWhere,
    List<Object?> extraWhereArgs = const [],
  }) async {
    const chunkSize = 500;
    for (var i = 0; i < staleUrls.length; i += chunkSize) {
      final slice = staleUrls.sublist(i, math.min(i + chunkSize, staleUrls.length));
      final placeholders = List.filled(slice.length, '?').join(',');
      final extra = extraWhere != null ? ' AND $extraWhere' : '';
      await txn.rawDelete(
        'DELETE FROM $table WHERE $urlColumn IN ($placeholders)$extra',
        [...slice, ...extraWhereArgs],
      );
    }
  }

  // ── Channels — queries ─────────────────────────────────────────────────────

  Future<int> channelCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS count FROM channels');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Channel>> channels({
    String query = '',
    String? group,
    int limit = 100,
    int offset = 0,
    bool sortAlpha = true,
  }) async {
    final db = await database;
    final normalizedQuery = query.trim().toLowerCase();
    final where = <String>[];
    final args = <Object?>[];

    // Always restrict to channels listed by at least one enabled playlist.
    where.add(_enabledFilter());

    if (normalizedQuery.isNotEmpty) {
      final ftsQ = _ftsQuery(normalizedQuery);
      if (ftsQ.isEmpty) return []; // no valid tokens — bail early
      if (await _hasFts()) {
        // FTS5 prefix query: O(log n) index lookup instead of O(n) table scan.
        // rowid IN (subquery) is optimised by SQLite as a semi-join.
        where.add(
          'rowid IN (SELECT rowid FROM channels_fts WHERE channels_fts MATCH ?)',
        );
        args.add(ftsQ);
      } else {
        // Fallback for devices without FTS5 (SQLite < 3.9 / Android < 7).
        where.add(r"search_text LIKE ? ESCAPE '\'");
        args.add('%${_escapeLike(normalizedQuery)}%');
      }
    }

    if (group != null && group.isNotEmpty) {
      where.add('group_name = ?');
      args.add(group);
    }

    final rows = await db.query(
      'channels',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      // sortAlpha: group → name A–Z. Provider order: M3U insertion order (rowid).
      orderBy: sortAlpha
          ? 'group_name IS NULL, group_name COLLATE NOCASE ASC, '
              'name COLLATE NOCASE ASC'
          : 'rowid ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Channel.fromDb).toList();
  }

  /// Top [groupLimit] groups by channel count, each capped at [perGroupLimit]
  /// channels, for the Netflix-style Home rows.
  ///
  /// [excludeUrlPrefix] hides channels whose reference starts with it (e.g.
  /// live matches, which have their own dashboard row) — the caller decides
  /// which scheme that is; this layer has no feature-specific knowledge of it.
  ///
  /// Deliberately avoids SQLite window functions (ROW_NUMBER OVER) so it
  /// works on every Android SQLite build including older OEM builds that
  /// ship SQLite < 3.25. Per-group capping is done in Dart after the query.
  Future<List<MapEntry<String, List<Channel>>>> channelsByGroup({
    String? excludeUrlPrefix,
    int groupLimit = 15,
    int perGroupLimit = 30,
  }) async {
    final db = await database;

    // Empty/null groups collapse into 'Other'.
    const groupExpr = "COALESCE(NULLIF(group_name, ''), 'Other')";
    const groupExprC = "COALESCE(NULLIF(c.group_name, ''), 'Other')";
    final notLiveMatch = excludeUrlPrefix == null ? '1=1' : 'url NOT LIKE ?';
    final notLiveMatchC = excludeUrlPrefix == null ? '1=1' : 'c.url NOT LIKE ?';
    final excludeArg = excludeUrlPrefix == null ? null : '$excludeUrlPrefix%';

    // Single query: inline the top-groups subquery so we avoid a second
    // round-trip to SQLite. The subquery is cheap (one index scan) and
    // SQLite caches it inside the same statement.
    final rows = await db.rawQuery(
      '''
SELECT c.*,
       $groupExprC AS _g
FROM   channels c
WHERE  $notLiveMatchC
  AND  ${_enabledFilter('c.')}
  AND  $groupExprC IN (
         SELECT $groupExpr AS _g
         FROM   channels
         WHERE  $notLiveMatch
           AND  ${_enabledFilter()}
         GROUP  BY _g
         ORDER  BY COUNT(*) DESC
         LIMIT  ?
       )
ORDER  BY $groupExprC COLLATE NOCASE ASC,
          c.name COLLATE NOCASE ASC
''',
      [?excludeArg, ?excludeArg, groupLimit],
    );
    if (rows.isEmpty) return [];

    // Group in Dart and cap each bucket at perGroupLimit.
    final groupMap = <String, List<Channel>>{};
    for (final row in rows) {
      final g = row['_g'] as String;
      final list = groupMap[g] ??= [];
      if (list.length < perGroupLimit) list.add(Channel.fromDb(row));
    }

    // Other pushed last; remainder in the order returned by step 1 (desc count).
    return (groupMap.entries.toList()
      ..sort((a, b) {
        if (a.key == 'Other' && b.key != 'Other') return 1;
        if (b.key == 'Other' && a.key != 'Other') return -1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      }));
  }

  Future<List<Channel>> favoriteChannels({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'channels',
      where: 'is_favorite = 1 AND ${_enabledFilter()}',
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(Channel.fromDb).toList();
  }

  /// Channels shown in the "Live Now" dashboard row — those whose reference
  /// starts with [urlPrefix] (the caller owns which scheme that is).
  Future<List<Channel>> liveMatches({
    required String urlPrefix,
    int limit = 40,
  }) async {
    final db = await database;
    final rows = await db.query(
      'channels',
      where: 'url LIKE ? AND ${_enabledFilter()}',
      whereArgs: ['$urlPrefix%'],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(Channel.fromDb).toList();
  }

  Future<List<Channel>> recentlyWatched({int limit = 12}) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
SELECT channels.*
FROM   recently_watched
JOIN   channels ON channels.url = recently_watched.channel_url
WHERE  ${_enabledFilter('channels.')}
ORDER  BY recently_watched.watched_at DESC
LIMIT  ?
''',
      [limit],
    );
    return rows.map(Channel.fromDb).toList();
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> setFavorite(String channelUrl, bool favorite) async {
    final db = await database;
    await db.update(
      'channels',
      {'is_favorite': favorite ? 1 : 0},
      where: 'url = ?',
      whereArgs: [channelUrl],
    );
  }

  Future<void> updateChannelName(String channelUrl, String name) async {
    final db = await database;
    await db.update(
      'channels',
      {'name': name, 'search_text': name.toLowerCase()},
      where: 'url = ?',
      whereArgs: [channelUrl],
    );
  }

  Future<void> markWatched(String channelUrl) async {
    final db = await database;
    await db.insert('recently_watched', {
      'channel_url': channelUrl,
      'watched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Most-recent watch timestamp. Used by auto-open to skip resumption after
  /// a long idle period.
  Future<DateTime?> lastWatchedAt() async {
    final db = await database;
    final rows = await db.query(
      'recently_watched',
      columns: ['watched_at'],
      orderBy: 'watched_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      rows.first['watched_at'] as int,
    );
  }

  String _escapeLike(String input) => input
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
