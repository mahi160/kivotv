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

class PlaylistRepository {
  PlaylistRepository._();

  static final PlaylistRepository instance = PlaylistRepository._();

  final ValueNotifier<int>  channelCount = ValueNotifier<int>(0);
  final ValueNotifier<bool> isFetching   = ValueNotifier<bool>(false);

  // ── Granular version notifiers ────────────────────────────────────────────
  //
  // Each notifier drives exactly one dashboard section provider. Bumping only
  // the relevant notifier means an update to one section (e.g. markWatched on
  // every channel play) doesn't trigger rebuilds in the other three sections.
  //
  //  liveVersion   ← refreshTflixMatches
  //  recentVersion ← markWatched
  //  favVersion    ← setFavorite, _bumpAll
  //  groupsVersion ← playlist refreshes, _bumpAll
  final ValueNotifier<int> liveVersion   = ValueNotifier<int>(0);
  final ValueNotifier<int> favVersion    = ValueNotifier<int>(0);
  final ValueNotifier<int> recentVersion = ValueNotifier<int>(0);
  final ValueNotifier<int> groupsVersion = ValueNotifier<int>(0);

  bool _bootstrapped = false;
  Future<void>? _bootstrapFuture;

  // One debounce timer per notifier so rapid bursts (e.g. multiple replaceChannels
  // calls during a refresh) coalesce into a single provider reload.
  Timer? _liveTimer;
  Timer? _favTimer;
  Timer? _recentTimer;
  Timer? _groupsTimer;

  Future<void> bootstrap() {
    if (_bootstrapped) return Future.value();
    return _bootstrapFuture ??= _bootstrap();
  }

  static const _refreshThreshold = Duration(hours: 24);

  static const _seededKey = 'kivo_playlists_seeded_v3';
  static const _seededPlaylists = [
    (
      name: 'Ultimate IPTV',
      url:  'https://raw.githubusercontent.com/mahi160/iptv_list/refs/heads/main/Ultimate.m3u',
    ),
  ];

  Future<void> _bootstrap() async {
    await _storeBuiltInChannels();

    final storedCount = await DatabaseService.instance.channelCount();
    channelCount.value = storedCount;
    _bumpAll();

    _bootstrapped = true;
    _seedAndRefresh();
  }

  Future<void> _storeBuiltInChannels() async {
    final playlistId = await DatabaseService.instance.upsertPlaylist(
      name: 'IPTV IDN',
      url:  'kivo://iptvidn',
    );
    await DatabaseService.instance.replaceChannels(
      playlistId: playlistId,
      channels:   iptvidnChannels,
    );
  }

  Future<void> _seedAndRefresh() async {
    isFetching.value = true;
    try {
      await refreshTflixMatches();

      final prefs       = await SharedPreferences.getInstance();
      final alreadyDone = prefs.getBool(_seededKey) ?? false;

      if (!alreadyDone) {
        for (final p in _seededPlaylists) {
          await addAndRefreshPlaylist(p.url, name: p.name);
        }
        await prefs.setBool(_seededKey, true);
        return;
      }

      final playlists    = await DatabaseService.instance.playlists();
      final userPlaylists = playlists.where((p) => !p.isBuiltIn).toList();
      if (userPlaylists.isEmpty) return;

      final now   = DateTime.now();
      final stale = userPlaylists.where((p) {
        final last = p.lastRefreshedDateTime;
        if (last == null) return true;
        return now.difference(last) > _refreshThreshold;
      }).toList();

      if (stale.isNotEmpty) await refreshAllPlaylists();
    } catch (_) {
    } finally {
      isFetching.value = false;
    }
  }

  DateTime? _lastTflixScrape;

  Future<void> refreshTflixMatches({
    bool force = false,
    Duration minInterval = const Duration(minutes: 2),
  }) async {
    final last = _lastTflixScrape;
    if (!force && last != null && DateTime.now().difference(last) < minInterval) {
      return;
    }
    try {
      final matches = await TflixService.instance.fetchLiveMatches();
      _lastTflixScrape = DateTime.now();
      final playlistId = await DatabaseService.instance.upsertPlaylist(
        name: 'TFLIX Live',
        url:  'kivo://tflix',
      );
      await DatabaseService.instance.replaceChannels(
        playlistId: playlistId,
        channels:   matches,
      );
      channelCount.value = await DatabaseService.instance.channelCount();
      // Only live matches changed — don't rebuild other sections.
      _bumpLive();
    } catch (_) {
    }
  }

  Future<void> manualRefresh() async {
    if (isFetching.value) return;
    isFetching.value = true;
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
    for (final playlist in playlists) {
      if (playlist.isBuiltIn) continue;
      try {
        final channels = await PlaylistService.instance.fetchChannels(
          url: playlist.url,
        );
        await DatabaseService.instance.replaceChannels(
          playlistId: playlist.id,
          channels:   channels,
        );
      } catch (_) {
      }
    }

    final count = await DatabaseService.instance.channelCount();
    channelCount.value = count;
    _bumpAll(); // channel data changed — refresh all sections
    return count;
  }

  Future<int> addPlaylist({required String url, String? name}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError('Enter a valid playlist URL');
    }
    return DatabaseService.instance.upsertPlaylist(
      name: name ?? uri.host,
      url:  uri.toString(),
    );
  }

  Future<int> addAndRefreshPlaylist(String url, {String? name}) async {
    final playlistId = await addPlaylist(url: url, name: name);
    final channels   = await PlaylistService.instance.fetchChannels(url: url.trim());
    await DatabaseService.instance.replaceChannels(
      playlistId: playlistId,
      channels:   channels,
    );
    final count = await DatabaseService.instance.channelCount();
    channelCount.value = count;
    _bumpAll();
    return count;
  }

  Future<List<Channel>> channels({
    String  query  = '',
    String? group,
    int     limit  = 100,
    int     offset = 0,
  }) {
    return DatabaseService.instance.channels(
      query:  query,
      group:  group,
      limit:  limit,
      offset: offset,
    );
  }

  Future<List<MapEntry<String, List<Channel>>>> groupedChannels() =>
      DatabaseService.instance.channelsByGroup();

  Future<List<Channel>> liveMatches() =>
      DatabaseService.instance.liveMatches();

  Future<List<Channel>> favoriteChannels() =>
      DatabaseService.instance.favoriteChannels();

  Future<List<Channel>> recentlyWatched() =>
      DatabaseService.instance.recentlyWatched();

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
    _bumpRecent();
  }

  // ── Bump helpers ──────────────────────────────────────────────────────────

  void _bumpLive() {
    _liveTimer?.cancel();
    _liveTimer = Timer(const Duration(milliseconds: 150),
        () => liveVersion.value++);
  }

  void _bumpFav() {
    _favTimer?.cancel();
    _favTimer = Timer(const Duration(milliseconds: 150),
        () => favVersion.value++);
  }

  void _bumpRecent() {
    _recentTimer?.cancel();
    _recentTimer = Timer(const Duration(milliseconds: 150),
        () => recentVersion.value++);
  }

  void _bumpGroups() {
    _groupsTimer?.cancel();
    _groupsTimer = Timer(const Duration(milliseconds: 150),
        () => groupsVersion.value++);
  }

  void _bumpAll() {
    _bumpLive();
    _bumpFav();
    _bumpRecent();
    _bumpGroups();
  }
}
