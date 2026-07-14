import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/core/db/database_service.dart';
import 'package:kivo/models/channel.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Channel _ch(String url, {String name = 'Ch', String? group}) =>
    Channel(id: url, name: name, url: url, group: group);

void main() {
  // sqflite delegates to a platform channel by default; ffi replaces that
  // with a pure-Dart/native sqlite3 binding so DatabaseService (unmodified)
  // runs against a real database in plain `flutter test`.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // A fresh, uniquely-named file per test — DatabaseService.forTesting
  // bypasses the app-wide singleton, but sqflite_common_ffi's own factory
  // caches connections by path, so reusing the literal ':memory:' string
  // across tests silently returns the *same* database instead of an empty
  // one. A unique temp file per test sidesteps that cache entirely.
  var dbCounter = 0;
  late DatabaseService db;
  late File dbFile;
  setUp(() {
    dbFile = File(
      p.join(Directory.systemTemp.path, 'kivo_test_${dbCounter++}.db'),
    );
    db = DatabaseService.forTesting(dbPath: dbFile.path);
  });
  tearDown(() async {
    if (await dbFile.exists()) await dbFile.delete();
  });

  group('replaceChannels — last_refreshed_at (AUDIT.md P0-2)', () {
    test('upsertPlaylist alone does not stamp last_refreshed_at', () async {
      final id = await db.upsertPlaylist(name: 'A', url: 'https://a.example/pl.m3u');
      final playlist = (await db.playlists()).single;
      expect(playlist.id, id);
      expect(playlist.lastRefreshedAt, isNull);
    });

    test('replaceChannels stamps last_refreshed_at even with zero channels', () async {
      final id = await db.upsertPlaylist(name: 'A', url: 'https://a.example/pl.m3u');
      await db.replaceChannels(playlistId: id, channels: [_ch('https://a.example/1')]);

      final playlist = (await db.playlists()).single;
      expect(playlist.lastRefreshedAt, isNotNull);
    });
  });

  group('replaceChannels — cross-playlist ownership (AUDIT.md P0-3)', () {
    test(
      'a URL owned by another playlist keeps its original metadata and owner',
      () async {
        final a = await db.upsertPlaylist(name: 'A', url: 'kivo://a');
        final b = await db.upsertPlaylist(name: 'B', url: 'kivo://b');
        const sharedUrl = 'https://cdn.example/shared.m3u8';

        await db.replaceChannels(
          playlistId: a,
          channels: [_ch(sharedUrl, name: 'From A', group: 'Sports')],
        );
        // B's refresh also lists the same URL, with different metadata.
        await db.replaceChannels(
          playlistId: b,
          channels: [_ch(sharedUrl, name: 'From B', group: 'Akash Sports')],
        );

        final found = await db.channels(query: '');
        expect(found, hasLength(1)); // one metadata row, not two
        expect(found.single.name, 'From A'); // first owner wins, never reparented
        expect(found.single.playlistId, a);
      },
    );

    test(
      'disabling the metadata owner does not hide a URL another enabled '
      'playlist also lists',
      () async {
        final a = await db.upsertPlaylist(name: 'A', url: 'kivo://a');
        final b = await db.upsertPlaylist(name: 'B', url: 'kivo://b');
        const sharedUrl = 'https://cdn.example/shared.m3u8';

        await db.replaceChannels(playlistId: a, channels: [_ch(sharedUrl)]);
        await db.replaceChannels(playlistId: b, channels: [_ch(sharedUrl)]);

        await db.setPlaylistEnabled(a, enabled: false);

        final found = await db.channels(query: '');
        expect(
          found,
          hasLength(1),
          reason: 'B still lists the URL and is enabled, so it must stay visible',
        );
      },
    );

    test('disabling every playlist that lists a URL hides it', () async {
      final a = await db.upsertPlaylist(name: 'A', url: 'kivo://a');
      final b = await db.upsertPlaylist(name: 'B', url: 'kivo://b');
      const sharedUrl = 'https://cdn.example/shared.m3u8';

      await db.replaceChannels(playlistId: a, channels: [_ch(sharedUrl)]);
      await db.replaceChannels(playlistId: b, channels: [_ch(sharedUrl)]);

      await db.setPlaylistEnabled(a, enabled: false);
      await db.setPlaylistEnabled(b, enabled: false);

      expect(await db.channels(query: ''), isEmpty);
    });

    test(
      'a playlist dropping a shared URL from its own list does not affect '
      'the other playlist still listing it',
      () async {
        final a = await db.upsertPlaylist(name: 'A', url: 'kivo://a');
        final b = await db.upsertPlaylist(name: 'B', url: 'kivo://b');
        const sharedUrl = 'https://cdn.example/shared.m3u8';

        await db.replaceChannels(playlistId: a, channels: [_ch(sharedUrl)]);
        await db.replaceChannels(playlistId: b, channels: [_ch(sharedUrl)]);

        // B's next refresh no longer includes the shared URL.
        await db.replaceChannels(playlistId: b, channels: const []);

        expect(
          await db.channels(query: ''),
          hasLength(1),
          reason: 'A still lists it and is enabled',
        );

        await db.setPlaylistEnabled(a, enabled: false);
        expect(
          await db.channels(query: ''),
          isEmpty,
          reason: 'B no longer lists it, so no enabled playlist does',
        );
      },
    );

    test('unrelated, non-shared channels are unaffected', () async {
      final a = await db.upsertPlaylist(name: 'A', url: 'kivo://a');
      final b = await db.upsertPlaylist(name: 'B', url: 'kivo://b');

      await db.replaceChannels(
        playlistId: a,
        channels: [_ch('https://a.example/1', name: 'A1')],
      );
      await db.replaceChannels(
        playlistId: b,
        channels: [_ch('https://b.example/1', name: 'B1')],
      );

      await db.setPlaylistEnabled(a, enabled: false);

      final found = await db.channels(query: '');
      expect(found, hasLength(1));
      expect(found.single.name, 'B1');
    });
  });

  group('replaceChannels — unchanged rows skip the metadata rewrite (P1-2)', () {
    test('re-storing identical channels leaves is_favorite untouched', () async {
      final a = await db.upsertPlaylist(name: 'A', url: 'kivo://a');
      const url = 'https://a.example/1';
      await db.replaceChannels(playlistId: a, channels: [_ch(url, name: 'X')]);
      await db.setFavorite(url, true);

      // Re-run with the exact same channel data.
      await db.replaceChannels(playlistId: a, channels: [_ch(url, name: 'X')]);

      final found = await db.channels(query: '');
      expect(found.single.isFavorite, isTrue);
    });
  });
}
