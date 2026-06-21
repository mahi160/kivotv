import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/channel.dart';
import '../../models/playlist.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  // Cached FTS availability — checked once on first search, then re-used.
  // null = not yet checked, true/false = result.
  bool? _ftsEnabled;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;

    final dbPath = p.join(await getDatabasesPath(), 'kivo.db');
    final opened = await openDatabase(
      dbPath,
      version: 6,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate:    (db, _) => _createSchema(db),
      onUpgrade: (db, oldVersion, _) async {
        // v1 → v2: added is_pinned, is_broken, recently_watched table.
        // is_broken column stays in old DBs (can't DROP COLUMN in old SQLite)
        // but is no longer read or written by the app as of v4.
        if (oldVersion < 2) {
          await _addColumnIfMissing(
              db, 'channels', 'is_pinned', 'INTEGER NOT NULL DEFAULT 0');
          await _addColumnIfMissing(
              db, 'channels', 'is_broken', 'INTEGER NOT NULL DEFAULT 0');
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
              db, 'channels', 'is_favorite', 'INTEGER NOT NULL DEFAULT 0');
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
              'UPDATE channels SET is_broken = 0 WHERE is_broken = 1');
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
                "INSERT INTO channels_fts(channels_fts) VALUES('rebuild')");
          } catch (_) {
            // FTS5 unavailable — hasFts() will return false and search
            // transparently falls back to the old LIKE path.
          }
        }
      },
    );
    _db = opened;
    return opened;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE playlists (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  name             TEXT    NOT NULL,
  url              TEXT    NOT NULL UNIQUE,
  last_refreshed_at INTEGER
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
    await db.execute('CREATE INDEX idx_channels_name      ON channels(name)');
    await db.execute('CREATE INDEX idx_channels_group     ON channels(group_name)');
    // Composite index for ORDER BY group_name, name (home dashboard).
    await db.execute(
      'CREATE INDEX idx_channels_group_name'
      ' ON channels(group_name COLLATE NOCASE, name COLLATE NOCASE)',
    );
    await db.execute('CREATE INDEX idx_channels_search    ON channels(search_text)');
    await db.execute('CREATE INDEX idx_channels_favorite  ON channels(is_favorite)');
    await db.execute(
      'CREATE INDEX idx_recent_watched_at ON recently_watched(watched_at DESC)');
    // FTS5 virtual table — backed by channels (stores only the inverted index).
    try {
      await db.execute(_ftsCreateSql);
    } catch (_) {
      // Gracefully skipped on SQLite < 3.9 / Android < 7.
    }
  }

  // FTS5 virtual table definition. Content table = channels, so FTS5 reads
  // the actual text by rowid from `channels` and stores only the index.
  static const _ftsCreateSql = '''
CREATE VIRTUAL TABLE IF NOT EXISTS channels_fts USING fts5(
  search_text,
  content='channels',
  content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 1'
)''';

  /// True if the FTS5 table exists in this database (SQLite 3.9+ / Android 7+).
  /// Result is cached after the first check.
  Future<bool> _hasFts() async {
    if (_ftsEnabled != null) return _ftsEnabled!;
    final db = await database;
    final r  = await db.rawQuery(
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
        .map((t) => '"$t"*')   // quoted token + prefix wildcard
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
    final exists  = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  // ── Playlists ──────────────────────────────────────────────────────────────

  Future<int> upsertPlaylist({
    required String name,
    required String url,
  }) async {
    final db  = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'playlists',
      {'name': name, 'url': url, 'last_refreshed_at': now},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update(
      'playlists',
      {'name': name, 'last_refreshed_at': now},
      where: 'url = ?', whereArgs: [url],
    );
    final rows = await db.query(
      'playlists', columns: ['id'], where: 'url = ?',
      whereArgs: [url], limit: 1,
    );
    return rows.single['id'] as int;
  }

  Future<List<Playlist>> playlists() async {
    final db   = await database;
    final rows = await db.query('playlists',
        orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Playlist.fromDb).toList();
  }

  // ── Channels — replace (diff-upsert) ──────────────────────────────────────

  /// Reconciles stored channels for [playlistId] with the new [channels] list.
  /// Deletes only URLs that disappeared upstream; upserts the rest in-place so
  /// is_favorite / recently_watched history are preserved.
  Future<void> replaceChannels({
    required int          playlistId,
    required List<Channel> channels,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final newUrls = {for (final c in channels) c.url};

      final existing = await txn.query(
        'channels', columns: ['url'],
        where: 'playlist_id = ?', whereArgs: [playlistId],
      );
      final toDelete = [
        for (final row in existing)
          if (!newUrls.contains(row['url'] as String)) row['url'] as String,
      ];

      const chunkSize = 500;
      for (var i = 0; i < toDelete.length; i += chunkSize) {
        final slice        = toDelete.sublist(i, math.min(i + chunkSize, toDelete.length));
        final placeholders = List.filled(slice.length, '?').join(',');
        await txn.rawDelete(
            'DELETE FROM channels WHERE url IN ($placeholders)', slice);
      }

      final batch = txn.batch();
      for (final channel in channels) {
        final data = channel.toDb(playlistId: playlistId);
        batch.rawInsert(
          '''
INSERT INTO channels
  (id, playlist_id, name, url, logo, group_name, search_text, is_favorite)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(url) DO UPDATE SET
  id          = excluded.id,
  playlist_id = excluded.playlist_id,
  name        = excluded.name,
  logo        = excluded.logo,
  group_name  = excluded.group_name,
  search_text = excluded.search_text
''',
          [
            data['id'],  data['playlist_id'], data['name'], data['url'],
            data['logo'], data['group_name'], data['search_text'],
            data['is_favorite'],
          ],
        );
      }
      await batch.commit(noResult: true);
    });

    // Rebuild the FTS index to reflect the updated channel rows.
    // Runs outside the transaction so it doesn't block channel reads.
    // Non-fatal: a rebuild failure leaves FTS slightly stale until the
    // next replaceChannels call; search falls back to LIKE if FTS fails.
    if (await _hasFts()) {
      try {
        final db = await database;
        await db.execute(
            "INSERT INTO channels_fts(channels_fts) VALUES('rebuild')");
      } catch (_) {
        _ftsEnabled = false; // disable FTS if the rebuild itself fails
      }
    }
  }

  // ── Channels — queries ─────────────────────────────────────────────────────

  Future<int> channelCount() async {
    final db     = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS count FROM channels');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Channel>> channels({
    String  query  = '',
    String? group,
    int     limit  = 100,
    int     offset = 0,
  }) async {
    final db              = await database;
    final normalizedQuery = query.trim().toLowerCase();
    final where           = <String>[];
    final args            = <Object?>[];

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
      where:     where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty  ? null : args,
      // Cluster by category (grouped channels first, A–Z within each group;
      // ungrouped last) rather than one flat alphabetical list.
      orderBy:   'group_name IS NULL, group_name COLLATE NOCASE ASC, '
                 'name COLLATE NOCASE ASC',
      limit:     limit,
      offset:    offset,
    );
    return rows.map(Channel.fromDb).toList();
  }

  /// All non-tflix channels grouped by category, for the Netflix-style Home
  /// rows. Each group's channels are A–Z; groups are ordered biggest-first,
  /// with ungrouped channels collected under "Other" and pushed to the end.
  /// (tflix live matches are excluded — they have their own "Live now" row.)
  ///
  /// [perGroupLimit] caps how many channels appear per group in the home
  /// dashboard. The full list is always accessible via Search. Capping here
  /// avoids creating thousands of Dart Channel objects on every dashboard
  /// rebuild when large playlists (e.g. 10 k+ channels) are installed.
  Future<List<MapEntry<String, List<Channel>>>> channelsByGroup({
    int perGroupLimit = 30,
  }) async {
    final db = await database;
    // ORDER BY group then name so per-group truncation is alphabetically stable
    // and channels are contiguous per group in the result cursor.
    final rows = await db.query(
      'channels',
      where:   "url NOT LIKE 'tflix://%'",
      orderBy: 'group_name COLLATE NOCASE ASC, name COLLATE NOCASE ASC',
    );
    final byGroup = <String, List<Channel>>{};
    for (final row in rows) {
      // Read the raw field (cheap map lookup) before deciding whether to
      // allocate a full Channel object — avoids O(n) allocations for large
      // playlists when most channels exceed the per-group cap.
      final rawGroup = row['group_name'] as String?;
      final g = (rawGroup == null || rawGroup.isEmpty) ? 'Other' : rawGroup;
      final list = (byGroup[g] ??= <Channel>[]);
      if (list.length < perGroupLimit) list.add(Channel.fromDb(row));
    }
    final entries = byGroup.entries.toList()
      ..sort((a, b) {
        final ao = a.key == 'Other' ? 1 : 0;
        final bo = b.key == 'Other' ? 1 : 0;
        if (ao != bo) return ao - bo;            // Other last
        return b.value.length.compareTo(a.value.length); // biggest first
      });
    return entries;
  }

  Future<List<Channel>> favoriteChannels({int limit = 12}) async {
    final db   = await database;
    final rows = await db.query(
      'channels',
      where:   'is_favorite = 1',
      orderBy: 'name COLLATE NOCASE ASC',
      limit:   limit,
    );
    return rows.map(Channel.fromDb).toList();
  }

  /// Live matches scraped from tflix (their refs use the `tflix://` scheme).
  Future<List<Channel>> liveMatches({int limit = 40}) async {
    final db   = await database;
    final rows = await db.query(
      'channels',
      where:   "url LIKE 'tflix://%'",
      orderBy: 'name COLLATE NOCASE ASC',
      limit:   limit,
    );
    return rows.map(Channel.fromDb).toList();
  }

  Future<List<Channel>> recentlyWatched({int limit = 12}) async {
    final db   = await database;
    final rows = await db.rawQuery('''
SELECT channels.*
FROM   recently_watched
JOIN   channels ON channels.url = recently_watched.channel_url
ORDER  BY recently_watched.watched_at DESC
LIMIT  ?
''', [limit]);
    return rows.map(Channel.fromDb).toList();
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> setFavorite(String channelUrl, bool favorite) async {
    final db = await database;
    await db.update('channels', {'is_favorite': favorite ? 1 : 0},
        where: 'url = ?', whereArgs: [channelUrl]);
  }

  Future<void> markWatched(String channelUrl) async {
    final db = await database;
    await db.insert(
      'recently_watched',
      {'channel_url': channelUrl,
       'watched_at':  DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _escapeLike(String input) => input
      .replaceAll(r'\', r'\\')
      .replaceAll('%',  r'\%')
      .replaceAll('_',  r'\_');
}
