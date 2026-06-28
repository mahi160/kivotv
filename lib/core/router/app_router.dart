import 'package:go_router/go_router.dart';

import '../../models/channel.dart';
import '../../features/home/home_screen.dart';
import '../../features/player/player_screen.dart';
import '../../features/search/search_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
    GoRoute(
      path: '/player',
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
