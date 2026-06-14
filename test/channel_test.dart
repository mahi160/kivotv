import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/models/channel.dart';

void main() {
  group('Channel.fromDb', () {
    test('parses all fields correctly', () {
      final map = {
        'id': 'bbc.uk',
        'name': 'BBC News',
        'url': 'https://example.com/bbc.m3u8',
        'logo': 'https://example.com/logo.png',
        'group_name': 'News',
        'playlist_id': 1,
        'is_pinned': 1,
        'is_favorite': 0,
        'is_broken': 0,
      };
      final ch = Channel.fromDb(map);

      expect(ch.id, 'bbc.uk');
      expect(ch.name, 'BBC News');
      expect(ch.url, 'https://example.com/bbc.m3u8');
      expect(ch.logo, 'https://example.com/logo.png');
      expect(ch.group, 'News');
      expect(ch.playlistId, 1);
      expect(ch.isPinned, isTrue);
      expect(ch.isFavorite, isFalse);
      expect(ch.isBroken, isFalse);
    });

    test('handles null optional fields', () {
      final map = {
        'id': 'test',
        'name': 'Test',
        'url': 'https://example.com/test.m3u8',
        'logo': null,
        'group_name': null,
        'playlist_id': null,
        'is_pinned': 0,
        'is_favorite': 0,
        'is_broken': 0,
      };
      final ch = Channel.fromDb(map);

      expect(ch.logo, isNull);
      expect(ch.group, isNull);
      expect(ch.playlistId, isNull);
    });
  });

  group('Channel.copyWith', () {
    const base = Channel(
      id: 'id1',
      name: 'Original',
      url: 'https://example.com/1.m3u8',
      logo: 'https://example.com/logo.png',
      group: 'Sports',
      isPinned: false,
      isFavorite: false,
    );

    test('returns identical channel when no args given', () {
      final copy = base.copyWith();
      expect(copy.id, base.id);
      expect(copy.name, base.name);
      expect(copy.url, base.url);
      expect(copy.logo, base.logo);
      expect(copy.group, base.group);
      expect(copy.isPinned, base.isPinned);
    });

    test('overrides only specified fields', () {
      final copy = base.copyWith(isPinned: true, name: 'Updated');
      expect(copy.isPinned, isTrue);
      expect(copy.name, 'Updated');
      expect(copy.url, base.url); // unchanged
      expect(copy.logo, base.logo); // unchanged
    });

    test('can set nullable fields to null', () {
      final copy = base.copyWith(logo: null, group: null);
      expect(copy.logo, isNull);
      expect(copy.group, isNull);
      expect(copy.name, base.name); // unchanged
    });
  });

  group('Channel.toDb', () {
    test('produces correct map for DB insert', () {
      const ch = Channel(
        id: 'bbc.uk',
        name: 'BBC News',
        url: 'https://example.com/bbc.m3u8',
        group: 'News',
        isPinned: true,
        isFavorite: false,
        isBroken: false,
      );
      final map = ch.toDb(playlistId: 42);

      expect(map['id'], 'bbc.uk');
      expect(map['playlist_id'], 42);
      expect(map['name'], 'BBC News');
      expect(map['is_pinned'], 1);
      expect(map['is_favorite'], 0);
      expect(map['is_broken'], 0);
      expect(
        (map['search_text'] as String).contains('bbc news'),
        isTrue,
        reason: 'search_text should contain lowercased name',
      );
    });
  });
}
