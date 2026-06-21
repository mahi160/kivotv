import 'dart:convert';
import 'dart:io';

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

    // Step 2 — probe each server; return the first that exposes an m3u8.
    for (final s in servers) {
      try {
        final body = await httpGetString(
          _http,
          Uri.parse(
            '$_player?stream=1&id=${Uri.encodeComponent(s['id'] as String)}&t=$ts&pt=$pt',
          ),
          referer: _player,
        );
        final m = _m3u8Re.firstMatch(body);
        if (m != null) return ResolvedStream(url: m.group(0)!);
      } catch (_) {
        continue;
      }
    }

    throw const FormatException('bdix: no playable source found');
  }
}
