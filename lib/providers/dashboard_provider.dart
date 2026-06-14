import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel.dart';
import '../services/playlist_repository.dart';

// ── Dashboard data ────────────────────────────────────────────────────────────

class DashboardData {
  const DashboardData({
    required this.favorites,
    required this.recent,
  });

  final List<Channel> favorites;
  final List<Channel> recent;

  bool get isEmpty => favorites.isEmpty && recent.isEmpty;
}

// ── Bridge: PlaylistRepository.dashboardVersion ValueNotifier → Riverpod ─────
//
// Every time the repository bumps dashboardVersion (after pin/fav/refresh),
// this stream emits a new value, which causes dashboardProvider to rebuild.

final _dashboardVersionStreamProvider = StreamProvider<int>((ref) {
  final notifier = PlaylistRepository.instance.dashboardVersion;
  // Non-broadcast: buffers the seeded version number until StreamProvider
  // subscribes, so the dashboard rebuilds immediately on first watch.
  final ctrl = StreamController<int>();
  ctrl.add(notifier.value);

  void listener() => ctrl.add(notifier.value);
  notifier.addListener(listener);
  ref.onDispose(() {
    notifier.removeListener(listener);
    ctrl.close();
  });

  return ctrl.stream;
});

// ── Dashboard data provider ───────────────────────────────────────────────────
//
// Auto-refreshes whenever dashboardVersion changes (pin, favourite, refresh).
// Screens watch this instead of manually adding/removing ValueNotifier listeners.

final dashboardProvider =
    FutureProvider.autoDispose<DashboardData>((ref) async {
  // Re-run whenever the repository signals a change.
  ref.watch(_dashboardVersionStreamProvider);

  final repo = PlaylistRepository.instance;
  final results = await Future.wait([
    repo.favoriteChannels(),
    repo.recentlyWatched(),
  ]);

  return DashboardData(
    favorites: results[0],
    recent: results[1],
  );
});
