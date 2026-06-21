import 'dart:io';

import 'http_get.dart';

import 'resolved_stream.dart';

/// Turns an `iptvidn://<slug>` channel reference into a currently-playable HLS
/// URL (see CONTEXT.md → "stream resolution").
///
/// iptvidn channels have no stable playable URL: each play needs a per-slug
/// Flussonic token (~3 h) and the serving host rotates per request. A single
/// plain HTTP GET to `play.php?stream=<slug>` returns an `<iframe>` whose `src`
/// carries both host and token as plain text — no JavaScript/webview required
/// (see docs/adr/0001-iptvidn-on-click-resolution.md).
class IptvidnResolver {
  IptvidnResolver._();
  static final IptvidnResolver instance = IptvidnResolver._();

  static const _scheme = 'iptvidn://';
  static const _base   = 'http://iptvidn.com';

  // Persistent client — reuses the TCP connection to iptvidn.com across
  // consecutive channel switches, avoiding a fresh TCP handshake (~150 ms)
  // per resolution. Dart's HttpClient pools idle connections and handles
  // server-initiated closes automatically. Never call close() on this.
  static final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  /// `<iframe ... src="http://<host>:<port>/<slug>/embed.html?token=...">`
  static final _iframeSrc =
      RegExp(r'src="(https?://[^"]+/embed\.html\?[^"]*token=[^"]+)"');

  static bool isResolvable(String reference) => reference.startsWith(_scheme);

  Future<ResolvedStream> resolve(String reference) async {
    final slug = reference.substring(_scheme.length);
    final body = await httpGetString(
      _http,
      Uri.parse('$_base/play.php?stream=$slug'),
      referer: '$_base/',
    );
    return parsePlayResponse(body);
  }

  /// Parses a `play.php` response body into a playable stream. Pure (no I/O),
  /// so it is unit-tested directly.
  ///
  /// The HLS master is built from exactly what the server handed us — the host
  /// rotates and the path slug may differ in case from our reference, so both
  /// are derived from the embed URL rather than from the stored slug.
  static ResolvedStream parsePlayResponse(String body) {
    final match = _iframeSrc.firstMatch(body);
    if (match == null) {
      throw const FormatException('iptvidn: no embed iframe in play.php response');
    }
    final embed = Uri.parse(match.group(1)!);
    final token = embed.queryParameters['token'];
    if (token == null || token.isEmpty) {
      throw const FormatException('iptvidn: no token in embed URL');
    }
    final origin = '${embed.scheme}://${embed.host}:${embed.port}';
    final path   = embed.path.replaceFirst(RegExp(r'embed\.html$'), 'index.m3u8');
    // ponytail: token alone authorises the stream (verified); the embed's
    // `remote=no_check_ip` param isn't needed on the m3u8 request.
    return ResolvedStream(
      url:       '$origin$path?token=$token',
      expiresAt: _expiryOf(token),
    );
  }

  /// Flussonic token = `...-<expiry_unix>-<start_unix>` (trailing two integer
  /// fields; leading HMAC segments are hex and never contain dashes, but we
  /// parse from the right to be format-agnostic).
  /// Sanity-checks the result: expiry must be in the next 6 h, otherwise
  /// the field offsets are wrong and we return null so the reactive path
  /// handles any eventual 403 rather than scheduling a timer at a bad time.
  static DateTime? _expiryOf(String token) {
    final parts = token.split('-');
    if (parts.length < 2) return null;
    final seconds = int.tryParse(parts[parts.length - 2]);
    if (seconds == null) return null;
    final expiry = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final now    = DateTime.now();
    if (expiry.isBefore(now) || expiry.isAfter(now.add(const Duration(hours: 6)))) {
      return null; // parsed the wrong field; let reactive re-resolve handle it
    }
    return expiry;
  }
}
