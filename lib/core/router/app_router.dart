import 'package:go_router/go_router.dart';

import '../../models/channel.dart';
import '../../features/home/home_screen.dart';
import '../../features/player/player_screen.dart';
import '../../features/search/search_screen.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const search = '/search';
  static const player = '/player';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
    GoRoute(path: AppRoutes.search, builder: (_, _) => const SearchScreen()),
    GoRoute(
      path: AppRoutes.player,
      builder: (_, state) {
        final extra = state.extra as Map<String, Object?>?;
        final channel = extra?['channel'] as Channel?;
        if (channel == null) return const HomeScreen();
        final zapChannels =
            (extra?['zapChannels'] as List<Channel>?) ?? const [];
        return PlayerScreen(channel: channel, zapChannels: zapChannels);
      },
    ),
  ],
);

/// The current top-level route path, or null if the router isn't ready yet
/// (shouldn't happen post-bootstrap, but callers guard anyway).
String? get currentRoutePath {
  try {
    return appRouter.routerDelegate.currentConfiguration.uri.path;
  } catch (_) {
    return null;
  }
}
