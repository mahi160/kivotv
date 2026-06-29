import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/tflix_service.dart';
import 'package:kivo/services/tflix_resolver.dart';

void main() {
  group('parseLiveMatches', () {
    const html = '''
<div class="card" data-status="live"
     onclick="location.href='play.php/turkey_paraguay/match_1781165015_4596'">
  <div class="topbar"><div>Football</div>
    <div class="tag">FIFA World Cup 2026™ | Group D</div></div>
  <div class="flex">
    <div class="team"><img alt="Turkey"><div class="team-name">Turkey </div></div>
    <div class="team"><img alt="Paraguay"><div class="team-name">Paraguay </div></div>
  </div>
</div>
<div class="card" data-status="upcoming"
     onclick="location.href='play.php/japan_tunisia/match_1781165815_2342'">
  <div class="flex">
    <div class="team"><div class="team-name">Japan</div></div>
    <div class="team"><div class="team-name">Tunisia</div></div>
  </div>
</div>
''';

    test('keeps live matches, skips upcoming', () {
      final matches = parseLiveMatches(html);
      expect(matches.length, 1);
      expect(matches.single.name, 'Turkey vs Paraguay');
    });

    test('builds a tflix:// reference and strips the ™ from the tag', () {
      final m = parseLiveMatches(html).single;
      expect(m.url, 'tflix://turkey_paraguay/match_1781165015_4596');
      expect(m.group, 'FIFA World Cup 2026 | Group D');
    });
  });

  group('TflixResolver.xorDecrypt', () {
    test('mirrors the JS atob+XOR scheme (round-trip)', () {
      const key = 'SecureKey123!';
      const plain = 'https://example.com/stream.mpd';
      final keyBytes = utf8.encode(key);
      final plainBytes = utf8.encode(plain);
      final xored = List<int>.generate(
        plainBytes.length,
        (i) => plainBytes[i] ^ keyBytes[i % keyBytes.length],
      );
      final encoded = base64.encode(xored);
      expect(TflixResolver.xorDecrypt(encoded, key), plain);
    });
  });

  group('TflixResolver.extractM3u8Candidates', () {
    test('pulls the inner m3u8 out of a ?url= player wrapper', () {
      const body = '''
        Iframe('https://hlsplayers.pages.dev/player1?url=https://cdn.example.com/a/chunklist.m3u8')
        Iframe('https://hlsplayers.pages.dev/player3?url=https://live.example.com:30443/b/chunks.m3u8')
        Iframe('https://bokul-cdn.example/play.php?id=abc')  // obfuscated, no m3u8
      ''';
      final c = TflixResolver.extractM3u8Candidates(body);
      expect(c, [
        'https://cdn.example.com/a/chunklist.m3u8',
        'https://live.example.com:30443/b/chunks.m3u8',
      ]);
    });

    test('ignores wrapper pages and returns empty when no m3u8 exists', () {
      expect(
        TflixResolver.extractM3u8Candidates('<html>no streams here</html>'),
        isEmpty,
      );
    });
  });
}
