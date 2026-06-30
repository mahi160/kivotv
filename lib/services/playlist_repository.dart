import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../core/db/database_service.dart';
import 'footmad_service.dart';
import 'local_iptv_service.dart';
import 'playlist_service.dart';
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
  final ValueNotifier<int> channelCount = ValueNotifier<int>(0);
  final ValueNotifier<bool> isFetching = ValueNotifier<bool>(false);

  /// Non-null while the last background fetch ended with an error.
  /// Cleared when a new fetch starts.
  final ValueNotifier<String?> fetchError = ValueNotifier<String?>(null);

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
  static const _streamcrichdChannelCount = 51; // 0–50 inclusive.

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
        await _storeIptvidnChannels();
        await _storeStreamcrichdChannels();
        await _storeLocalIptvChannels();
        // Remove old single-playlist footmad entry if present.
        await DatabaseService.instance.deletePlaylistByUrl('kivo://footmad');
        await prefs.setBool(_builtinSeededKey, true);
      }
      final storedCount = await DatabaseService.instance.channelCount();
      channelCount.value = storedCount;
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
        await DatabaseService.instance.upsertPlaylist(
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
    final playlists = await DatabaseService.instance.playlists();
    final enabled = playlists
        .where((p) => p.url.startsWith(_footmadPrefix) && p.enabled)
        .toList();
    if (enabled.isEmpty) return;
    final now = DateTime.now();
    final anyStale = enabled.any((p) {
      final last = p.lastRefreshedDateTime;
      return last == null || now.difference(last) > _refreshThreshold;
    });
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

    final playlists = await DatabaseService.instance.playlists();
    final enabled = playlists
        .where((p) => p.url.startsWith(_footmadPrefix) && p.enabled)
        .toList();

    await Future.wait(enabled.map((p) async {
      final apiUrl = apiByName[p.name];
      if (apiUrl == null) return; // category removed from API
      try {
        final channels =
            await FootmadService.instance.fetchCategoryChannels(apiUrl);
        await DatabaseService.instance.replaceChannels(
          playlistId: p.id,
          channels: channels,
        );
      } catch (e) {
        debugPrint('kivo footmad refresh [${p.name}]: $e');
      }
    }));

    channelCount.value = await DatabaseService.instance.channelCount();
    _bumpAll();
  }

  Future<void> _storeIptvidnChannels() async {
    final playlistId = await DatabaseService.instance.upsertPlaylist(
      name: 'IPTV IDN',
      url: 'kivo://iptvidn',
      defaultEnabled: false,
    );
    final json = await rootBundle.loadString('assets/iptvidn_channels.json');
    final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    final channels = list
        .map(
          (m) => Channel(
            id: m['id'] as String,
            name: m['name'] as String,
            url: m['url'] as String,
            logo: m['logo'] as String?,
            group: m['group'] as String?,
          ),
        )
        .toList();
    await DatabaseService.instance.replaceChannels(
      playlistId: playlistId,
      channels: channels,
    );
  }

  Future<void> _storeLocalIptvChannels() async {
    // Seed whatever the local server has right now. If unreachable (TV is off
    // the home LAN), LocalIptvService returns [] and we store an empty playlist
    // — the live channels just won't appear until the next manual refresh.
    final channels = await LocalIptvService.instance.fetchChannels();
    final playlistId = await DatabaseService.instance.upsertPlaylist(
      name: 'Local IPTV',
      url: 'kivo://localiptv',
    );
    if (channels.isNotEmpty) {
      await DatabaseService.instance.replaceChannels(
        playlistId: playlistId,
        channels: channels,
      );
    }
  }

  Future<void> _storeStreamcrichdChannels() async {
    final playlistId = await DatabaseService.instance.upsertPlaylist(
      name: 'StreamCricHD',
      url: 'kivo://streamcrichd',
      defaultEnabled: false,
    );
    await DatabaseService.instance.replaceChannels(
      playlistId: playlistId,
      channels: List.generate(_streamcrichdChannelCount, (i) {
        return Channel(
          id: 'streamcrichd-$i',
          name: 'StreamCricHD $i',
          url: 'https://streamcrichd.com/update/fetch.php?hd=$i',
          group: 'Live Sports',
        );
      }),
    );
  }

  Future<void> _seedAndRefresh(SharedPreferences prefs) async {
    isFetching.value = true;
    fetchError.value = null;
    try {
      await refreshTflixMatches();
      await _syncFootmadCategories();
      await _refreshFootmadIfStale();
      await _refreshLocalIptvIfEnabled();

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

      final playlists = await DatabaseService.instance.playlists();
      final userPlaylists = playlists.where((p) => !p.isBuiltIn).toList();
      if (userPlaylists.isEmpty) return;

      final now = DateTime.now();
      final stale = userPlaylists.where((p) => p.enabled).where((p) {
        final last = p.lastRefreshedDateTime;
        if (last == null) return true;
        return now.difference(last) > _refreshThreshold;
      }).toList();

      if (stale.isNotEmpty) await refreshAllPlaylists();
    } catch (e) {
      fetchError.value = 'Couldn\'t fetch channels — check your connection.';
    } finally {
      isFetching.value = false;
    }
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
      final playlists = await DatabaseService.instance.playlists();
      final tflix = playlists.where((p) => p.url == 'kivo://tflix').firstOrNull;
      if (tflix != null && !tflix.enabled) return;

      final matches = await TflixService.instance.fetchLiveMatches();
      _lastTflixScrape = DateTime.now();
      final playlistId = await DatabaseService.instance.upsertPlaylist(
        name: 'TFLIX Live',
        url: 'kivo://tflix',
        defaultEnabled: false,
      );
      await DatabaseService.instance.replaceChannels(
        playlistId: playlistId,
        channels: matches,
      );
      channelCount.value = await DatabaseService.instance.channelCount();
      // Only live matches changed — don't rebuild other sections.
      liveVersion.bump();
    } catch (_) {}
  }

  Future<void> _refreshLocalIptvIfEnabled() async {
    final playlists = await DatabaseService.instance.playlists();
    final p = playlists.where((p) => p.url == 'kivo://localiptv').firstOrNull;
    if (p == null || !p.enabled) return;
    final channels = await LocalIptvService.instance.fetchChannels();
    if (channels.isEmpty) return; // server unreachable — keep existing data
    await DatabaseService.instance.replaceChannels(
      playlistId: p.id,
      channels: channels,
    );
    channelCount.value = await DatabaseService.instance.channelCount();
    _bumpAll();
  }

  Future<void> manualRefresh() async {
    if (isFetching.value) return;
    isFetching.value = true;
    fetchError.value = null;
    try {
      await _clearImageCache();
      await refreshTflixMatches(force: true);
      await _syncFootmadCategories();
      await _refreshFootmadEnabled();
      await _refreshLocalIptvIfEnabled();
      await refreshAllPlaylists();
    } finally {
      isFetching.value = false;
    }
  }

  /// Purges both the in-memory Flutter image cache and the flutter_cache_manager
  /// disk cache so stale channel logos load fresh after a playlist refresh.
  Future<void> _clearImageCache() async {
    // In-memory: Flutter's own painting cache (holds decoded bitmaps).
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    // Disk: flutter_cache_manager's HTTP cache (stores raw network bytes).
    await DefaultCacheManager().emptyCache();
  }

  Future<int> refreshAllPlaylists() async {
    final playlists = await DatabaseService.instance.playlists();
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

    var failed = 0;
    for (final (playlist, channels) in fetched) {
      if (channels == null) {
        failed++;
        continue;
      }
      try {
        await DatabaseService.instance.replaceChannels(
          playlistId: playlist.id,
          channels: channels,
        );
      } catch (_) {
        failed++;
      }
    }

    // Surface an error only when every playlist failed — partial failures
    // (one bad source among many) are normal for public IPTV lists.
    if (userPlaylists.isNotEmpty && failed == userPlaylists.length) {
      fetchError.value = 'Couldn\'t fetch channels — check your connection.';
    }

    final count = await DatabaseService.instance.channelCount();
    channelCount.value = count;
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
    return DatabaseService.instance.upsertPlaylist(
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
    await DatabaseService.instance.replaceChannels(
      playlistId: playlistId,
      channels: channels,
    );
    final count = await DatabaseService.instance.channelCount();
    channelCount.value = count;
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
    return DatabaseService.instance.channels(
      query: query,
      group: group,
      limit: limit,
      offset: offset,
      sortAlpha: sortAlpha,
    );
  }

  Future<List<MapEntry<String, List<Channel>>>> groupedChannels() =>
      DatabaseService.instance.channelsByGroup();

  Future<List<Channel>> liveMatches() => DatabaseService.instance.liveMatches();

  Future<List<Channel>> favoriteChannels() =>
      DatabaseService.instance.favoriteChannels();

  Future<List<Channel>> recentlyWatched() =>
      DatabaseService.instance.recentlyWatched();

  Future<void> updateChannelName(Channel channel, String name) async {
    await DatabaseService.instance.updateChannelName(channel.url, name);
    // Name change is visible on cards in all sections — bump everything.
    _bumpAll();
  }

  Future<void> setFavorite(Channel channel, bool favorite) async {
    await DatabaseService.instance.setFavorite(channel.url, favorite);
    // Favorite state is shown across all sections (star badge on cards), so
    // we reload everything. setFavorite is a user action — frequency is low.
    _bumpAll();
  }

  Future<void> markWatched(Channel channel) async {
    await DatabaseService.instance.markWatched(channel.url);
    // Only the "Recently watched" section changes — don't reload Live / Fav /
    // Groups. This is the single biggest source of unnecessary dashboard
    // rebuilds (fires every time a channel starts playing).
    recentVersion.bump();
  }

  // ── Bump helpers ──────────────────────────────────────────────────────────

  Future<void> setPlaylistEnabled(int playlistId, {required bool enabled}) async {
    await DatabaseService.instance.setPlaylistEnabled(
      playlistId,
      enabled: enabled,
    );
    _bumpAll();
    playlistsVersion.bump();
  }

  Future<void> deletePlaylist(int id) async {
    await DatabaseService.instance.deletePlaylistById(id);
    _bumpAll();
    playlistsVersion.bump();
  }

  Future<DateTime?> lastWatchedAt() =>
      DatabaseService.instance.lastWatchedAt();

  Future<List<Playlist>> playlists() =>
      DatabaseService.instance.playlists();

  void _bumpAll() {
    liveVersion.bump();
    favVersion.bump();
    recentVersion.bump();
    groupsVersion.bump();
  }
}
