import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/models/playlist.dart';

void main() {
  group('Playlist.fromDb', () {
    test('parses all fields', () {
      final ts = DateTime(2024, 6, 1).millisecondsSinceEpoch;
      final map = {
        'id': 7,
        'name': 'IPTV Org',
        'url': 'https://iptv-org.github.io/iptv/index.m3u',
        'last_refreshed_at': ts,
      };
      final p = Playlist.fromDb(map);

      expect(p.id, 7);
      expect(p.name, 'IPTV Org');
      expect(p.url, 'https://iptv-org.github.io/iptv/index.m3u');
      expect(p.lastRefreshedAt, ts);
      expect(p.isBuiltIn, isFalse);
    });

    test('null lastRefreshedAt is preserved', () {
      final map = {
        'id': 1,
        'name': 'Test',
        'url': 'https://example.com/pl.m3u',
        'last_refreshed_at': null,
      };
      final p = Playlist.fromDb(map);
      expect(p.lastRefreshedAt, isNull);
      expect(p.lastRefreshedDateTime, isNull);
    });
  });

  group('Playlist.isBuiltIn', () {
    test('kivo:// URL is built-in', () {
      const p = Playlist(id: 1, name: 'Examples', url: 'kivo://examples');
      expect(p.isBuiltIn, isTrue);
    });

    test('https:// URL is not built-in', () {
      const p =
          Playlist(id: 2, name: 'Remote', url: 'https://example.com/pl.m3u');
      expect(p.isBuiltIn, isFalse);
    });
  });

  group('Playlist.copyWith', () {
    const base = Playlist(
      id: 3,
      name: 'Original',
      url: 'https://example.com/pl.m3u',
    );

    test('copies unchanged fields', () {
      final copy = base.copyWith(name: 'Updated');
      expect(copy.id, base.id);
      expect(copy.url, base.url);
      expect(copy.name, 'Updated');
    });
  });

  group('Playlist.lastRefreshedDateTime', () {
    test('converts epoch ms to DateTime', () {
      final ts = DateTime(2024, 1, 15, 12, 0).millisecondsSinceEpoch;
      final p = Playlist(
          id: 1, name: 'X', url: 'https://x.com/p.m3u', lastRefreshedAt: ts);
      final dt = p.lastRefreshedDateTime!;
      expect(dt.year, 2024);
      expect(dt.month, 1);
      expect(dt.day, 15);
    });
  });
}
