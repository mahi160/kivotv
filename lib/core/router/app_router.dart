import 'package:go_router/go_router.dart';

import '../../models/channel.dart';
import '../../features/channels/channel_list_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/player/player_screen.dart';
import '../../features/settings/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/channels', builder: (_, _) => const ChannelListScreen()),
    GoRoute(
      path: '/player',
      builder: (_, state) {
        final extra = state.extra as Map<String, Object?>?;
        final channel = extra?['channel'] as Channel?;
        final query  = extra?['query']   as String? ?? '';
        if (channel == null) return const ChannelListScreen();
        return PlayerScreen(channel: channel, query: query);
      },
    ),
  ],
);
