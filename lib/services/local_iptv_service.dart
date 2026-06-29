import 'dart:convert';
import 'dart:io';

import '../models/channel.dart';
import 'http_get.dart';

/// Scrapes channels from the LiveTV.IPTV web panel running on the local
/// network at [_baseUrl]. The panel embeds all channel metadata as a JSON
/// array (`var allCh = [...]`) directly in the HTML, so no separate API
/// call is needed. Streams are served by Flussonic at [_streamPort].
///
/// Silently returns an empty list when the server is unreachable — this
/// source is optional and should never block bootstrap or show an error
/// when the device is off the home network.
class LocalIptvService {
  LocalIptvService._();
  static final LocalIptvService instance = LocalIptvService._();

  static const _baseUrl = 'http://10.255.255.50';
  // Streams are served by Flussonic at port 9898 — embedded in channel URLs.

  static final _allChRegex = RegExp(r'var allCh = (\[.*?\]);');

  Future<List<Channel>> fetchChannels() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final html = await httpGetString(
        client,
        Uri.parse('$_baseUrl/'),
        bodyTimeout: const Duration(seconds: 8),
      );
      return _parse(html);
    } catch (_) {
      // Server unreachable or response malformed — not an error condition.
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  List<Channel> _parse(String html) {
    final match = _allChRegex.firstMatch(html);
    if (match == null) return const [];

    final raw = jsonDecode(match.group(1)!) as List<dynamic>;
    final channels = <Channel>[];

    for (final item in raw) {
      final m = item as Map<String, dynamic>;
      final id = m['id'] as String?;
      final name = m['name'] as String?;
      final url = m['url'] as String?;
      if (id == null || name == null || url == null || url.isEmpty) continue;

      final cats = m['categories'] as List<dynamic>?;
      final group = cats != null && cats.isNotEmpty
          ? _capitalise(cats.first as String)
          : null;

      channels.add(Channel(
        id: 'localiptv-$id',
        name: name,
        url: url,
        logo: m['logo'] as String?,
        group: group,
      ));
    }

    return channels;
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
