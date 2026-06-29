import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'hls_probe.dart';
import 'http_get.dart';
import 'resolved_stream.dart';

/// Resolves a `tflix://<teams>/match_<id>` reference into a playable stream.
///
/// ### Architecture (as of mid-2026)
/// tflix.pro's play.php no longer embeds m3u8 URLs directly. Instead each
/// match card contains one or more `<iframe src="...">` pointing to an
/// external player page (tv.durbinlive.live, ex.roooom.online, etc.).
///
/// The primary player page (durbinlive) stores the stream URL inside a
/// XOR-encrypted blob:
///   • `const decryptionKey = "..."` — the XOR key
///   • `let encrypted = "..."` — base64(xor(plaintext, key))
/// Decrypting yields a JS snippet that contains:
///   • `mpdUrl` — an MPEG-DASH manifest (CENC-encrypted)
///   • `kid` / `key` — ClearKey DRM credentials
///
/// We try the iframe mirrors in order, returning the first one that yields a
/// valid stream URL. For MPD streams the ClearKey credentials are surfaced in
/// [ResolvedStream.drmClearKeys] so callers can configure the player.
///
/// Legacy `?url=<m3u8>` wrapper mirrors (if any remain) are still supported.
class TflixResolver {
  TflixResolver._();
  static final TflixResolver instance = TflixResolver._();

  static const _scheme = 'tflix://';
  static const _base = 'https://tflix.pro';
  static const _ua = 'Mozilla/5.0';

  static final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  static bool isResolvable(String reference) => reference.startsWith(_scheme);

  // ── Legacy: direct m3u8 inside a ?url= player wrapper ────────────────────
  static final _wrappedUrl = RegExp(r'''[?&]url=(https?://[^"'\s]+)''');
  static final _bareM3u8 = RegExp(r'''https?://[^"'\s]+\.m3u8[^"'\s]*''');

  /// Ordered, de-duplicated m3u8 candidates from a play.php body (legacy path).
  static List<String> extractM3u8Candidates(String body) {
    final out = <String>[];
    for (final m in _wrappedUrl.allMatches(body)) {
      final inner = m.group(1)!;
      if (inner.contains('.m3u8') && !out.contains(inner)) out.add(inner);
    }
    for (final m in _bareM3u8.allMatches(body)) {
      final u = m.group(0)!;
      if (u.contains('/player') || u.contains('pages.dev')) continue;
      if (!out.contains(u)) out.add(u);
    }
    return out;
  }

  // ── New: iframe → XOR-decrypt player page ────────────────────────────────

  /// Iframe src URLs embedded in the play.php body (ordered).
  static final _iframeSrc = RegExp(
    r'''<iframe[^>]+src=["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// XOR-decrypt: base64-decode [data], then XOR each byte with the [key]
  /// (cycling). Mirrors the JS used by the tflix player pages.
  static String xorDecrypt(String data, String key) {
    // Pad to valid base64 length.
    final padded = data + '=' * ((4 - data.length % 4) % 4);
    final bytes = base64.decode(padded);
    final keyBytes = utf8.encode(key);
    final out = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      out.writeCharCode(bytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    return out.toString();
  }

  static final _decryptionKeyRe = RegExp(
    r'''const decryptionKey\s*=\s*["']([^"']+)["']''',
  );
  static final _encryptedRe = RegExp(
    r'''let encrypted\s*=\s*["']([^"']+)["']''',
  );
  static final _mpdUrlRe = RegExp(r'''mpdUrl\s*=\s*['"]([^'"]+\.mpd[^'"]*)''');
  static final _kidRe = RegExp(r'''(?:const\s+)?kid\s*=\s*['"]([0-9a-f]+)['"]''');
  static final _keyRe = RegExp(r'''(?:const\s+)?key\s*=\s*['"]([0-9a-f]+)['"]''');

  /// Try to extract an MPD URL + ClearKey credentials from a player page that
  /// uses the XOR encryption scheme. Returns null if the pattern isn't present.
  static _DrmStream? _extractDrmStream(String playerBody) {
    final keyM = _decryptionKeyRe.firstMatch(playerBody);
    final encM = _encryptedRe.firstMatch(playerBody);
    if (keyM == null || encM == null) return null;

    final plaintext = xorDecrypt(encM.group(1)!, keyM.group(1)!);

    final mpdM = _mpdUrlRe.firstMatch(plaintext);
    if (mpdM == null) return null;

    final kidM = _kidRe.firstMatch(plaintext);
    final keyValM = _keyRe.firstMatch(plaintext);

    return _DrmStream(
      url: mpdM.group(1)!,
      kid: kidM?.group(1),
      key: keyValM?.group(1),
    );
  }

  // ── Resolution entry point ────────────────────────────────────────────────

  Future<ResolvedStream> resolve(String reference) async {
    final path = reference.substring(_scheme.length);
    final body = await httpGetString(
      _http,
      Uri.parse('$_base/play.php/$path'),
      referer: '$_base/',
    );

    // 1. Legacy path: direct m3u8 in play.php body.
    final candidates = extractM3u8Candidates(body);
    if (candidates.isNotEmpty) {
      return _resolveM3u8(candidates);
    }

    // 2. New path: iframe → player page → XOR decrypt → MPD + DRM.
    final iframes = _iframeSrc
        .allMatches(body)
        .map((m) => m.group(1)!.trim())
        .where((u) => u.startsWith('http'))
        .toList();

    if (iframes.isEmpty) {
      throw const FormatException('tflix: no stream source found for this match');
    }

    for (final iframeUrl in iframes.take(4)) {
      try {
        final playerBody = await _fetchPlayerPage(iframeUrl);

        // 2a. XOR-encrypted MPD.
        final drm = _extractDrmStream(playerBody);
        if (drm != null) {
          return ResolvedStream(
            url: drm.url,
            httpHeaders: const {'User-Agent': _ua},
            drmClearKeys:
                (drm.kid != null && drm.key != null)
                    ? {drm.kid!: drm.key!}
                    : null,
          );
        }

        // 2b. Legacy ?url=m3u8 pattern inside the player page.
        final innerCandidates = extractM3u8Candidates(playerBody);
        if (innerCandidates.isNotEmpty) {
          return _resolveM3u8(innerCandidates);
        }
      } catch (_) {
        continue; // dead mirror — try next
      }
    }

    throw const FormatException('tflix: no reachable source for this match');
  }

  Future<String> _fetchPlayerPage(String url) => httpGetString(
    HttpClient()..connectionTimeout = const Duration(seconds: 12),
    Uri.parse(url),
    referer: '$_base/',
  );

  /// Race m3u8 candidates in parallel — first real HLS manifest wins.
  Future<ResolvedStream> _resolveM3u8(List<String> candidates) async {
    final probes = candidates.take(6).toList();
    final completer = Completer<String>();
    var settled = 0;

    for (final url in probes) {
      _isPlayable(url)
          .then((ok) {
            if (ok && !completer.isCompleted) completer.complete(url);
          })
          .whenComplete(() {
            if (++settled == probes.length && !completer.isCompleted) {
              completer.completeError(
                const FormatException('tflix: no reachable HLS source'),
              );
            }
          });
    }

    final url = await completer.future;
    return ResolvedStream(url: url, httpHeaders: const {'User-Agent': _ua});
  }

  Future<bool> _isPlayable(String url) =>
      isHlsManifest(url, headers: const {HttpHeaders.userAgentHeader: _ua});
}

class _DrmStream {
  const _DrmStream({required this.url, this.kid, this.key});
  final String url;
  final String? kid;
  final String? key;
}
