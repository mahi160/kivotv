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
      version: 3,
      onCreate: (db, _) => _createSchema(db),
      onUpgrade: (db, oldVersion, _) async {
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
  watched_at INTEGER NOT NULL,
  FOREIGN KEY (channel_url) REFERENCES channels (url) ON DELETE CASCADE
)
''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_recent_watched_at ON recently_watched(watched_at DESC)',
          );
        }
        if (oldVersion < 3) {
          await _addColumnIfMissing(
            db,
            'channels',
            'is_favorite',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_channels_favorite ON channels(is_favorite)',
          );
        }
      },
    );
    _db = opened;
    return opened;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE playlists (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  url TEXT NOT NULL UNIQUE,
  last_refreshed_at INTEGER
)
''');
    await db.execute('''
CREATE TABLE channels (
  id TEXT NOT NULL,
  playlist_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  url TEXT NOT NULL UNIQUE,
  logo TEXT,
  group_name TEXT,
  search_text TEXT NOT NULL,
  is_pinned INTEGER NOT NULL DEFAULT 0,
  is_favorite INTEGER NOT NULL DEFAULT 0,
  is_broken INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE
)
''');
    await db.execute('''
CREATE TABLE recently_watched (
  channel_url TEXT PRIMARY KEY,
  watched_at INTEGER NOT NULL,
  FOREIGN KEY (channel_url) REFERENCES channels (url) ON DELETE CASCADE
)
''');
    await db.execute('CREATE INDEX idx_channels_name ON channels(name)');
    await db.execute('CREATE INDEX idx_channels_group ON channels(group_name)');
    await db.execute(
      'CREATE INDEX idx_channels_search ON channels(search_text)',
    );
    await db.execute('CREATE INDEX idx_channels_pinned ON channels(is_pinned)');
    await db.execute(
      'CREATE INDEX idx_channels_favorite ON channels(is_favorite)',
    );
    await db.execute('CREATE INDEX idx_channels_broken ON channels(is_broken)');
    await db.execute(
      'CREATE INDEX idx_recent_watched_at ON recently_watched(watched_at DESC)',
    );
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

  Future<int> upsertPlaylist({
    required String name,
    required String url,
  }) async {
    final db = await database;
    final refreshedAt = DateTime.now().millisecondsSinceEpoch;
    // Single upsert: insert or update name + timestamp on url conflict.
    // RETURNING id avoids a separate SELECT query.
    final result = await db.rawQuery(
      '''
INSERT INTO playlists (name, url, last_refreshed_at)
VALUES (?, ?, ?)
ON CONFLICT(url) DO UPDATE SET
  name = excluded.name,
  last_refreshed_at = excluded.last_refreshed_at
RETURNING id
''',
      [name, url, refreshedAt],
    );
    return result.single['id'] as int;
  }

  Future<List<Playlist>> playlists() async {
    final db = await database;
    final rows = await db.query('playlists', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Playlist.fromDb).toList();
  }

  Future<void> replaceChannels({
    required int playlistId,
    required List<Channel> channels,
  }) {
    return upsertChannels(playlistId: playlistId, channels: channels);
  }

  Future<void> upsertChannels({
    required int playlistId,
    required List<Channel> channels,
  }) async {
    final db = await database;
    final batch = db.batch();
    for (final channel in channels) {
      final data = channel.toDb(playlistId: playlistId);
      batch.rawInsert(
        '''
INSERT INTO channels (id, playlist_id, name, url, logo, group_name, search_text, is_pinned, is_favorite, is_broken)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(url) DO UPDATE SET
  id = excluded.id,
  playlist_id = excluded.playlist_id,
  name = excluded.name,
  logo = excluded.logo,
  group_name = excluded.group_name,
  search_text = excluded.search_text
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
          data['is_broken'],
        ],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> channelCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM channels WHERE is_broken = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Channel>> channels({
    String query = '',
    int limit = 100,
    int offset = 0,
    bool includeBroken = false,
  }) async {
    final db = await database;
    final normalizedQuery = query.trim().toLowerCase();
    final where = <String>[];
    final args = <Object?>[];
    if (!includeBroken) where.add('is_broken = 0');
    if (normalizedQuery.isNotEmpty) {
      where.add(r"search_text LIKE ? ESCAPE '\'");
      args.add('%${_escapeLike(normalizedQuery)}%');
    }
    final rows = await db.query(
      'channels',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Channel.fromDb).toList();
  }

  Future<List<Channel>> pinnedChannels({int limit = 12}) async {
    final db = await database;
    final rows = await db.query(
      'channels',
      where: 'is_pinned = 1 AND is_broken = 0',
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(Channel.fromDb).toList();
  }

  Future<List<Channel>> favoriteChannels({int limit = 12}) async {
    final db = await database;
    final rows = await db.query(
      'channels',
      where: 'is_favorite = 1 AND is_broken = 0',
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
FROM recently_watched
JOIN channels ON channels.url = recently_watched.channel_url
WHERE channels.is_broken = 0
ORDER BY recently_watched.watched_at DESC
LIMIT ?
''',
      [limit],
    );
    return rows.map(Channel.fromDb).toList();
  }

  Future<void> setPinned(String channelUrl, bool pinned) async {
    final db = await database;
    await db.update(
      'channels',
      {'is_pinned': pinned ? 1 : 0},
      where: 'url = ?',
      whereArgs: [channelUrl],
    );
  }

  Future<void> setFavorite(String channelUrl, bool favorite) async {
    final db = await database;
    await db.update(
      'channels',
      {'is_favorite': favorite ? 1 : 0},
      where: 'url = ?',
      whereArgs: [channelUrl],
    );
  }

  Future<void> markBroken(String channelUrl) async {
    final db = await database;
    await db.update(
      'channels',
      {'is_broken': 1},
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

  String _escapeLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}
