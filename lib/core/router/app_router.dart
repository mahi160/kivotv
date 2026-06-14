import 'package:go_router/go_router.dart';

import '../../models/channel.dart';
import '../../features/channels/channel_list_screen.dart';
import '../../features/groups/groups_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/player/player_screen.dart';
import '../../features/settings/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/groups', builder: (_, _) => const GroupsScreen()),
    GoRoute(
      path: '/channels',
      builder: (_, state) {
        final group = state.uri.queryParameters['group'];
        return ChannelListScreen(groupFilter: group);
      },
    ),
    GoRoute(
      path: '/player',
      builder: (_, state) {
        final extra = state.extra as Map<String, Object?>?;
        final channel = extra?['channel'] as Channel?;
        final query = extra?['query'] as String? ?? '';
        final group = extra?['group'] as String?;
        if (channel == null) {
          return const ChannelListScreen();
        }
        return PlayerScreen(channel: channel, query: query, groupFilter: group);
      },
    ),
  ],
);
