import 'dart:convert';
import 'dart:io';

import 'http_get.dart';
import 'resolved_stream.dart';

/// Resolves `https://streamcrichd.com/update/fetch.php?hd=<id>` pages to HLS.
class StreamcrichdResolver {
  StreamcrichdResolver._();
  static final StreamcrichdResolver instance = StreamcrichdResolver._();

  static const _base = 'https://streamcrichd.com';
  static const _premiumBase = 'https://executeandship.com';
  static const _ua = 'Mozilla/5.0';

  static final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  static bool isResolvable(String reference) {
    final uri = Uri.tryParse(reference);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'streamcrichd.com' &&
        uri.path == '/update/fetch.php' &&
        uri.queryParameters['hd']?.isNotEmpty == true;
  }

  Future<ResolvedStream> resolve(String reference) async {
    final pageUri = Uri.parse(reference);
    final page = await _getLenient(pageUri, referer: '$_base/');
    final fid = parseFetchPage(page);
    if (fid.length > 256) {
      throw const FormatException('streamcrichd: fid too long');
    }

    final playerUri = Uri.parse(
      '$_premiumBase/premiumcr.php?player=desktop&live=${Uri.encodeQueryComponent(fid)}',
    );
    final player = await httpGetString(
      _http,
      playerUri,
      referer: reference,
      userAgent: _ua,
    );

    return parsePlayerPage(player);
  }

  static String parseFetchPage(String body) {
    final match = RegExp(r'''\bfid\s*=\s*["']([^"']+)["']''').firstMatch(body);
    if (match == null) {
      throw const FormatException('streamcrichd: no fid in fetch page');
    }
    return match.group(1)!;
  }

  static ResolvedStream parsePlayerPage(String body) {
    final match = RegExp(
      r'''return\s*\(\s*\[(.*?)\]\s*\.join\(""\)''',
      dotAll: true,
    ).firstMatch(body);
    if (match == null) {
      throw const FormatException(
        'streamcrichd: no HLS URL array in player page',
      );
    }

    final quoted = RegExp(r'''"(?:\\.|[^"\\])*"''').allMatches(match.group(1)!);
    final url = quoted.map((m) {
      try {
        return jsonDecode(m.group(0)!) as String;
      } on FormatException {
        throw const FormatException('streamcrichd: malformed HLS URL array');
      }
    }).join();
    final uri = Uri.parse(url);
    if (!url.startsWith(RegExp(r'https?://')) ||
        !url.toLowerCase().contains('.m3u8') ||
        !_isAllowedHlsHost(uri.host)) {
      throw FormatException(
        'streamcrichd: unexpected HLS URL "$url" (host not in allowlist)',
      );
    }

    // Extract fid from the HLS path (…/hls/<fid>.m3u8) for display name.
    final pathSeg = uri.pathSegments;
    final fidRaw = pathSeg.isNotEmpty
        ? pathSeg.last.replaceFirst(
            RegExp(r'\.m3u8$', caseSensitive: false),
            '',
          )
        : null;
    return ResolvedStream(
      url: url,
      expiresAt: _expiryOf(uri),
      httpHeaders: const {'User-Agent': _ua, 'Referer': '$_premiumBase/'},
      channelName: fidRaw != null && fidRaw.isNotEmpty
          ? _fidToName(fidRaw)
          : null,
    );
  }

  /// Converts a raw stream fid (e.g. "asportshd", "geo-super") to a
  /// human-readable channel name ("A Sports HD", "Geo Super").
  static String _fidToName(String fid) {
    var s = fid.toLowerCase();
    // Peel off known quality suffixes before splitting.
    var suffix = '';
    for (final q in ['fhd', 'uhd', 'hd', 'sd']) {
      if (s.endsWith(q) && s.length > q.length) {
        suffix = ' ${q.toUpperCase()}';
        s = s.substring(0, s.length - q.length);
        break;
      }
    }
    // Split on hyphens, underscores, and camelCase transitions.
    final words = s
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m.group(1)!} ${m.group(2)!}',
        )
        .split(RegExp(r'[-_\s]+'))
        .where((p) => p.isNotEmpty)
        .map(
          (p) => p.length <= 3
              ? p.toUpperCase()
              : p[0].toUpperCase() + p.substring(1),
        )
        .toList();
    return (words.join(' ') + suffix).trim();
  }

  static bool _isAllowedHlsHost(String host) =>
      host == 'zohanayaan.com' || host.endsWith('.zohanayaan.com');

  static DateTime? _expiryOf(Uri url) {
    final seconds = int.tryParse(url.queryParameters['expires'] ?? '');
    if (seconds == null) return null;
    final expiry = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final now = DateTime.now();
    if (expiry.isBefore(now) ||
        expiry.isAfter(now.add(const Duration(days: 2)))) {
      return null;
    }
    return expiry;
  }

  /// Lenient GET that accepts both 200 and 500 responses. The fetch.php
  /// endpoint returns a 500 status but still serves valid HTML with the
  /// stream player markup we need.
  static Future<String> _getLenient(Uri url, {String? referer}) async {
    final req = await _http.getUrl(url);
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    if (referer != null) req.headers.set(HttpHeaders.refererHeader, referer);
    final resp = await req.close().timeout(const Duration(seconds: 15));
    if (resp.statusCode != HttpStatus.ok &&
        resp.statusCode != HttpStatus.internalServerError) {
      throw HttpException('HTTP ${resp.statusCode}', uri: url);
    }
    return resp
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 15));
  }
}
