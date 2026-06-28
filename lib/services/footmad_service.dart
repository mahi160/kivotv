import 'dart:convert';
import 'dart:io';

import 'package:encrypt/encrypt.dart';

import '../models/channel.dart';
import 'http_get.dart';
import 'playlist_service.dart';

class FootmadCategory {
  const FootmadCategory({required this.name, required this.apiUrl});
  final String name;
  final String apiUrl;
}

/// Fetches the FootMad content catalog from the encrypted `/p.enc` endpoint,
/// then downloads every visible category's M3U playlist in parallel and returns
/// the combined channel list.
///
/// All channels are stored under a single `kivo://footmad` playlist so the
/// source can be toggled on/off as one unit in Settings.
class FootmadService {
  FootmadService._();
  static final FootmadService instance = FootmadService._();

  static const _catalogUrl =
      'https://footmad-api.haruntv2003.workers.dev/p.enc';

  // AES-256-CBC — key/IV from the app's DecryptionInterceptor.
  static final _key       = Key.fromUtf8('cricmad_secret_key_1234567890123');
  static final _iv        = IV.fromUtf8('cricmad_iv_12345');
  static final _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));

  /// Fetches and decrypts the catalog. Returns all visible categories.
  Future<List<FootmadCategory>> fetchCategories() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final raw = await httpGetString(client, Uri.parse(_catalogUrl));
      final json = _decrypt(raw.trim());
      return (jsonDecode(json)['categories'] as List)
          .cast<Map<String, dynamic>>()
          .where((c) => c['visible'] == true &&
              (c['api'] as String?)?.isNotEmpty == true)
          .map((c) => FootmadCategory(
                name:   (c['name'] as String).trim(),
                apiUrl: c['api'] as String,
              ))
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  /// Fetches, normalises, and deduplicates channels from a single category M3U.
  Future<List<Channel>> fetchCategoryChannels(String apiUrl) async {
    final channels = await PlaylistService.instance.fetchChannels(url: apiUrl);
    final seen = <String>{};
    return channels
        .map(_normalize)
        .where(_keep)
        .where((ch) => seen.add('${ch.group}\x00${ch.name.toLowerCase().trim()}'))
        .toList();
  }

  // ── Post-processing ───────────────────────────────────────────────────────

  static Channel _normalize(Channel ch) => ch.copyWith(
        group: _remapGroup(ch.group),
        logo:  _isBadLogo(ch.logo) ? null : ch.logo,
      );

  /// Drop promo channels and non-AV groups (Music, Movies, Entertainment).
  static bool _keep(Channel ch) {
    if (ch.name.toLowerCase().contains('welcome to play')) return false;
    const nonAv = {'Music', 'Hindi Movie', 'Entertainment'};
    return !nonAv.contains(ch.group);
  }

  /// Canonical group names for FootMad channels.
  static String? _remapGroup(String? raw) {
    final g = (raw ?? '').trim();
    if (g == 'Akash Bangla' || g == 'Akash Indian-Bangla' || g == 'Bangla') {
      return 'Bangla';
    }
    if (g == 'Akash Sports') return 'Akash Sports';
    // Everything else (empty, FIFA World Cup, Akash FIFA, Live Sports, Sports,
    // MLB Baseball, Boxing, etc.) collapses into Sports.
    return 'Sports';
  }

  /// Placeholder logos reused across many channels — strip so the app shows
  /// the letter-fallback tile instead of a wrong/generic image.
  static const _badLogos = {
    'https://i.postimg.cc/x8sgjYtH/resized-300x180-ffffff-12.jpg', // Akash Bangla placeholder
    'https://imglink.cc/cdn/RY7jBwPKAr.jpg',                        // Akash Sports placeholder
  };
  static bool _isBadLogo(String? logo) =>
      logo != null && _badLogos.contains(logo);

  String _decrypt(String base64Ciphertext) {
    return _encrypter.decrypt(
      Encrypted.fromBase64(base64Ciphertext),
      iv: _iv,
    );
  }
}
