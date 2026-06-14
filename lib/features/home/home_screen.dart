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
                      // Clip.none + bottom padding so focus rings at the
                      // bottom of the last section are never cropped.
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.only(
                        bottom: AppSpacing.xxl,
                      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(icon, color: AppColors.oceanBright, size: 22),
            const SizedBox(width: 10),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // 3-column grid — shrinkWrap so it sizes to its content.
        // NeverScrollableScrollPhysics so the outer ListView drives scrolling.
        // Clip.none + padding so focus rings never get cropped.
        channels.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: _EmptyRow(text: emptyText),
              )
            : Padding(
                // Extra 8 px on all sides so the focus ring paints fully.
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: GridView.builder(
                  shrinkWrap: true,
                  clipBehavior: Clip.none,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:   3,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing:  AppSpacing.md,
                    mainAxisExtent:   190,
                  ),
                  itemCount: channels.length,
                  itemBuilder: (context, index) => ChannelCard(
                    channel: channels[index],
                    onTap: () => onOpen(channels[index]),
                  ),
                ),
              ),
        const SizedBox(height: AppSpacing.lg),
      ],
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
