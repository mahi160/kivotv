import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/playlist_service.dart';

void main() {
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
