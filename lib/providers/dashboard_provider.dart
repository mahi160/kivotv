import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import 'notifier_stream.dart';
import 'repository_provider.dart';

// ── Per-section version streams ───────────────────────────────────────────────
//
// Each bridges exactly one PlaylistRepository.DebouncedVersion into Riverpod.
// Bumping only the relevant notifier (e.g. markWatched → recentVersion) means
// only that one section rebuilds, not the whole dashboard.

final _liveVersionStream = StreamProvider.autoDispose<int>(
  (ref) => valueNotifierStream(ref, ref.watch(repositoryProvider).liveVersion),
);
final _favVersionStream = StreamProvider.autoDispose<int>(
  (ref) => valueNotifierStream(ref, ref.watch(repositoryProvider).favVersion),
);
final _recentVersionStream = StreamProvider.autoDispose<int>(
  (ref) =>
      valueNotifierStream(ref, ref.watch(repositoryProvider).recentVersion),
);
final _groupsVersionStream = StreamProvider.autoDispose<int>(
  (ref) =>
      valueNotifierStream(ref, ref.watch(repositoryProvider).groupsVersion),
);
final _playlistsVersionStream = StreamProvider.autoDispose<int>(
  (ref) => valueNotifierStream(
    ref,
    ref.watch(repositoryProvider).playlistsVersion,
  ),
);

// ── Section data providers ────────────────────────────────────────────────────

final liveMatchesProvider = FutureProvider.autoDispose<List<Channel>>((
  ref,
) async {
  ref.watch(_liveVersionStream);
  return ref.watch(repositoryProvider).liveMatches();
});

final favoritesProvider = FutureProvider.autoDispose<List<Channel>>((
  ref,
) async {
  ref.watch(_favVersionStream);
  return ref.watch(repositoryProvider).favoriteChannels();
});

final recentProvider = FutureProvider.autoDispose<List<Channel>>((ref) async {
  ref.watch(_recentVersionStream);
  return ref.watch(repositoryProvider).recentlyWatched();
});

final playlistsProvider = FutureProvider.autoDispose<List<Playlist>>((ref) async {
  ref.watch(_playlistsVersionStream);
  return ref.watch(repositoryProvider).playlists();
});

final groupsProvider =
    FutureProvider.autoDispose<List<MapEntry<String, List<Channel>>>>((
      ref,
    ) async {
      ref.watch(_groupsVersionStream);
      return ref.watch(repositoryProvider).groupedChannels();
    });

// ── Ready flag ────────────────────────────────────────────────────────────────
//
// True once all four sections have resolved at least once. Used by HomeScreen
// to gate its loading spinner. Because resolved providers never go back to
// AsyncLoading (only AsyncData, possibly with skipLoadingOnReload), this
// transitions false → true exactly once per session, so HomeScreen rebuilds
// at most once from this provider.

final dashboardReadyProvider = Provider.autoDispose<bool>((ref) {
  // !isLoading is true for both AsyncData and AsyncError, so a single
  // failing provider never blocks the whole screen in skeleton forever.
  return !ref.watch(liveMatchesProvider).isLoading &&
      !ref.watch(favoritesProvider).isLoading &&
      !ref.watch(recentProvider).isLoading &&
      !ref.watch(groupsProvider).isLoading;
});
