import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/models/channel.dart';

void main() {
  group('Channel.fromDb', () {
    test('parses all fields correctly', () {
      final map = {
        'id':          'bbc.uk',
        'name':        'BBC News',
        'url':         'https://example.com/bbc.m3u8',
        'logo':        'https://example.com/logo.png',
        'group_name':  'News',
        'playlist_id': 1,
        'is_favorite': 1,
      };
      final ch = Channel.fromDb(map);

      expect(ch.id,         'bbc.uk');
      expect(ch.name,       'BBC News');
      expect(ch.url,        'https://example.com/bbc.m3u8');
      expect(ch.logo,       'https://example.com/logo.png');
      expect(ch.group,      'News');
      expect(ch.playlistId, 1);
      expect(ch.isFavorite, isTrue);
    });

    test('handles null optional fields', () {
      final map = {
        'id':          'test',
        'name':        'Test',
        'url':         'https://example.com/test.m3u8',
        'logo':        null,
        'group_name':  null,
        'playlist_id': null,
        'is_favorite': 0,
      };
      final ch = Channel.fromDb(map);

      expect(ch.logo,       isNull);
      expect(ch.group,      isNull);
      expect(ch.playlistId, isNull);
    });

    test('ignores legacy is_pinned / is_broken columns in old DB rows', () {
      // Old DB rows may still carry is_pinned + is_broken — fromDb must not
      // throw and must simply ignore them.
      final map = {
        'id':          'old',
        'name':        'Old Channel',
        'url':         'https://example.com/old.m3u8',
        'logo':        null,
        'group_name':  null,
        'playlist_id': 1,
        'is_favorite': 0,
        'is_pinned':   1, // legacy — should be silently ignored
        'is_broken':   1, // legacy — should be silently ignored
      };
      expect(() => Channel.fromDb(map), returnsNormally);
    });
  });

  group('Channel.copyWith', () {
    const base = Channel(
      id:         'id1',
      name:       'Original',
      url:        'https://example.com/1.m3u8',
      logo:       'https://example.com/logo.png',
      group:      'Sports',
      isFavorite: false,
    );

    test('returns identical channel when no args given', () {
      final copy = base.copyWith();
      expect(copy.id,         base.id);
      expect(copy.name,       base.name);
      expect(copy.url,        base.url);
      expect(copy.logo,       base.logo);
      expect(copy.group,      base.group);
      expect(copy.isFavorite, base.isFavorite);
    });

    test('overrides only specified fields', () {
      final copy = base.copyWith(isFavorite: true, name: 'Updated');
      expect(copy.isFavorite, isTrue);
      expect(copy.name,     'Updated');
      expect(copy.url,      base.url);  // unchanged
      expect(copy.logo,     base.logo); // unchanged
    });

    test('can set nullable fields to null', () {
      final copy = base.copyWith(logo: null, group: null);
      expect(copy.logo,  isNull);
      expect(copy.group, isNull);
      expect(copy.name,  base.name); // unchanged
    });
  });

  group('Channel.toDb', () {
    test('produces correct map for DB insert', () {
      const ch = Channel(
        id:         'bbc.uk',
        name:       'BBC News',
        url:        'https://example.com/bbc.m3u8',
        group:      'News',
        isFavorite: true,
      );
      final map = ch.toDb(playlistId: 42);

      expect(map['id'],          'bbc.uk');
      expect(map['playlist_id'], 42);
      expect(map['name'],        'BBC News');
      expect(map['is_favorite'], 1);
      expect(map.containsKey('is_pinned'), isFalse,
          reason: 'is_pinned was removed from the app layer');
      expect(map.containsKey('is_broken'), isFalse,
          reason: 'is_broken was removed in v4');
      expect(
        (map['search_text'] as String).contains('bbc news'),
        isTrue,
        reason: 'search_text should contain lowercased name',
      );
    });
  });
}
