import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel.dart';
import '../services/playlist_repository.dart';
import 'notifier_stream.dart';

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

// autoDispose so the listener is cleaned up when dashboardProvider
// (also autoDispose) leaves the tree.
final _dashboardVersionStreamProvider = StreamProvider.autoDispose<int>(
  (ref) =>
      valueNotifierStream(ref, PlaylistRepository.instance.dashboardVersion),
);

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
