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
import '../../core/widgets/settings_drawer.dart';
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
    context.push('/player', extra: {'channel': channel});
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final primary  = AppColors.primary(isDark);
    final isReady  = ref.watch(dashboardReadyProvider);
    final fetching = ref.watch(isFetchingProvider).asData?.value == true;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: GradientBackground(
          variant: GradientVariant.home,
          child: Column(
            children: [
              // Slim progress bar during background playlist fetch.
              if (fetching) ...[
                LinearProgressIndicator(
                  minHeight:        3,
                  backgroundColor:  Colors.transparent,
                  valueColor:       AlwaysStoppedAnimation<Color>(primary),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.tvEdge, 4, AppSpacing.tvEdge, 0),
                  child: Row(
                    children: [
                      Icon(Icons.downloading_rounded, size: 13,
                          color: primary.withValues(alpha: 0.70)),
                      const SizedBox(width: 6),
                      Text(
                        'Fetching channels…',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: primary.withValues(alpha: 0.70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.tvEdge, AppSpacing.md,
                    AppSpacing.tvEdge, AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppNavBar(
                        onOpenMenu: () => showSettings(context),
                        onSearch:   () => context.go('/search'),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      Expanded(
                        // RepaintBoundary isolates the scrollable dashboard
                        // from the gradient background: focus animations and
                        // section repaints don't repaint the gradient layer.
                        child: RepaintBoundary(
                          child: isReady
                              ? _DashboardList(onOpen: _open)
                              : const Center(
                                  child: CircularProgressIndicator()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard list
// ─────────────────────────────────────────────────────────────────────────────

/// Pure layout widget — watches no providers itself. Each child section is its
/// own ConsumerWidget, so an update to one section (e.g. recentProvider on
/// markWatched) only rebuilds that section, not the others.
class _DashboardList extends StatelessWidget {
  const _DashboardList({required this.onOpen});
  final ValueChanged<Channel> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xxl),
      children: [
        _LiveSection(onOpen:   onOpen),
        _FavSection(onOpen:    onOpen),
        _RecentSection(onOpen: onOpen),
        _GroupsSection(onOpen: onOpen),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-section ConsumerWidgets
// ─────────────────────────────────────────────────────────────────────────────

class _LiveSection extends ConsumerWidget {
  const _LiveSection({required this.onOpen});
  final ValueChanged<Channel> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(liveMatchesProvider).value ?? [];
    if (channels.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DashboardSection(
          title:          'Live Now',
          live:           true,
          countLabel:     '${channels.length} matches',
          channels:       channels,
          onOpen:         onOpen,
          autofocusFirst: true,
        ),
        const SizedBox(height: AppSpacing.tvSectionGap),
      ],
    );
  }
}

class _FavSection extends ConsumerWidget {
  const _FavSection({required this.onOpen});
  final ValueChanged<Channel> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(favoritesProvider).value ?? [];
    if (channels.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DashboardSection(
          title:          'Favourites',
          countLabel:     '${channels.length} channels',
          channels:       channels,
          onOpen:         onOpen,
          autofocusFirst: true,
        ),
        const SizedBox(height: AppSpacing.tvSectionGap),
      ],
    );
  }
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection({required this.onOpen});
  final ValueChanged<Channel> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(recentProvider).value ?? [];
    if (channels.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DashboardSection(
          title:          'Recently watched',
          channels:       channels,
          onOpen:         onOpen,
          autofocusFirst: true,
        ),
        const SizedBox(height: AppSpacing.tvSectionGap),
      ],
    );
  }
}

class _GroupsSection extends ConsumerWidget {
  const _GroupsSection({required this.onOpen});
  final ValueChanged<Channel> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider).value ?? [];
    if (groups.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          _DashboardSection(
            title:          groups[i].key,
            countLabel:     '${groups[i].value.length}',
            channels:       groups[i].value,
            onOpen:         onOpen,
            autofocusFirst: true,
          ),
          if (i < groups.length - 1)
            const SizedBox(height: AppSpacing.tvSectionGap),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section widget (horizontal card row)
// ─────────────────────────────────────────────────────────────────────────────

/// One Home section rendered as a single horizontal "Netflix row" of channel
/// cards. D-pad ◀ ▶ moves within the row; ▲ ▼ jumps between rows.
class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.channels,
    required this.onOpen,
    this.countLabel,
    this.live = false,
    this.autofocusFirst = false,
  });

  final String              title;
  final List<Channel>       channels;
  final ValueChanged<Channel> onOpen;
  final String?             countLabel;
  final bool                live;
  final bool                autofocusFirst;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, countLabel: countLabel, live: live),
        const SizedBox(height: AppSpacing.md),

        // RepaintBoundary per row: a focused card's scale animation stays
        // in its own compositor layer and doesn't repaint sibling rows.
        RepaintBoundary(
          child: SizedBox(
            height: live
                ? AppSpacing.tvLiveCardHeight
                : AppSpacing.tvRowCardHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior:    Clip.none,
              // ignore: deprecated_member_use
              cacheExtent: 1200,
              itemCount:   channels.length,
              itemBuilder: (context, index) => Padding(
                padding: EdgeInsets.only(
                  right: index == channels.length - 1
                      ? 0
                      : AppSpacing.tvRowGap,
                ),
                child: SizedBox(
                  width: live
                      ? AppSpacing.tvLiveCardWidth
                      : AppSpacing.tvRowCardWidth,
                  child: live
                      ? _LiveMatchCard(
                          channel:   channels[index],
                          autofocus: autofocusFirst && index == 0,
                          onTap:     () => onOpen(channels[index]),
                        )
                      : ChannelCard(
                          channel:   channels[index],
                          autofocus: autofocusFirst && index == 0,
                          onTap:     () => onOpen(channels[index]),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live-match card
// ─────────────────────────────────────────────────────────────────────────────

class _LiveMatchCard extends StatelessWidget {
  const _LiveMatchCard({
    required this.channel,
    required this.onTap,
    this.autofocus = false,
  });

  final Channel      channel;
  final VoidCallback onTap;
  final bool         autofocus;

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.oceanDeep : AppColors.lightSurface;
    final accent  = AppColors.focus(isDark);
    final text1   = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final border  = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return FocusableTap(
      autofocus: autofocus,
      onTap:     onTap,
      builder: (_, focused) => AnimatedScale(
        scale:    focused ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve:    Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve:    Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: focused ? accent : border,
              width: focused ? 2 : 1,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
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
            children: [
              ChannelAvatar(
                logoUrl: channel.logo,
                name:    channel.name,
                size:    38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines:  2,
                  overflow:  TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color:      text1,
                    fontWeight: FontWeight.w600,
                    height:     1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.countLabel,
    required this.live,
  });

  final String  title;
  final String? countLabel;
  final bool    live;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (live) ...[
          // RepaintBoundary isolates the continuous pulsing-dot ticker from
          // the surrounding section header and card rows.
          const RepaintBoundary(child: _PulsingDot()),
          const SizedBox(width: 10),
        ],
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(width: 12),
        if (countLabel != null)
          live
              ? Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.live.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    countLabel!,
                    style: const TextStyle(
                      fontFamily:    'Outfit',
                      fontSize:      13,
                      fontWeight:    FontWeight.w700,
                      letterSpacing: 0.3,
                      color:         AppColors.live,
                    ),
                  ),
                )
              : Text(
                  countLabel!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing dot
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync:    this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.3).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.75).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut),
        ),
        child: Container(
          width: 10, height: 10,
          decoration: const BoxDecoration(
            color: AppColors.live,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
