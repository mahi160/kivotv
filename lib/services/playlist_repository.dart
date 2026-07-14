import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../core/db/database_service.dart';
import 'footmad_service.dart';
import 'local_iptv_service.dart';
import 'playlist_service.dart';
import 'tflix_resolver.dart';
import 'tflix_service.dart';

/// A [ValueNotifier<int>] with a built-in 150 ms debounce. Rapid [bump]
/// calls coalesce into a single notification so downstream Riverpod providers
/// don't rebuild on every individual DB write during a batch refresh.
class DebouncedVersion extends ValueNotifier<int> {
  DebouncedVersion() : super(0);

  Timer? _timer;

  void bump() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 150), () => value++);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class PlaylistRepository {
  PlaylistRepository({DatabaseService? database})
    : _db = database ?? DatabaseService.instance;

  /// Injectable so tests can override with an in-memory stub instead of the
  /// hand-rolled [DatabaseService.instance] singleton.
  final DatabaseService _db;

  final ValueNotifier<bool> isFetching = ValueNotifier<bool>(false);

  // ── Granular version notifiers ────────────────────────────────────────────
  //  liveVersion   ← refreshTflixMatches
  //  recentVersion ← markWatched
  //  favVersion    ← setFavorite, _bumpAll
  //  groupsVersion ← playlist refreshes, _bumpAll
  final liveVersion = DebouncedVersion();
  final favVersion = DebouncedVersion();
  final recentVersion = DebouncedVersion();
  final groupsVersion = DebouncedVersion();
  /// Bumped whenever the playlist list itself changes (add, remove, toggle).
  final playlistsVersion = DebouncedVersion();

  bool _bootstrapped = false;
  Future<void>? _bootstrapFuture;

  Future<void> bootstrap() {
    if (_bootstrapped) return Future.value();
    return _bootstrapFuture ??= _bootstrap();
  }

  static const _refreshThreshold = Duration(hours: 24);

  static const _seededKey        = 'kivo_playlists_seeded_v4';
  /// Bumping this key forces built-in channels to re-seed on next launch
  /// (e.g. when the StreamCricHD channel count changes).
  // Bump this key to force a re-seed of all built-in channels on next launch.
  // v4: added LocalIptv (http://10.255.255.50) source.
  static const _builtinSeededKey = 'kivo_builtin_seeded_v4';

  // kivo://footmad/<name> — one playlist per FootMad category.
  static const _footmadPrefix = 'kivo://footmad/';
  // Only SportsOnly on by default; everything else user-enables.
  static const _footmadDefaultOn = {'SportsOnly'};

  // ── Built-in sources ────────────────────────────────────────────
  // One registry entry per simple kivo:// source: seeded once on install,
  // optionally re-fetched on refresh (refreshable: true). TFLIX and FootMad
  // have dedicated flows below — they genuinely differ (scrape throttling /
  // multi-playlist catalog).

  static const _streamcrichdChannelCount = 51; // 0–50 inclusive.

  static final _builtinSources = <({
    String name,
    String url,
    bool defaultEnabled,
    bool refreshable,
    Future<List<Channel>> Function() fetch,
  })>[
    (
      name: 'IPTV IDN',
      url: 'kivo://iptvidn',
      defaultEnabled: false,
      refreshable: false,
      fetch: _fetchIptvidnChannels,
    ),
    (
      name: 'StreamCricHD',
      url: 'kivo://streamcrichd',
      defaultEnabled: false,
      refreshable: false,
      fetch: _fetchStreamcrichdChannels,
    ),
    (
      name: 'Local IPTV',
      url: 'kivo://localiptv',
      defaultEnabled: true,
      // Re-fetched on refresh: the local server's lineup changes and the
      // seed may have run while the TV was off the home LAN.
      refreshable: true,
      fetch: LocalIptvService.instance.fetchChannels,
    ),
  ];

  static Future<List<Channel>> _fetchIptvidnChannels() async {
    final json = await rootBundle.loadString('assets/iptvidn_channels.json');
    final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    return [
      for (final m in list)
        Channel(
          id: m['id'] as String,
          name: m['name'] as String,
          url: m['url'] as String,
          logo: m['logo'] as String?,
          group: m['group'] as String?,
        ),
    ];
  }

  static Future<List<Channel>> _fetchStreamcrichdChannels() async {
    return List.generate(_streamcrichdChannelCount, (i) {
      return Channel(
        id: 'streamcrichd-$i',
        name: 'StreamCricHD $i',
        url: 'https://streamcrichd.com/update/fetch.php?hd=$i',
        group: 'Live Sports',
      );
    });
  }

  static const _seededPlaylists = [
    (
      name: 'Ultimate IPTV',
      url:
          'https://raw.githubusercontent.com/mahi160/iptv_list/refs/heads/main/Ultimate.m3u',
      defaultEnabled: true,
    ),
    (
      name: 'Bengali (IPTV-org)',
      url: 'https://iptv-org.github.io/iptv/languages/ben.m3u',
      defaultEnabled: false,
    ),
  ];

  Future<void> _bootstrap() async {
    final prefs       = await SharedPreferences.getInstance();
    final builtinDone = prefs.getBool(_builtinSeededKey) ?? false;
    try {
      // Only seed / clean built-ins once per install (or after a key bump).
      // Skipping on subsequent launches saves ~100 SQLite ops per start.
      if (!builtinDone) {
        await _seedBuiltinSources();
        // Remove old single-playlist footmad entry if present.
        await _db.deletePlaylistByUrl('kivo://footmad');
        await prefs.setBool(_builtinSeededKey, true);
      }
      _bumpAll();
      playlistsVersion.bump();
    } catch (e) {
      debugPrint('kivo bootstrap store error: $e');
    } finally {
      _bootstrapped = true;
    }
    // Fire-and-forget intentionally: bootstrap returns quickly so the UI can
    // show cached channels while the network refresh runs in the background.
    // _bootstrapped == true does NOT mean the refresh is complete.
    // ignore: unawaited_futures
    _seedAndRefresh(prefs);
  }

  /// Fetches the FootMad catalog and upserts a playlist row for every visible
  /// category. New categories default to enabled only if in [_footmadDefaultOn];
  /// existing rows keep whatever the user last set.
  Future<void> _syncFootmadCategories() async {
    try {
      final cats = await FootmadService.instance.fetchCategories();
      for (final cat in cats) {
        final url = '$_footmadPrefix${Uri.encodeComponent(cat.name)}';
        await _db.upsertPlaylist(
          name: cat.name,
          url: url,
          defaultEnabled: _footmadDefaultOn.contains(cat.name),
        );
      }
      playlistsVersion.bump();
    } catch (e) {
      debugPrint('kivo footmad sync error: $e');
    }
  }

  /// Refresh only when at least one enabled FootMad category is stale.
  Future<void> _refreshFootmadIfStale() async {
    final playlists = await _db.playlists();
    final enabled = playlists
        .where((p) => p.url.startsWith(_footmadPrefix) && p.enabled)
        .toList();
    if (enabled.isEmpty) return;
    final anyStale = enabled.any((p) => p.isStale(_refreshThreshold));
    if (anyStale) await _refreshFootmadEnabled();
  }

  Future<void> _refreshFootmadEnabled() async {
    List<FootmadCategory> cats;
    try {
      cats = await FootmadService.instance.fetchCategories();
    } catch (e) {
      debugPrint('kivo footmad catalog error: $e');
      return;
    }
    final apiByName = {for (final c in cats) c.name: c.apiUrl};

    final playlists = await _db.playlists();
    final enabled = playlists
        .where((p) => p.url.startsWith(_footmadPrefix) && p.enabled)
        .toList();

    await Future.wait(enabled.map((p) async {
      final apiUrl = apiByName[p.name];
      if (apiUrl == null) return; // category removed from API
      try {
        final channels =
            await FootmadService.instance.fetchCategoryChannels(apiUrl);
        await _db.replaceChannels(
          playlistId: p.id,
          channels: channels,
        );
      } catch (e) {
        debugPrint('kivo footmad refresh [${p.name}]: $e');
      }
    }));

    _bumpAll();
  }

  /// Seeds every registered built-in source: upsert the playlist row, fetch
  /// its channels, store them. An empty fetch (e.g. Local IPTV while off the
  /// home LAN) keeps the row but stores nothing — channels appear on the next
  /// refresh.
  Future<void> _seedBuiltinSources() async {
    for (final source in _builtinSources) {
      final playlistId = await _db.upsertPlaylist(
        name: source.name,
        url: source.url,
        defaultEnabled: source.defaultEnabled,
      );
      final channels = await source.fetch();
      if (channels.isNotEmpty) {
        await _db.replaceChannels(
          playlistId: playlistId,
          channels: channels,
        );
      }
    }
  }

  /// Re-fetches every refreshable built-in source that is currently enabled.
  Future<void> _refreshBuiltinsIfEnabled() async {
    final playlists = await _db.playlists();
    var changed = false;
    for (final source in _builtinSources.where((s) => s.refreshable)) {
      final p = playlists.where((x) => x.url == source.url).firstOrNull;
      if (p == null || !p.enabled) continue;
      final channels = await source.fetch();
      if (channels.isEmpty) continue; // unreachable — keep existing data
      await _db.replaceChannels(
        playlistId: p.id,
        channels: channels,
      );
      changed = true;
    }
    if (changed) {
      _bumpAll();
    }
  }

  Future<void> _seedAndRefresh(SharedPreferences prefs) async {
    isFetching.value = true;
    try {
      // All four flows are independent network work — run them in parallel.
      // SQLite writes are serialized by sqflite's transaction queue.
      // Each flow already logs/swallows its own errors, so nothing further
      // to surface here.
      await Future.wait([
        refreshTflixMatches(),
        _syncFootmadCategories().then((_) => _refreshFootmadIfStale()),
        _refreshBuiltinsIfEnabled(),
        _seedOrRefreshUserPlaylists(prefs),
      ]);
    } finally {
      isFetching.value = false;
    }
  }

  /// First launch: seed the bundled user playlists. Later launches: refresh
  /// any enabled user playlist older than [_refreshThreshold].
  Future<void> _seedOrRefreshUserPlaylists(SharedPreferences prefs) async {
    final alreadyDone = prefs.getBool(_seededKey) ?? false;

    if (!alreadyDone) {
      for (final p in _seededPlaylists) {
        await addAndRefreshPlaylist(
          p.url,
          name: p.name,
          defaultEnabled: p.defaultEnabled,
        );
      }
      await prefs.setBool(_seededKey, true);
      return;
    }

    final playlists = await _db.playlists();
    final userPlaylists = playlists.where((p) => !p.isBuiltIn).toList();
    if (userPlaylists.isEmpty) return;

    final anyStale = userPlaylists
        .where((p) => p.enabled)
        .any((p) => p.isStale(_refreshThreshold));

    if (anyStale) await refreshAllPlaylists();
  }

  DateTime? _lastTflixScrape;
  // In-flight guard: bootstrap, resume, and manual refresh can all call
  // refreshTflixMatches concurrently. Store the running future so concurrent
  // callers share one scrape instead of duplicating network + DB work.
  Future<void>? _tflixRefreshFuture;

  Future<void> refreshTflixMatches({
    bool force = false,
    Duration minInterval = const Duration(minutes: 2),
  }) {
    // Return the running future if a scrape is already in flight.
    final running = _tflixRefreshFuture;
    if (running != null) return running;

    final last = _lastTflixScrape;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < minInterval) {
      return Future.value();
    }
    return _tflixRefreshFuture = _doRefreshTflix().whenComplete(() {
      _tflixRefreshFuture = null;
    });
  }

  Future<void> _doRefreshTflix() async {
    try {
      // Skip network fetch if the TFLIX source is disabled.
      final playlists = await _db.playlists();
      final tflix = playlists.where((p) => p.url == 'kivo://tflix').firstOrNull;
      if (tflix != null && !tflix.enabled) return;

      final matches = await TflixService.instance.fetchLiveMatches();
      _lastTflixScrape = DateTime.now();
      final playlistId = await _db.upsertPlaylist(
        name: 'TFLIX Live',
        url: 'kivo://tflix',
        defaultEnabled: false,
      );
      await _db.replaceChannels(
        playlistId: playlistId,
        channels: matches,
      );
      // Only live matches changed — don't rebuild other sections.
      liveVersion.bump();
    } catch (_) {}
  }

  /// Refreshes every source. Image-cache purging is a UI-layer concern and is
  /// the caller's responsibility (see `core/image_cache_util.dart`) — this
  /// repository only touches the database.
  Future<void> manualRefresh() async {
    if (isFetching.value) return;
    isFetching.value = true;
    try {
      // Independent sources refresh in parallel; DB writes are serialized
      // by sqflite's transaction queue.
      await Future.wait([
        refreshTflixMatches(force: true),
        _syncFootmadCategories().then((_) => _refreshFootmadEnabled()),
        _refreshBuiltinsIfEnabled(),
        refreshAllPlaylists(),
      ]);
    } finally {
      isFetching.value = false;
    }
  }

  Future<int> refreshAllPlaylists() async {
    final playlists = await _db.playlists();
    final userPlaylists =
        playlists.where((p) => !p.isBuiltIn && p.enabled).toList();

    // Fetch all playlists in parallel — the slow part is the network.
    // DB writes are kept sequential to avoid SQLite write-lock contention.
    final fetched = await Future.wait(
      userPlaylists.map((p) async {
        try {
          return (p, await PlaylistService.instance.fetchChannels(url: p.url));
        } catch (_) {
          return (p, null);
        }
      }),
    );

    // Partial failures (one bad source among many) are normal for public
    // IPTV lists — store whatever came back and move on; nothing surfaces
    // fetch failures to the UI (see AUDIT.md P1-1).
    for (final (playlist, channels) in fetched) {
      if (channels == null) continue;
      try {
        await _db.replaceChannels(playlistId: playlist.id, channels: channels);
      } catch (_) {
        // Storage failure for this one playlist — others still commit.
      }
    }

    final count = await _db.channelCount();
    _bumpAll();
    return count;
  }

  Future<int> addPlaylist({
    required String url,
    String? name,
    bool defaultEnabled = true,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError('Enter a valid playlist URL');
    }
    return _db.upsertPlaylist(
      name: name ?? uri.host,
      url: uri.toString(),
      defaultEnabled: defaultEnabled,
    );
  }

  Future<int> addAndRefreshPlaylist(
    String url, {
    String? name,
    bool defaultEnabled = true,
  }) async {
    final playlistId = await addPlaylist(
      url: url,
      name: name,
      defaultEnabled: defaultEnabled,
    );
    final channels = await PlaylistService.instance.fetchChannels(
      url: url.trim(),
    );
    await _db.replaceChannels(
      playlistId: playlistId,
      channels: channels,
    );
    final count = await _db.channelCount();
    _bumpAll();
    return count;
  }

  Future<List<Channel>> channels({
    String query = '',
    String? group,
    int limit = 100,
    int offset = 0,
    bool sortAlpha = true,
  }) {
    return _db.channels(
      query: query,
      group: group,
      limit: limit,
      offset: offset,
      sortAlpha: sortAlpha,
    );
  }

  Future<List<MapEntry<String, List<Channel>>>> groupedChannels() =>
      _db.channelsByGroup(excludeUrlPrefix: TflixResolver.scheme);

  Future<List<Channel>> liveMatches() =>
      _db.liveMatches(urlPrefix: TflixResolver.scheme);

  Future<List<Channel>> favoriteChannels() =>
      _db.favoriteChannels();

  Future<List<Channel>> recentlyWatched() =>
      _db.recentlyWatched();

  Future<void> updateChannelName(Channel channel, String name) async {
    await _db.updateChannelName(channel.url, name);
    // Name change is visible on cards in all sections — bump everything.
    _bumpAll();
  }

  /// Seeded StreamCricHD channels carry placeholder names ("StreamCricHD 12")
  /// until a resolver discovers the real channel name mid-stream.
  static final _placeholderName = RegExp(r'^StreamCricHD \d+$');

  /// If [suggested] should replace [channel]'s seeded placeholder name,
  /// persists the rename and returns the updated channel. Null = keep as-is.
  Channel? adoptResolvedName(Channel channel, String? suggested) {
    if (suggested == null || suggested.isEmpty) return null;
    if (!_placeholderName.hasMatch(channel.name)) return null;
    unawaited(updateChannelName(channel, suggested));
    return channel.copyWith(name: suggested);
  }

  Future<void> setFavorite(Channel channel, bool favorite) async {
    await _db.setFavorite(channel.url, favorite);
    // Favorite state is shown across all sections (star badge on cards), so
    // we reload everything. setFavorite is a user action — frequency is low.
    _bumpAll();
  }

  Future<void> markWatched(Channel channel) async {
    await _db.markWatched(channel.url);
    // Only the "Recently watched" section changes — don't reload Live / Fav /
    // Groups. This is the single biggest source of unnecessary dashboard
    // rebuilds (fires every time a channel starts playing).
    recentVersion.bump();
  }

  // ── Bump helpers ──────────────────────────────────────────────────────────

  Future<void> setPlaylistEnabled(int playlistId, {required bool enabled}) async {
    await _db.setPlaylistEnabled(
      playlistId,
      enabled: enabled,
    );
    _bumpAll();
    playlistsVersion.bump();
  }

  Future<void> deletePlaylist(int id) async {
    await _db.deletePlaylistById(id);
    _bumpAll();
    playlistsVersion.bump();
  }

  Future<DateTime?> lastWatchedAt() =>
      _db.lastWatchedAt();

  Future<List<Playlist>> playlists() =>
      _db.playlists();

  void _bumpAll() {
    liveVersion.bump();
    favVersion.bump();
    recentVersion.bump();
    groupsVersion.bump();
  }
}
