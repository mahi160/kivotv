import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/stream_resolver.dart';
import 'package:kivo/services/streamcrichd_resolver.dart';

void main() {
  group('StreamcrichdResolver.isResolvable', () {
    test('matches streamcrichd fetch URLs with hd', () {
      expect(
        StreamcrichdResolver.isResolvable(
          'https://streamcrichd.com/update/fetch.php?hd=24',
        ),
        isTrue,
      );
      expect(
        StreamResolver.isResolvable(
          'https://streamcrichd.com/update/fetch.php?hd=24',
        ),
        isTrue,
      );
    });

    test('rejects non-fetch URLs', () {
      expect(
        StreamcrichdResolver.isResolvable('https://x.com/a.m3u8'),
        isFalse,
      );
      expect(
        StreamcrichdResolver.isResolvable(
          'https://streamcrichd.com/update/fetch.php',
        ),
        isFalse,
      );
    });
  });

  group('StreamcrichdResolver.parseFetchPage', () {
    test('extracts the channel fid', () {
      expect(
        StreamcrichdResolver.parseFetchPage(
          '<script>fid="asportshd"; v_width="100%";</script>',
        ),
        'asportshd',
      );
    });

    test('throws when fid is absent', () {
      expect(
        () => StreamcrichdResolver.parseFetchPage('<html>nope</html>'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('StreamcrichdResolver.parsePlayerPage', () {
    final expiryUnix =
        DateTime.now().add(const Duration(hours: 3)).millisecondsSinceEpoch ~/
        1000;
    final url =
        'https://cdn1.zohanayaan.com/hls/asportshd.m3u8?md5=abc&expires=$expiryUnix';
    final body =
        '''
<script>
function pltHrtgteU() {
  return(${jsonEncode(url.split(''))}.join("") + suffix);
}
</script>
''';

    test('builds HLS URL from obfuscated char array', () {
      final r = StreamcrichdResolver.parsePlayerPage(body);
      expect(r.url, url);
      expect(r.httpHeaders?['User-Agent'], 'Mozilla/5.0');
      expect(r.httpHeaders?['Referer'], 'https://executeandship.com/');
    });

    test('derives channelName from fid in HLS path', () {
      final r = StreamcrichdResolver.parsePlayerPage(body);
      // "asportshd" → suffix "HD" stripped, remainder "asports" → "Asports HD"
      expect(r.channelName, 'Asports HD');
    });

    test('parses expires query parameter', () {
      final r = StreamcrichdResolver.parsePlayerPage(body);
      expect(
        r.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(expiryUnix * 1000),
      );
    });

    test('throws when HLS array is absent', () {
      expect(
        () => StreamcrichdResolver.parsePlayerPage('<html>nope</html>'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when HLS host is not the expected CDN', () {
      final badUrl =
          'https://evil.example/hls/asportshd.m3u8?expires=$expiryUnix';
      final badBody =
          '''
<script>
function pltHrtgteU() {
  return(${jsonEncode(badUrl.split(''))}.join(""));
}
</script>
''';
      expect(
        () => StreamcrichdResolver.parsePlayerPage(badBody),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
