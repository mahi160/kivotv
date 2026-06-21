import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http_get.dart';

import 'resolved_stream.dart';

/// Resolves a `tflix://<teams>/match_<id>` reference into a playable HLS URL.
///
/// tflix aggregates several mirror sources per match. Phase 1 supports only the
/// "clean" ones that expose a direct m3u8 inside a `?url=<m3u8>` player wrapper
/// (JS-obfuscated `atob` embeds are intentionally ignored). Mirrors die or are
/// geo-blocked constantly, so we **probe candidates on-device** and return the
/// first that actually answers with an HLS manifest — meaning a dead first
/// mirror falls through to a working one instead of failing the whole match.
class TflixResolver {
  TflixResolver._();
  static final TflixResolver instance = TflixResolver._();

  static const _scheme = 'tflix://';
  static const _base   = 'https://tflix.pro';
  static const _ua     = 'Mozilla/5.0';

  // Persistent client for tflix.pro requests — reuses the TLS session across
  // multiple resolve() calls (play.php fetch + mirror probes). Saves one full
  // TLS handshake per channel switch. Mirror probes go to different CDN hosts,
  // so their connections can't be pooled, but the play.php fetch is reused.
  static final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  static bool isResolvable(String reference) => reference.startsWith(_scheme);

  // Inner m3u8 inside a player wrapper: ...?url=<m3u8> (or &url=<m3u8>).
  static final _wrappedUrl = RegExp(r'''[?&]url=(https?://[^"'\s]+)''');
  // A bare .m3u8 that isn't itself a player-wrapper page.
  static final _bareM3u8   = RegExp(r'''https?://[^"'\s]+\.m3u8[^"'\s]*''');

  /// Ordered, de-duplicated m3u8 candidates from a play.php body. Pure, so it's
  /// unit-tested. Prefers the inner m3u8 of a `?url=` wrapper over bare ones.
  static List<String> extractM3u8Candidates(String body) {
    final out = <String>[];
    for (final m in _wrappedUrl.allMatches(body)) {
      final inner = m.group(1)!;
      if (inner.contains('.m3u8') && !out.contains(inner)) out.add(inner);
    }
    for (final m in _bareM3u8.allMatches(body)) {
      final u = m.group(0)!;
      if (u.contains('/player') || u.contains('pages.dev')) continue; // wrapper
      if (!out.contains(u)) out.add(u);
    }
    return out;
  }

  Future<ResolvedStream> resolve(String reference) async {
    final path       = reference.substring(_scheme.length);
    final body       = await httpGetString(
      _http, Uri.parse('$_base/play.php/$path'), referer: '$_base/');
    final candidates = extractM3u8Candidates(body);
    if (candidates.isEmpty) {
      throw const FormatException('tflix: no direct source for this match');
    }

    // Race all candidates in parallel — first 200+#EXTM3U wins.
    // Sequential was worst-case 6 × 8 s; parallel is one round-trip.
    final probes    = candidates.take(6).toList();
    final completer = Completer<String>();
    var   settled   = 0;

    for (final url in probes) {
      _isPlayable(url).then((ok) {
        if (ok && !completer.isCompleted) completer.complete(url);
      }).whenComplete(() {
        if (++settled == probes.length && !completer.isCompleted) {
          completer.completeError(
            const FormatException('tflix: no reachable source for this match'));
        }
      });
    }

    final url = await completer.future;
    return ResolvedStream(url: url, httpHeaders: const {'User-Agent': _ua});
  }

  /// True if [url] returns 200 and an HLS manifest. Probed from the device so a
  /// mirror that's dead/geo-blocked *for this user* is correctly skipped.
  Future<bool> _isPlayable(String url) async {
    try {
      // Separate short-lived client per probe — avoids polluting the persistent
      // _http pool with dead CDN hosts.
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set(HttpHeaders.userAgentHeader, _ua);
        final resp = await req.close().timeout(const Duration(seconds: 8));
        if (resp.statusCode != HttpStatus.ok) return false;
        // '#EXTM3U' is always the first line of a valid HLS manifest — reading
        // the first response chunk is enough; no need to download the full file.
        final first = await resp.first.timeout(const Duration(seconds: 8));
        return utf8.decode(first, allowMalformed: true).trimLeft().startsWith('#EXTM3U');
      } finally {
        client.close(force: true); // also drains the socket
      }
    } catch (_) {
      return false;
    }
  }
}
