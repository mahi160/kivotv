import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel.dart';
import '../services/playlist_repository.dart';
import 'notifier_stream.dart';

// ── Per-section version streams ───────────────────────────────────────────────
//
// Each stream provider bridges exactly one PlaylistRepository version notifier
// into Riverpod. Bumping only the relevant notifier means, e.g., markWatched
// (fired on every channel play) only rebuilds the "Recently watched" section,
// not Live / Favourites / Groups.

final _liveVersionStream = StreamProvider.autoDispose<int>(
  (ref) => valueNotifierStream(ref, PlaylistRepository.instance.liveVersion),
);

final _favVersionStream = StreamProvider.autoDispose<int>(
  (ref) => valueNotifierStream(ref, PlaylistRepository.instance.favVersion),
);

final _recentVersionStream = StreamProvider.autoDispose<int>(
  (ref) => valueNotifierStream(ref, PlaylistRepository.instance.recentVersion),
);

final _groupsVersionStream = StreamProvider.autoDispose<int>(
  (ref) => valueNotifierStream(ref, PlaylistRepository.instance.groupsVersion),
);

// ── Section data providers ────────────────────────────────────────────────────

final liveMatchesProvider = FutureProvider.autoDispose<List<Channel>>((ref) async {
  ref.watch(_liveVersionStream);
  return PlaylistRepository.instance.liveMatches();
});

final favoritesProvider = FutureProvider.autoDispose<List<Channel>>((ref) async {
  ref.watch(_favVersionStream);
  return PlaylistRepository.instance.favoriteChannels();
});

final recentProvider = FutureProvider.autoDispose<List<Channel>>((ref) async {
  ref.watch(_recentVersionStream);
  return PlaylistRepository.instance.recentlyWatched();
});

final groupsProvider =
    FutureProvider.autoDispose<List<MapEntry<String, List<Channel>>>>((ref) async {
  ref.watch(_groupsVersionStream);
  return PlaylistRepository.instance.groupedChannels();
});

// ── Ready flag ────────────────────────────────────────────────────────────────
//
// True once all four sections have resolved at least once. Used by HomeScreen
// to gate its loading spinner. Because resolved providers never go back to
// AsyncLoading (only AsyncData, possibly with skipLoadingOnReload), this
// transitions false → true exactly once per session, so HomeScreen rebuilds
// at most once from this provider.

final dashboardReadyProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(liveMatchesProvider).hasValue &&
         ref.watch(favoritesProvider).hasValue &&
         ref.watch(recentProvider).hasValue &&
         ref.watch(groupsProvider).hasValue;
});
