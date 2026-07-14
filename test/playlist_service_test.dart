import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/playlist_service.dart';

void main() {
  group('PlaylistService.fetchChannels — concurrency (AUDIT.md P0-1)', () {
    // Regression test for the cancel-previous-client bug: fetchChannels used
    // to share one HttpClient across calls and force-close it whenever a new
    // fetch started, so concurrent fetches (as refreshAllPlaylists now runs
    // them) killed each other.
    //
    // Verified by hand (see AUDIT.md) that `HttpClient.close(force: true)`
    // only actually aborts a call whose TCP connect is still pending — on
    // loopback that phase resolves in low-single-digit milliseconds, too fast
    // to hit deterministically from a unit test without relying on real
    // network latency (which would make this test flaky/environment-
    // dependent). This test instead pins the *contract* fetchChannels must
    // hold: concurrent calls never interfere with each other, regardless of
    // response timing — it would fail immediately if a shared
    // cancel-on-new-call field were ever reintroduced and, on a slower
    // connection than loopback, is exactly the scenario the original bug hit.
    HttpServer? server;

    tearDown(() async {
      await server?.close(force: true);
      server = null;
    });

    test('two concurrent fetchChannels calls both succeed independently', () async {
      // The first request holds its response open until the second request
      // has definitely started, so both are genuinely in-flight at once.
      final secondRequestStarted = Completer<void>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        if (req.uri.path == '/slow') {
          await secondRequestStarted.future;
          req.response.write('#EXTM3U\n#EXTINF:-1,Slow\nhttps://example.com/slow.m3u8\n');
        } else {
          if (!secondRequestStarted.isCompleted) secondRequestStarted.complete();
          req.response.write('#EXTM3U\n#EXTINF:-1,Fast\nhttps://example.com/fast.m3u8\n');
        }
        await req.response.close();
      });
      final port = server!.port;

      final results = await Future.wait([
        PlaylistService.instance.fetchChannels(url: 'http://127.0.0.1:$port/slow'),
        PlaylistService.instance.fetchChannels(url: 'http://127.0.0.1:$port/fast'),
      ]);

      expect(results[0], hasLength(1));
      expect(results[0].single.name, 'Slow');
      expect(results[1], hasLength(1));
      expect(results[1].single.name, 'Fast');
    });
  });

  test('parseM3u parses channel metadata and urls', () {
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="bbc.uk" tvg-name="BBC News" tvg-logo="https://example.com/bbc.png" group-title="News",BBC News UK
https://example.com/bbc.m3u8
#EXTINF:-1 tvg-id="" tvg-name="" group-title="Music",Fallback Channel
https://example.com/music.m3u8
''';

    final channels = parseM3u(playlist);

    expect(channels, hasLength(2));
    expect(channels.first.id, 'bbc.uk');
    expect(channels.first.name, 'BBC News');
    expect(channels.first.url, 'https://example.com/bbc.m3u8');
    expect(channels.first.logo, 'https://example.com/bbc.png');
    expect(channels.first.group, 'News');
    expect(channels.last.id, startsWith('url_'));
    expect(channels.last.name, 'Fallback Channel');
    expect(channels.last.group, 'Music');
  });

  test('parseM3u handles commas inside attributes', () {
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-name="City News" group-title="Local, News",City News, HD
https://example.com/city.m3u8
''';

    final channels = parseM3u(playlist);

    expect(channels, hasLength(1));
    expect(channels.single.name, 'City News');
    expect(channels.single.group, 'Local, News');
  });

  test('parseM3u skips malformed entries', () {
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="missing-url",Missing URL
#EXTINF:-1 tvg-name="Valid",Valid
https://example.com/valid.m3u8
''';

    final channels = parseM3u(playlist);

    expect(channels, hasLength(1));
    expect(channels.single.name, 'Valid');
  });
}
