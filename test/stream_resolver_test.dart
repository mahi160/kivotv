import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/stream_resolver.dart';

void main() {
  group('StreamResolver', () {
    test('isResolvable is false for a direct playable URL', () {
      expect(StreamResolver.isResolvable('https://example.com/live.m3u8'), false);
    });

    test('isResolvable is true for each known scheme', () {
      expect(StreamResolver.isResolvable('tflix://a/match_1'), true);
      expect(StreamResolver.isResolvable('iptvidn://SLUG'), true);
      expect(
        StreamResolver.isResolvable(
          'https://streamcrichd.com/update/fetch.php?hd=1',
        ),
        true,
      );
    });

    // resolve() must never silently misroute an unresolvable reference to
    // whichever resolver happens to be last in the dispatch table — callers
    // are required to guard with isResolvable first, and an unguarded call
    // must fail loudly instead of parsing garbage.
    test('resolve throws StateError for a reference no resolver owns', () {
      expect(
        () => StreamResolver.resolve('https://example.com/live.m3u8'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
