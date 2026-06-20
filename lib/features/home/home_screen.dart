import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../core/widgets/app_nav_bar.dart';
import '../../core/widgets/channel_card.dart';
import '../../core/widgets/focusable_tap.dart';
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
            if (ref.watch(isFetchingProvider).asData?.value == true) ...([
              LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.oceanDeepBlue),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.tvEdge, 4, AppSpacing.tvEdge, 0,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.downloading_rounded,
                      size: 13,
                      color: AppColors.oceanDeepBlue.withValues(alpha: 0.70),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Fetching channels…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.oceanDeepBlue.withValues(alpha: 0.70),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
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
                    skipLoadingOnReload: true,
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('Failed to load dashboard: $e'),
                    ),
                    data: (data) {
                      // First-ever launch: nothing watched or favourited yet.
                      // Show a focusable CTA (autofocused) so the remote always
                      // lands on something pressable instead of an empty screen.
                      if (data.favorites.isEmpty && data.recent.isEmpty) {
                        return _EmptyHome(
                          onBrowse: () => context.go('/channels'),
                        );
                      }
                      // First non-empty section autofocuses its first card so
                      // the remote always lands on something pressable.
                      final favFirst = data.favorites.isNotEmpty;
                      return ListView(
                        // Clip.none so a focused card's scale + glow — including
                        // the leftmost card — is never cropped at the dashboard
                        // edge. Safe here: only two short rows, so this list
                        // never scrolls vertically, nothing bleeds over the nav.
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.only(
                          top:    AppSpacing.xs,
                          bottom: AppSpacing.xxl,
                        ),
                        children: [
                          _DashboardSection(
                            icon: Icons.star_rounded,
                            title: 'Favourites',
                            channels: data.favorites,
                            emptyText:
                                'Press MENU on any channel to add it here.',
                            onOpen: _open,
                            autofocusFirst: favFirst,
                          ),
                          const SizedBox(height: AppSpacing.tvSectionGap),
                          _DashboardSection(
                            icon: Icons.history_rounded,
                            title: 'Recently watched',
                            channels: data.recent,
                            emptyText: 'Channels you watch will appear here.',
                            onOpen: _open,
                            autofocusFirst: !favFirst,
                          ),
                        ],
                      );
                    },
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

/// One Home section rendered as a single horizontal "Netflix row" of big
/// channel cards. D-pad ◀ ▶ moves within the row; ▲ ▼ jumps between rows —
/// the most predictable possible navigation model on a TV remote.
class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.icon,
    required this.title,
    required this.channels,
    required this.emptyText,
    required this.onOpen,
    this.autofocusFirst = false,
  });

  final IconData icon;
  final String title;
  final List<Channel> channels;
  final String emptyText;
  final ValueChanged<Channel> onOpen;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ───────────────────────────────────────────────
        Row(
          children: [
            Icon(icon, color: AppColors.accent, size: AppSpacing.iconMd),
            const SizedBox(width: 12),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // ── Row of cards (or empty hint) ─────────────────────────────────
        channels.isEmpty
            ? _EmptyRow(text: emptyText)
            : SizedBox(
                height: AppSpacing.tvRowCardHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  // Clip.none so the focused card's scale + glow overflow the
                  // row band instead of being cropped.
                  clipBehavior: Clip.none,
                  // Generous cache so directional D-pad focus can reach (and
                  // auto-scroll to) cards just off the visible edge. cacheExtent
                  // is deprecated, but its typed replacement (ScrollCacheExtent)
                  // isn't exported from material/widgets yet, so the ignore stays.
                  // ignore: deprecated_member_use
                  cacheExtent: 1200,
                  itemCount: channels.length,
                  itemBuilder: (context, index) => Padding(
                    padding: EdgeInsets.only(
                      right: index == channels.length - 1
                          ? 0
                          : AppSpacing.tvRowGap,
                    ),
                    child: SizedBox(
                      width: AppSpacing.tvRowCardWidth,
                      child: ChannelCard(
                        channel:   channels[index],
                        autofocus: autofocusFirst && index == 0,
                        onTap:     () => onOpen(channels[index]),
                      ),
                    ),
                  ),
                ),
              ),
      ],
    );
  }
}

/// Calm empty-state hint shown when a section has no channels yet.
class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: AppSpacing.tvRowCardHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.oceanDeep : AppColors.lightSurface)
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: AppSpacing.iconMd,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.30),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// First-launch empty state: a focusable call-to-action that always grabs the
/// remote, so Home never opens with nothing selected.
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onBrowse});
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.focus(isDark);
    final onSurface =
        isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.live_tv_rounded,
              size: 72, color: AppColors.accent.withValues(alpha: 0.85)),
          const SizedBox(height: AppSpacing.md),
          Text('Nothing here yet',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              'Browse the channels to start watching — your favourites and '
              'recently watched will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FocusableTap(
            autofocus: true,
            onTap:     onBrowse,
            builder: (_, focused) => AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve:    Curves.easeOut,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: focused ? accent : accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                border: Border.all(
                    color: focused ? accent : Colors.transparent, width: 2),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color:        accent.withValues(alpha: 0.45),
                          blurRadius:   22,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.grid_view_rounded,
                      size: AppSpacing.iconMd,
                      color: focused ? Colors.white : onSurface),
                  const SizedBox(width: 10),
                  Text('Browse channels',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: focused ? Colors.white : onSurface,
                          )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
