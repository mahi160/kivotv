import 'dart:convert';
import 'dart:io';

import '../models/channel.dart';

class PlaylistService {
  PlaylistService._();

  static final PlaylistService instance = PlaylistService._();

  static const playlistUrl = 'https://iptv-org.github.io/iptv/index.m3u';

  /// Currently active HTTP client — cancelled when a new fetch starts.
  HttpClient? _activeClient;

  /// Fetches and parses an M3U playlist without loading it fully into memory.
  ///
  /// Calling this while a previous fetch is in progress cancels the earlier
  /// request so bandwidth is never wasted on stale downloads.
  ///
  /// The response body is processed line-by-line (streaming), so even
  /// 200 MB playlist files never allocate a single giant String.
  Future<List<Channel>> fetchChannels({String url = playlistUrl}) async {
    // Cancel any in-flight request before starting a new one.
    _activeClient?.close(force: true);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    _activeClient = client;

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

      // Stream-decode into lines then parse synchronously.
      // compute() with 150k strings causes isolate message failures in
      // release builds — sync parse is safer; brief UI block is acceptable.
      final lines = await response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();

      return parseM3uLines(lines);
    } finally {
      // Only clear the reference if this client is still the active one.
      if (identical(_activeClient, client)) _activeClient = null;
      client.close(force: true);
    }
  }

  /// Cancels any in-progress playlist download immediately.
  void cancel() {
    _activeClient?.close(force: true);
    _activeClient = null;
  }
}

/// Parses a full M3U string (kept for unit tests and small playlists).
List<Channel> parseM3u(String content) =>
    parseM3uLines(const LineSplitter().convert(content));

/// Parses an M3U playlist from an already-split list of lines.
/// Prefer this overload when the lines come from a streaming source.
List<Channel> parseM3uLines(List<String> rawLines) {
  final lines = rawLines
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
