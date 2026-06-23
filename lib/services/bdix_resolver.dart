import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'hls_probe.dart';
import 'http_get.dart';
import 'resolved_stream.dart';

/// Resolves a `bdixtv://onair` reference to a live HLS URL.
///
/// The bdix.my.id/onair switcher exposes a JSON server list; we probe each
/// entry in order and return the first page that contains an m3u8 URL.
class BdixtvResolver {
  BdixtvResolver._();
  static final BdixtvResolver instance = BdixtvResolver._();

  static const _scheme  = 'bdixtv://';
  static const _player  = 'https://bdix.my.id/onair/l.php';
  static const _referer = 'https://bdixtv.serverbd247.com/';
  // ponytail: token is hard-coded from DOMAIN_PROTECTION.token in l.php.
  // If streams stop resolving, re-fetch l.php and update this value.
  static const _token =
      'db581f658445b7dd9cd432556c2cfb0c7e9be27b9a5f6e3acedafa623826c324';

  static final _http   = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  static final _m3u8Re = RegExp(r'''https?://[^"'\s<>]+\.m3u8[^"'\s<>]*''');

  static bool isResolvable(String reference) => reference.startsWith(_scheme);

  Future<ResolvedStream> resolve(String reference) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final pt = Uri.encodeComponent(_token);

    // Step 1 — fetch the server list.
    final serversBody = await httpGetString(
      _http,
      Uri.parse('$_player?ajax=servers&nocache=$ts&pt=$pt'),
      referer: _referer,
    );
    final servers = (jsonDecode(serversBody)['servers'] as List)
        .cast<Map<String, dynamic>>();

    if (servers.isEmpty) throw const FormatException('bdix: no servers available');

    // Step 2 — probe all servers in parallel; return the first live m3u8.
    final completer = Completer<String>();
    var settled = 0;

    for (final s in servers) {
      _probeServer(s, ts, pt, completer).then((url) {
        if (url != null && !completer.isCompleted) completer.complete(url);
      }).whenComplete(() {
        if (++settled == servers.length && !completer.isCompleted) {
          completer.completeError(
              const FormatException('bdix: no playable source found'));
        }
      });
    }

    return ResolvedStream(url: await completer.future);
  }

  /// Fetches a server's stream URL from the bdix API and probes it.
  /// [done] is the shared race completer — checked between the two serial
  /// steps so that once a winner is found, remaining probes skip the
  /// expensive HLS manifest fetch.
  /// Returns the m3u8 URL if live, null otherwise.
  Future<String?> _probeServer(
      Map<String, dynamic> s, int ts, String pt, Completer<String> done) async {
    try {
      final body = await httpGetString(
        _http,
        Uri.parse(
          '$_player?stream=1&id=${Uri.encodeComponent(s['id'] as String)}&t=$ts&pt=$pt',
        ),
        referer: _player,
      );
      // Short-circuit if another probe already won while we were fetching.
      if (done.isCompleted) return null;
      final m = _m3u8Re.firstMatch(body);
      if (m == null) return null;
      final url = m.group(0)!;
      return await isHlsManifest(url, timeout: const Duration(seconds: 6))
          ? url
          : null;
    } catch (_) {
      return null;
    }
  }
}
