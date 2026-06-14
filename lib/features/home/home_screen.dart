import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../core/widgets/app_nav_bar.dart';
import '../../core/widgets/channel_logo.dart';
import '../../models/channel.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/fetch_status_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
        child: Column(
          children: [
            // Slim progress bar shown while background playlist fetch runs.
            if (ref.watch(isFetchingProvider).asData?.value == true)
              LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.sandMid),
              ),
            Expanded(
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
                const AppNavBar(active: NavDestination.home),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: ref.watch(dashboardProvider).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('Failed to load dashboard: $e'),
                    ),
                    data: (data) => ListView(
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
                    ),
                  ),
                ),
              ],
            ),
          ),
          ), // Expanded
          ], // Column children
        ), // outer Column (GradientBackground child)
      ), // GradientBackground
    ), // Scaffold
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
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: AppSpacing.tvRowHeight,
            child: channels.isEmpty
                ? _EmptyRow(text: emptyText)
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: channels.length,
                    itemExtent: AppSpacing.tvCardWidth + AppSpacing.tvCardGap,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.tvCardGap),
                      child: _ChannelCard(
                        channel: channels[index],
                        onTap: () => onOpen(channels[index]),
                      ),
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
        style: Theme.of(context).textTheme.bodyLarge,
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
                ChannelLogo(
                  logoUrl: widget.channel.logo,
                  size: 40,
                  borderRadius: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                ),
                const Spacer(),
                Text(
                  widget.channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.channel.group ?? 'Ungrouped',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
