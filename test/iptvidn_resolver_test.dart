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
    // A real play.php body (host + token live in the iframe src).
    const body =
        '<iframe allowfullscreen style="width:100%; height:100%;" '
        'src="http://103.89.248.10:8082/STAR-SPORTS-1/embed.html'
        '?token=aaaa-bbbb-1781985015-1781974215&remote=no_check_ip"></iframe>';

    test('builds the index.m3u8 URL from the embed host + token', () {
      final r = IptvidnResolver.parsePlayResponse(body);
      expect(
        r.url,
        'http://103.89.248.10:8082/STAR-SPORTS-1/index.m3u8'
        '?token=aaaa-bbbb-1781985015-1781974215',
      );
    });

    test('parses the token expiry (second-to-last field)', () {
      final r = IptvidnResolver.parsePlayResponse(body);
      expect(
        r.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1781985015 * 1000),
      );
    });

    test('throws when no embed iframe is present', () {
      expect(
        () => IptvidnResolver.parsePlayResponse('<html>nope</html>'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
