import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/channel_group.dart';
import '../models/playlist.dart';
import '../core/db/database_service.dart';
import 'playlist_service.dart';

class PlaylistRepository {
  PlaylistRepository._();

  static final PlaylistRepository instance = PlaylistRepository._();

  static const exampleChannel = Channel(
    id: 'example-bpk-tv-1711',
    name: 'Example Channel',
    url: 'https://owrcovcrpy.gpcdn.net/bpk-tv/1711/output/index.m3u8',
    group: 'Example',
  );

  final ValueNotifier<int> channelCount = ValueNotifier<int>(0);
  final ValueNotifier<int> dashboardVersion = ValueNotifier<int>(0);

  bool _bootstrapped = false;
  Future<void>? _bootstrapFuture;

  Future<void> bootstrap() {
    if (_bootstrapped) return Future.value();
    return _bootstrapFuture ??= _bootstrap();
  }

  static const _refreshThreshold = Duration(hours: 24);

  Future<void> _bootstrap() async {
    var storedCount = await DatabaseService.instance.channelCount();
    channelCount.value = storedCount;
    debugPrint('Loaded $storedCount channels from SQLite');

    await _storeExampleChannel();
    storedCount = await DatabaseService.instance.channelCount();
    channelCount.value = storedCount;
    _bumpDashboard();

    _bootstrapped = true;

    // Background auto-refresh: if any playlist is stale, refresh silently.
    _autoRefreshIfStale();
  }

  /// Refreshes playlists that haven't been updated in [_refreshThreshold].
  /// Runs in the background — does not block the UI or bootstrap completion.
  Future<void> _autoRefreshIfStale() async {
    try {
      final playlists = await DatabaseService.instance.playlists();
      final now = DateTime.now();
      final stale = playlists.where((p) {
        if (p.isBuiltIn) return false;
        final last = p.lastRefreshedDateTime;
        if (last == null) return true;
        return now.difference(last) > _refreshThreshold;
      }).toList();

      if (stale.isEmpty) {
        debugPrint('All playlists are fresh — skipping auto-refresh');
        return;
      }

      debugPrint('Auto-refreshing ${stale.length} stale playlist(s)...');
      await refreshAllPlaylists();
    } catch (error, stackTrace) {
      debugPrint('Auto-refresh failed silently: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<int> refreshPlaylist() => refreshAllPlaylists();

  Future<int> refreshAllPlaylists() async {
    await addPlaylist(url: PlaylistService.playlistUrl, name: 'IPTV Org');
    await _storeExampleChannel();

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
      } catch (error, stackTrace) {
        debugPrint('Failed to refresh playlist ${playlist.url}: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    final count = await DatabaseService.instance.channelCount();
    channelCount.value = count;
    _bumpDashboard();
    debugPrint('Stored $count channels in SQLite');
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

  Future<void> _storeExampleChannel() async {
    final playlistId = await DatabaseService.instance.upsertPlaylist(
      name: 'Examples',
      url: 'kivo://examples',
    );
    await DatabaseService.instance.upsertChannels(
      playlistId: playlistId,
      channels: const [exampleChannel],
    );
  }

  Future<List<Playlist>> playlists() => DatabaseService.instance.playlists();

  Future<void> deletePlaylist(int playlistId) async {
    final db = await DatabaseService.instance.database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
    final count = await DatabaseService.instance.channelCount();
    channelCount.value = count;
    _bumpDashboard();
  }

  Future<List<ChannelGroup>> groups() => DatabaseService.instance.groups();

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

  Future<List<Channel>> allChannels({String query = ''}) {
    return DatabaseService.instance.allChannels(query: query);
  }

  Future<List<Channel>> pinnedChannels() =>
      DatabaseService.instance.pinnedChannels();

  Future<List<Channel>> favoriteChannels() =>
      DatabaseService.instance.favoriteChannels();

  Future<List<Channel>> recentlyWatched() =>
      DatabaseService.instance.recentlyWatched();

  Future<void> setPinned(Channel channel, bool pinned) async {
    await DatabaseService.instance.setPinned(channel.url, pinned);
    _bumpDashboard();
  }

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
