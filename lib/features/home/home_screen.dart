import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../core/widgets/app_nav_bar.dart';
import '../../core/widgets/channel_card.dart';
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
          // Extra vertical space (8px each side) so focus ring never clips.
          SizedBox(
            height: 206, // 190 card + 8 top + 8 bottom
            child: channels.isEmpty
                ? _EmptyRow(text: emptyText)
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    // Horizontal padding gives focus ring room on both ends.
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
                    clipBehavior: Clip.none,
                    itemCount: channels.length,
                    itemExtent: 210, // card width + inter-card gap
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChannelCard(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
