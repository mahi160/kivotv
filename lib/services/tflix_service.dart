import 'dart:async';
import 'dart:io';

import 'http_get.dart';

import '../models/channel.dart';
import 'tflix_resolver.dart';

/// Scrapes tflix.pro's homepage for LIVE sports matches and exposes them as
/// channels. Each match's `url` is a `tflix://<teams>/match_<id>` reference,
/// resolved to a playable HLS URL at play time by [TflixResolver].
///
/// Matches are time-bound events, so this is fetched at runtime (never
/// hardcoded) and refreshed on launch; finished matches drop off on the next
/// scrape (the caller stores them with replaceChannels, which prunes them).
class TflixService {
  TflixService._();
  static final TflixService instance = TflixService._();

  static const _home = 'https://tflix.pro/';

  Future<List<Channel>> fetchLiveMatches() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return parseLiveMatches(await httpGetString(client, Uri.parse(_home)));
    } finally {
      client.close(force: true);
    }
  }
}

// ── Pure parser (unit-tested) ───────────────────────────────────────────────

final _cardRe = RegExp(
  r'''data-status="(live|upcoming)"\s+onclick="location\.href='(play\.php/[^']+)'"''',
  caseSensitive: false,
);
final _teamRe = RegExp(
  r'team-name">\s*([^<]+?)\s*</div>',
  caseSensitive: false,
);
final _tagRe = RegExp(r'class="tag">\s*([^<]+?)\s*<', caseSensitive: false);

/// Parses tflix.pro's homepage into LIVE matches. Upcoming matches are skipped
/// (no stream exists yet). Each match card carries its status + play.php path;
/// the two team names and the competition tag live between this card and the
/// next, so we slice that window to read them.
List<Channel> parseLiveMatches(String html) {
  final cards = _cardRe.allMatches(html).toList();
  final out = <Channel>[];
  for (var i = 0; i < cards.length; i++) {
    final card = cards[i];
    if (card.group(1)!.toLowerCase() != 'live') continue;

    final path = card.group(2)!; // play.php/<teams>/match_<id>
    final end = i + 1 < cards.length ? cards[i + 1].start : html.length;
    final window = html.substring(card.end, end);

    final teams = _teamRe
        .allMatches(window)
        .map((m) => m.group(1)!.trim())
        .where((s) => s.isNotEmpty)
        .take(2)
        .toList();
    final tag = _cleanTag(_tagRe.firstMatch(window)?.group(1));

    final ref =
        '${TflixResolver.scheme}${path.substring('play.php/'.length)}';
    final name = teams.length == 2
        ? '${teams[0]} vs ${teams[1]}'
        : _humanize(path);
    out.add(
      Channel(id: ref, name: name, url: ref, group: tag ?? 'Live Sports'),
    );
  }
  return out;
}

String? _cleanTag(String? tag) {
  if (tag == null) return null;
  final t = tag.replaceAll('™', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? null : t;
}

String _humanize(String path) {
  final segs = path.split('/');
  final teams = segs.length > 1 ? segs[1] : path;
  return teams
      .split(RegExp(r'[_-]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
