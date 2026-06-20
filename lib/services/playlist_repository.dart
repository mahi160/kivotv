import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../core/db/database_service.dart';
import 'iptvidn_channels.dart';
import 'playlist_service.dart';

class PlaylistRepository {
  PlaylistRepository._();

  static final PlaylistRepository instance = PlaylistRepository._();

  final ValueNotifier<int>  channelCount     = ValueNotifier<int>(0);
  final ValueNotifier<int>  dashboardVersion = ValueNotifier<int>(0);
  /// True while a background playlist fetch is in progress.
  final ValueNotifier<bool> isFetching       = ValueNotifier<bool>(false);

  bool _bootstrapped = false;
  Future<void>? _bootstrapFuture;

  Future<void> bootstrap() {
    if (_bootstrapped) return Future.value();
    return _bootstrapFuture ??= _bootstrap();
  }

  static const _refreshThreshold = Duration(hours: 24);

  // Bumping the key version forces a re-seed on every existing install
  // when the default playlist list changes.
  static const _seededKey = 'kivo_playlists_seeded_v3';
  static const _seededPlaylists = [
    (
      name: 'Ultimate IPTV',
      url:  'https://raw.githubusercontent.com/mahi160/iptv_list/refs/heads/main/Ultimate.m3u',
    ),
  ];

  Future<void> _bootstrap() async {
    // Seed the built-in iptvidn channels (idempotent — safe on every launch).
    await _storeBuiltInChannels();

    final storedCount = await DatabaseService.instance.channelCount();
    channelCount.value = storedCount;
    _bumpDashboard();

    _bootstrapped = true;

    // Seed the default playlists once, then keep them refreshed.
    _seedAndRefresh();
  }

  /// The iptvidn channels are a hardcoded, built-in playlist (kivo:// URL, so
  /// the refresh logic never tries to HTTP-fetch it). Their `url` is an
  /// `iptvidn://<slug>` reference resolved at play time.
  Future<void> _storeBuiltInChannels() async {
    final playlistId = await DatabaseService.instance.upsertPlaylist(
      name: 'IPTV IDN',
      url:  'kivo://iptvidn',
    );
    await DatabaseService.instance.upsertChannels(
      playlistId: playlistId,
      channels:   iptvidnChannels,
    );
  }

  /// On first launch: adds the default playlists and fetches them.
  /// On subsequent launches: refreshes any user playlist older than 24 h.
  /// Never blocks bootstrap or the UI.
  Future<void> _seedAndRefresh() async {
    isFetching.value = true;
    try {
      final prefs       = await SharedPreferences.getInstance();
      final alreadyDone = prefs.getBool(_seededKey) ?? false;

      if (!alreadyDone) {
        // First launch: add and fetch the default playlists.
        for (final p in _seededPlaylists) {
          await addAndRefreshPlaylist(p.url, name: p.name);
        }
        await prefs.setBool(_seededKey, true);
        return; // counts already bumped inside addAndRefreshPlaylist
      }

      // Subsequent launches: refresh playlists older than 24 h.
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
      // Background failures are silent — the UI shows whatever is cached.
    } finally {
      isFetching.value = false;
    }
  }

  Future<int> refreshAllPlaylists() async {
    // Do NOT add any default playlist here.
    // Default seeding is handled once at first launch by _seedAndRefresh().
    // Re-adding IPTV Org every refresh would silently resurrect it after the
    // user deliberately deletes it from Settings.
    final playlists = await DatabaseService.instance.playlists();
    for (final playlist in playlists) {
      if (playlist.isBuiltIn) continue;

      try {
        final channels = await PlaylistService.instance.fetchChannels(
          url: playlist.url,
        );
        await DatabaseService.instance.replaceChannels(
          playlistId: playlist.id,
          channels: channels,
        );
      } catch (_) {
        // Individual playlist failures are non-fatal — continue refreshing others.
      }
    }

    final count = await DatabaseService.instance.channelCount();
    channelCount.value = count;
    _bumpDashboard();
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
    _bumpDashboard();
    return count;
  }

  Future<List<Channel>> channels({
    String query  = '',
    int    limit  = 100,
    int    offset = 0,
  }) {
    return DatabaseService.instance.channels(
      query:  query,
      limit:  limit,
      offset: offset,
    );
  }

  Future<List<Channel>> favoriteChannels() =>
      DatabaseService.instance.favoriteChannels();

  Future<List<Channel>> recentlyWatched() =>
      DatabaseService.instance.recentlyWatched();

  Future<void> setFavorite(Channel channel, bool favorite) async {
    await DatabaseService.instance.setFavorite(channel.url, favorite);
    _bumpDashboard();
  }

  Future<void> markWatched(Channel channel) async {
    await DatabaseService.instance.markWatched(channel.url);
    _bumpDashboard();
  }

  void _bumpDashboard() {
    dashboardVersion.value++;
  }
}
