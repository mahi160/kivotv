import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../core/db/database_service.dart';
import 'iptvidn_channels.dart';
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

  bool _bootstrapped = false;
  Future<void>? _bootstrapFuture;

  Future<void> bootstrap() {
    if (_bootstrapped) return Future.value();
    return _bootstrapFuture ??= _bootstrap();
  }

  static const _refreshThreshold = Duration(hours: 24);
  static const _streamcrichdChannelCount = 51; // 0–50 inclusive.

  static const _seededKey = 'kivo_playlists_seeded_v3';
  static const _seededPlaylists = [
    (
      name: 'Ultimate IPTV',
      url:
          'https://raw.githubusercontent.com/mahi160/iptv_list/refs/heads/main/Ultimate.m3u',
    ),
  ];

  Future<void> _bootstrap() async {
    try {
      await _storeBuiltInChannels();
      await _storeStreamcrichdChannels();
      final storedCount = await DatabaseService.instance.channelCount();
      channelCount.value = storedCount;
      _bumpAll();
    } catch (e) {
      // Store failures are non-fatal — channels from previous launches may
      // already exist in the DB. Log and continue so the app never hangs.
      debugPrint('kivo bootstrap store error: $e');
    } finally {
      _bootstrapped = true;
    }
    // Fire-and-forget intentionally: bootstrap returns quickly so the UI can
    // show cached channels while the network refresh runs in the background.
    // _bootstrapped == true does NOT mean the refresh is complete.
    // ignore: unawaited_futures
    _seedAndRefresh();
  }

  Future<void> _storeBuiltInChannels() async {
    final playlistId = await DatabaseService.instance.upsertPlaylist(
      name: 'IPTV IDN',
      url: 'kivo://iptvidn',
    );
    await DatabaseService.instance.replaceChannels(
      playlistId: playlistId,
      channels: iptvidnChannels,
    );
  }

  Future<void> _storeStreamcrichdChannels() async {
    final playlistId = await DatabaseService.instance.upsertPlaylist(
      name: 'StreamCricHD',
      url: 'kivo://streamcrichd',
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

  Future<void> _seedAndRefresh() async {
    isFetching.value = true;
    fetchError.value = null;
    try {
      await refreshTflixMatches();

      final prefs = await SharedPreferences.getInstance();
      final alreadyDone = prefs.getBool(_seededKey) ?? false;

      if (!alreadyDone) {
        for (final p in _seededPlaylists) {
          await addAndRefreshPlaylist(p.url, name: p.name);
        }
        await prefs.setBool(_seededKey, true);
        return;
      }

      final playlists = await DatabaseService.instance.playlists();
      final userPlaylists = playlists.where((p) => !p.isBuiltIn).toList();
      if (userPlaylists.isEmpty) return;

      final now = DateTime.now();
      final stale = userPlaylists.where((p) {
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
      final matches = await TflixService.instance.fetchLiveMatches();
      _lastTflixScrape = DateTime.now();
      final playlistId = await DatabaseService.instance.upsertPlaylist(
        name: 'TFLIX Live',
        url: 'kivo://tflix',
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

  Future<void> manualRefresh() async {
    if (isFetching.value) return;
    isFetching.value = true;
    fetchError.value = null;
    try {
      await _clearImageCache();
      await refreshTflixMatches(force: true);
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
    final userPlaylists = playlists.where((p) => !p.isBuiltIn).toList();
    var failed = 0;

    for (final playlist in userPlaylists) {
      try {
        final channels = await PlaylistService.instance.fetchChannels(
          url: playlist.url,
        );
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

  Future<int> addPlaylist({required String url, String? name}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError('Enter a valid playlist URL');
    }
    return DatabaseService.instance.upsertPlaylist(
      name: name ?? uri.host,
      url: uri.toString(),
    );
  }

  Future<int> addAndRefreshPlaylist(String url, {String? name}) async {
    final playlistId = await addPlaylist(url: url, name: name);
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
  }) {
    return DatabaseService.instance.channels(
      query: query,
      group: group,
      limit: limit,
      offset: offset,
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

  void _bumpAll() {
    liveVersion.bump();
    favVersion.bump();
    recentVersion.bump();
    groupsVersion.bump();
  }
}
