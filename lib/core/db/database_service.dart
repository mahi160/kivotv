import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/channel.dart';
import '../../models/playlist.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;

    final dbPath = p.join(await getDatabasesPath(), 'kivo.db');
    final opened = await openDatabase(
      dbPath,
      version: 4,
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
    await db.execute('CREATE INDEX idx_channels_name    ON channels(name)');
    await db.execute('CREATE INDEX idx_channels_group   ON channels(group_name)');
    await db.execute('CREATE INDEX idx_channels_search  ON channels(search_text)');
    await db.execute('CREATE INDEX idx_channels_favorite ON channels(is_favorite)');
    await db.execute(
      'CREATE INDEX idx_recent_watched_at ON recently_watched(watched_at DESC)');
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
      where.add(r"search_text LIKE ? ESCAPE '\'");
      args.add('%${_escapeLike(normalizedQuery)}%');
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
  Future<List<MapEntry<String, List<Channel>>>> channelsByGroup() async {
    final db = await database;
    final rows = await db.query(
      'channels',
      where:   "url NOT LIKE 'tflix://%'",
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final byGroup = <String, List<Channel>>{};
    for (final row in rows) {
      final c = Channel.fromDb(row);
      final g = (c.group == null || c.group!.isEmpty) ? 'Other' : c.group!;
      (byGroup[g] ??= <Channel>[]).add(c);
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
