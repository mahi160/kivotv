import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../core/db/database_service.dart';
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

  // Two built-in sample channels so the app has content on first open.
  static const _sampleChannels = [
    Channel(
      id: 'sample-1live',
      name: '1LIVE',
      url: 'http://103.89.248.22:8082/1LIVE/tracks-a1/index.fmp4.m3u8'
           '?token=c3350d500806be60bc5c9a7859bdfb75e05c9021'
           '-bd999b1fab19a5867973b1040e73a267-1781457467-1781446667',
      group: 'Samples',
    ),
    Channel(
      id: 'sample-bpk-1723',
      name: 'BPK TV',
      url: 'https://owrcovcrpy.gpcdn.net/bpk-tv/1723/output/index.m3u8',
      group: 'Samples',
    ),
  ];

  Future<void> _bootstrap() async {
    // Store the two built-in sample channels (idempotent — safe on every launch).
    await _storeSampleChannels();

    final storedCount = await DatabaseService.instance.channelCount();
    channelCount.value = storedCount;
    _bumpDashboard();

    _bootstrapped = true;

    // Refresh any user-added playlists that are older than 24 h.
    _refreshStalePlaylists();
  }

  Future<void> _storeSampleChannels() async {
    final playlistId = await DatabaseService.instance.upsertPlaylist(
      name: 'Samples',
      url: 'kivo://samples',
    );
    await DatabaseService.instance.upsertChannels(
      playlistId: playlistId,
      channels: _sampleChannels,
    );
  }

  /// Refreshes user-added playlists that are stale (> 24 h old).
  /// Runs in the background — never blocks bootstrap or the UI.
  Future<void> _refreshStalePlaylists() async {
    isFetching.value = true;
    try {
      final playlists = await DatabaseService.instance.playlists();
      final userPlaylists = playlists.where((p) => !p.isBuiltIn).toList();
      if (userPlaylists.isEmpty) return;

      final now   = DateTime.now();
      final stale = userPlaylists.where((p) {
        final last = p.lastRefreshedDateTime;
        if (last == null) return true;
        return now.difference(last) > _refreshThreshold;
      }).toList();

      if (stale.isEmpty) return;
      await refreshAllPlaylists();
    } catch (_) {
      // Silent — stale data is shown gracefully.
    } finally {
      isFetching.value = false;
    }
  }

  Future<int> refreshPlaylist() => refreshAllPlaylists();

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

  Future<int> addAndRefreshPlaylist(String url) async {
    final playlistId = await addPlaylist(url: url);
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

  Future<List<Playlist>> playlists() => DatabaseService.instance.playlists();

  Future<void> deletePlaylist(int playlistId) async {
    final db = await DatabaseService.instance.database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
    final count = await DatabaseService.instance.channelCount();
    channelCount.value = count;
    _bumpDashboard();
  }

  Future<List<Channel>> channels({
    String query = '',
    int limit = 100,
    int offset = 0,
    bool includeBroken = false,
  }) {
    return DatabaseService.instance.channels(
      query: query,
      limit: limit,
      offset: offset,
      includeBroken: includeBroken,
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

  Future<void> markBroken(Channel channel) async {
    await DatabaseService.instance.markBroken(channel.url);
    channelCount.value = await DatabaseService.instance.channelCount();
    _bumpDashboard();
  }

  void _bumpDashboard() {
    dashboardVersion.value++;
  }
}
