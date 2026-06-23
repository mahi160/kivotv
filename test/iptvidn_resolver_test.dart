import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/iptvidn_resolver.dart';

void main() {
  group('IptvidnResolver.isResolvable', () {
    test('matches iptvidn references, not direct URLs', () {
      expect(IptvidnResolver.isResolvable('iptvidn://STAR-SPORTS-1'), isTrue);
      expect(IptvidnResolver.isResolvable('https://x.com/a.m3u8'), isFalse);
    });
  });

  group('IptvidnResolver.parsePlayResponse', () {
    // Build a token whose expiry is ~3 h from now so _expiryOf() always
    // accepts it regardless of when the test runs.
    final expiryUnix =
        DateTime.now().add(const Duration(hours: 3)).millisecondsSinceEpoch ~/
            1000;
    final startUnix = expiryUnix - 10800; // 3 h stream window
    final token     = 'aaaa-bbbb-$expiryUnix-$startUnix';
    final body =
        '<iframe allowfullscreen style="width:100%; height:100%;" '
        'src="http://103.89.248.10:8082/STAR-SPORTS-1/embed.html'
        '?token=$token&remote=no_check_ip"></iframe>';

    test('builds the index.m3u8 URL from the embed host + token', () {
      final r = IptvidnResolver.parsePlayResponse(body);
      expect(
        r.url,
        'http://103.89.248.10:8082/STAR-SPORTS-1/index.m3u8?token=$token',
      );
    });

    test('parses the token expiry (second-to-last field)', () {
      final r = IptvidnResolver.parsePlayResponse(body);
      expect(
        r.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(expiryUnix * 1000),
      );
    });

    test('returns null expiry for an already-expired token', () {
      // Unix timestamp in year 2001 — always in the past.
      const pastToken = 'aaaa-bbbb-1000000000-999989200';
      const expiredBody =
          '<iframe allowfullscreen style="width:100%; height:100%;" '
          'src="http://103.89.248.10:8082/STAR-SPORTS-1/embed.html'
          '?token=$pastToken&remote=no_check_ip"></iframe>';
      final r = IptvidnResolver.parsePlayResponse(expiredBody);
      expect(r.expiresAt, isNull); // _expiryOf rejects past timestamps
    });

    test('returns null expiry for a malformed token (too few fields)', () {
      const badToken = 'notavalidtoken';
      const badBody =
          '<iframe allowfullscreen style="width:100%; height:100%;" '
          'src="http://103.89.248.10:8082/STAR-SPORTS-1/embed.html'
          '?token=$badToken&remote=no_check_ip"></iframe>';
      final r = IptvidnResolver.parsePlayResponse(badBody);
      expect(r.expiresAt, isNull);
    });

    test('throws when no embed iframe is present', () {
      expect(
        () => IptvidnResolver.parsePlayResponse('<html>nope</html>'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
