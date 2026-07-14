import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import '../models/channel.dart';

class PlaylistService {
  PlaylistService._();

  static final PlaylistService instance = PlaylistService._();

  static const playlistUrl = 'https://iptv-org.github.io/iptv/index.m3u';

  /// Fetches and parses an M3U playlist from [url].
  ///
  /// Uses a fresh [HttpClient] per call — playlist refreshes now run
  /// concurrently (see [PlaylistRepository.refreshAllPlaylists]), and a
  /// shared cancel-previous client would kill sibling in-flight fetches.
  ///
  /// The full response body is read into a single String, then passed to
  /// [parseM3u] running in a background isolate via [compute] so the UI
  /// thread is never blocked by the regex-heavy parse (10k+ entries ≈ 200 ms).
  Future<List<Channel>> fetchChannels({String url = playlistUrl}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);

    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Failed to download playlist: HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      // Read the body with a hard timeout so a stalled CDN doesn't leave
      // the "Fetching channels…" indicator running forever.
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 90));

      // Parse on a background isolate — the regex loop over 10k+ lines
      // would jank the UI for ~200 ms on a low-end TV SoC if run here.
      return compute(parseM3u, body);
    } finally {
      client.close(force: true);
    }
  }
}

/// Parses a full M3U string into channels.
List<Channel> parseM3u(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final channels = <Channel>[];

  for (var i = 0; i < lines.length; i++) {
    final metadata = lines[i];
    if (!metadata.startsWith('#EXTINF')) {
      continue;
    }

    final urlIndex = i + 1;
    if (urlIndex >= lines.length) {
      continue;
    }

    final url = lines[urlIndex];
    if (url.startsWith('#')) {
      continue;
    }

    final attrs = _parseAttributes(metadata);
    final fallbackName = _parseName(metadata);
    final name = _firstNonEmpty([
      attrs['tvg-name'],
      fallbackName,
      attrs['tvg-id'],
    ]);

    if (name == null) {
      continue;
    }

    final tvgId = attrs['tvg-id'];
    channels.add(
      Channel(
        id: (tvgId == null || tvgId.isEmpty) ? _fallbackId(url) : tvgId,
        name: name,
        url: url,
        logo: _emptyToNull(attrs['tvg-logo']),
        group: _emptyToNull(attrs['group-title']),
      ),
    );
  }

  return channels;
}

Map<String, String> _parseAttributes(String metadata) {
  final attrs = <String, String>{};
  final attrPattern = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

  for (final match in attrPattern.allMatches(metadata)) {
    attrs[match.group(1)!] = match.group(2)!;
  }

  return attrs;
}

String? _parseName(String metadata) {
  final commaIndex = _findNameSeparator(metadata);
  if (commaIndex == -1 || commaIndex == metadata.length - 1) {
    return null;
  }

  return _emptyToNull(metadata.substring(commaIndex + 1).trim());
}

int _findNameSeparator(String metadata) {
  var inQuotes = false;

  for (var i = 0; i < metadata.length; i++) {
    final char = metadata[i];
    if (char == '"') {
      inQuotes = !inQuotes;
    } else if (char == ',' && !inQuotes) {
      return i;
    }
  }

  return -1;
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final normalized = _emptyToNull(value);
    if (normalized != null) {
      return normalized;
    }
  }

  return null;
}

String _fallbackId(String url) => 'url_${base64Url.encode(utf8.encode(url))}';

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  return trimmed;
}
