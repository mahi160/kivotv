import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/gradient_background.dart';
import '../models/channel.dart';
import '../services/playlist_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_DashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
    PlaylistRepository.instance.dashboardVersion.addListener(_reload);
  }

  @override
  void dispose() {
    PlaylistRepository.instance.dashboardVersion.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _dashboardFuture = _loadDashboard();
      });
    }
  }

  Future<_DashboardData> _loadDashboard() async {
    return _DashboardData(
      favorites: await PlaylistRepository.instance.favoriteChannels(),
      recent: await PlaylistRepository.instance.recentlyWatched(),
      pinned: await PlaylistRepository.instance.pinnedChannels(),
    );
  }

  void _open(Channel channel) {
    context.go('/player', extra: {'channel': channel});
  }

  Future<bool> _onWillPop() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Kivo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return exit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      body: GradientBackground(
        variant: GradientVariant.home,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.tvEdge,
              AppSpacing.tvHeaderGap,
              AppSpacing.tvEdge,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HomeHeader(),
                const SizedBox(height: 34),
                Expanded(
                  child: FutureBuilder<_DashboardData>(
                    future: _dashboardFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final data = snapshot.data!;
                      return ListView(
                        children: [
                          _DashboardSection(
                            icon: Icons.star_rounded,
                            title: 'Favorites',
                            channels: data.favorites,
                            emptyText: 'Press ★ on channels you love.',
                            onOpen: _open,
                          ),
                          _DashboardSection(
                            icon: Icons.history_rounded,
                            title: 'Recently watched',
                            channels: data.recent,
                            emptyText: 'Start watching to build your row.',
                            onOpen: _open,
                          ),
                          _DashboardSection(
                            icon: Icons.push_pin_rounded,
                            title: 'Pinned channels',
                            channels: data.pinned,
                            emptyText: 'Pin channels from All Channels.',
                            onOpen: _open,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.favorites,
    required this.recent,
    required this.pinned,
  });

  final List<Channel> favorites;
  final List<Channel> recent;
  final List<Channel> pinned;
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final left = Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _LogoMark(),
        SizedBox(width: 18),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kivo',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'Live TV launcher',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<int>(
          valueListenable: PlaylistRepository.instance.channelCount,
          builder: (_, count, _) => _StatPill(label: 'Channels', value: '$count'),
        ),
        const SizedBox(width: 14),
        ElevatedButton.icon(
          autofocus: true,
          onPressed: () => context.go('/channels'),
          icon: const Icon(Icons.grid_view_rounded),
          label: const Text('All Channels'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => context.go('/settings'),
          icon: const Icon(Icons.settings_rounded),
          label: const Text('Settings'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [left, const SizedBox(width: 36), actions]),
          );
        }

        return Row(children: [left, const Spacer(), actions]);
      },
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [AppColors.logoGradientStart, AppColors.logoGradientEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.logoGradientStart.withValues(alpha: 0.35),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.live_tv_rounded, size: 34, color: Colors.white),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.icon,
    required this.title,
    required this.channels,
    required this.emptyText,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final List<Channel> channels;
  final String emptyText;
  final ValueChanged<Channel> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.oceanBright),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 156,
            child: channels.isEmpty
                ? _EmptyRow(text: emptyText)
                : GridView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: channels.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 1,
                          mainAxisExtent: 250,
                          mainAxisSpacing: 14,
                        ),
                    itemBuilder: (context, index) => _ChannelCard(
                      channel: channels[index],
                      onTap: () => onOpen(channels[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white60, fontSize: 18),
      ),
    );
  }
}

class _ChannelCard extends StatefulWidget {
  const _ChannelCard({required this.channel, required this.onTap});

  final Channel channel;
  final VoidCallback onTap;

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(26),
        child: AnimatedScale(
          scale: _focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 130),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _focused
                    ? const [AppColors.focusCardStart, AppColors.focusCardEnd]
                    : [
                        Colors.white.withValues(alpha: 0.12),
                        Colors.white.withValues(alpha: 0.05),
                      ],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: _focused
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.12),
                width: _focused ? 2.5 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppColors.focusCardStart.withValues(alpha: 0.35),
                        blurRadius: 26,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tv_rounded, color: Colors.white70, size: 28),
                const Spacer(),
                Text(
                  widget.channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.channel.group ?? 'Ungrouped',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
