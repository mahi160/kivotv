import 'dart:convert';
import 'dart:io';

/// Returns true if [url] responds with HTTP 200 and a valid HLS manifest
/// (first line starts with `#EXTM3U`).
///
/// A separate short-lived [HttpClient] is used per call so dead CDN hosts
/// never pollute a shared connection pool.
///
/// Used by [BdixtvResolver] and [TflixResolver] so HLS validation logic
/// stays in one place with consistent UTF-8 decoding.
Future<bool> isHlsManifest(
  String url, {
  Duration timeout = const Duration(seconds: 8),
  Map<String, String> headers = const {},
}) async {
  try {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
      for (final e in headers.entries) {
        req.headers.set(e.key, e.value);
      }
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != HttpStatus.ok) return false;
      // '#EXTM3U' is always the first line — reading the first chunk is enough.
      final first = await resp.first.timeout(timeout);
      return utf8
          .decode(first, allowMalformed: true)
          .trimLeft()
          .startsWith('#EXTM3U');
    } finally {
      client.close(force: true);
    }
  } catch (_) {
    return false;
  }
}
