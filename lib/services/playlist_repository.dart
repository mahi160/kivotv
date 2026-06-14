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

  Future<void> _bootstrap() async {
    // Ensure the default playlist record exists immediately so Settings
    // always shows it, even before channels have been fetched.
    await DatabaseService.instance.upsertPlaylist(
      name: 'IPTV Org',
      url: PlaylistService.playlistUrl,
    );

    final storedCount = await DatabaseService.instance.channelCount();
    channelCount.value = storedCount;

    _bootstrapped = true;

    // Fetch channels in the background (does not block app launch).
    _seedAndRefresh();
  }

  /// On first launch (no user playlists yet) adds the IPTV Org default and
  /// fetches its channels in the background.
  /// On subsequent launches refreshes playlists older than [_refreshThreshold].
  /// Never blocks bootstrap or the UI.
  Future<void> _seedAndRefresh() async {
    isFetching.value = true;
    try {
      final playlists = await DatabaseService.instance.playlists();
      final userPlaylists = playlists.where((p) => !p.isBuiltIn).toList();

      final storedCount = await DatabaseService.instance.channelCount();
      if (userPlaylists.isEmpty || storedCount == 0) {
        // No playlists yet, or playlists exist but channels are empty —
        // always fetch the default list to guarantee content on first open.
        await addAndRefreshPlaylist(PlaylistService.playlistUrl);
        return;
      }

      final now = DateTime.now();
      final stale = userPlaylists.where((p) {
        final last = p.lastRefreshedDateTime;
        if (last == null) return true;
        return now.difference(last) > _refreshThreshold;
      }).toList();

      if (stale.isEmpty) {
        return;
      }
      await refreshAllPlaylists();
    } catch (_) {
      // Background refresh failures are silent — the UI shows stale data gracefully.
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
