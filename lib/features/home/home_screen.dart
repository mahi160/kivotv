import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_guard.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../core/widgets/app_nav_bar.dart';
import '../../core/widgets/channel_card.dart';
import '../../core/widgets/focusable_tap.dart';
import '../../core/widgets/settings_drawer.dart';
import '../../models/channel.dart';
import '../../providers/dashboard_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Armed on mount so any back echo that trails the navigation from the
  // player (see BackGuard) doesn't immediately exit the app.
  final _backGuard = BackGuard();

  @override
  void initState() {
    super.initState();
    _backGuard.arm();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-arm whenever the route becomes active again (e.g. after returning
    // from the player).
    _backGuard.arm();
  }

  void _open(Channel channel, [List<Channel> zapChannels = const []]) {
    context.push(AppRoutes.player, extra: {'channel': channel, 'zapChannels': zapChannels});
  }

  @override
  Widget build(BuildContext context) {
    final isReady = ref.watch(dashboardReadyProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_backGuard.swallow) return; // firmware back echo — ignore
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: GradientBackground(
            variant: GradientVariant.home,
            child: Column(
              children: [
                // ── Nav bar — fixed, never scrolls ──────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.tvEdge,
                    AppSpacing.sm,
                    AppSpacing.tvEdge,
                    0,
                  ),
                  child: AppNavBar(
                    onOpenMenu: () => showSettings(context),
                    onSearch: () => context.go('/search'),
                  ),
                ),
                const SizedBox(height: AppSpacing.tvHeaderGap),

                // ── Scrollable dashboard ──────────────────────────────
                Expanded(
                  child: RepaintBoundary(
                    child: isReady
                        ? _DashboardList(onOpen: _open)
                        : const _HomeSkeleton(),
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

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard list
// ─────────────────────────────────────────────────────────────────────────────

/// Reads all four section lists so it can give autofocus to exactly the first
/// non-empty section. Each _ChannelSection child is still its own ConsumerWidget
/// so only the affected row rebuilds on data changes.
class _DashboardList extends ConsumerWidget {
  const _DashboardList({required this.onOpen});
  final void Function(Channel, List<Channel>) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveMatchesProvider).value ?? [];
    final favs = ref.watch(favoritesProvider).value ?? [];
    final recent = ref.watch(recentProvider).value ?? [];
    final groups = ref.watch(groupsProvider).value ?? [];

    // Autofocus goes to the first non-empty section in display order
    // (Live → Favs → Recent → Groups) so the focused card is always near
    // the top of the list — Flutter's ensureVisible scroll won't push the
    // section header above the viewport.
    var autofocusClaimed = false;
    bool claim(List<Object?> list) {
      if (autofocusClaimed || list.isEmpty) return false;
      autofocusClaimed = true;
      return true;
    }

    final autofocusLive = claim(live);
    final autofocusFavs = claim(favs);
    final autofocusRecent = claim(recent);
    final autofocusGroups = claim(groups);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.tvEdge,
        AppSpacing.xs,
        AppSpacing.tvEdge,
        AppSpacing.xxl,
      ),
      children: [
        _ChannelSection(
          channels: live,
          title: 'Live Now',
          live: true,
          onOpen: (ch) => onOpen(ch, const []),
          makeCountLabel: (ch) => '${ch.length} matches',
          autofocusFirst: autofocusLive,
        ),
        _ChannelSection(
          channels: favs,
          title: 'Favourites',
          // ponytail: zap list = snapshot of favs at open time, session-scoped
          onOpen: (ch) => onOpen(ch, favs),
          makeCountLabel: (ch) => '${ch.length} channels',
          autofocusFirst: autofocusFavs,
        ),
        _ChannelSection(
          channels: recent,
          title: 'Recently watched',
          onOpen: (ch) => onOpen(ch, const []),
          autofocusFirst: autofocusRecent,
        ),
        _GroupsSection(onOpen: (ch) => onOpen(ch, const []), autofocusFirst: autofocusGroups),
      ],
    );
  }
}

/// Renders a [_DashboardSection] row when [channels] is non-empty.
class _ChannelSection extends StatelessWidget {
  const _ChannelSection({
    required this.channels,
    required this.title,
    required this.onOpen,
    this.makeCountLabel,
    this.live = false,
    this.autofocusFirst = false,
  });

  final List<Channel> channels;
  final String title;
  final ValueChanged<Channel> onOpen;
  final String? Function(List<Channel>)? makeCountLabel;
  final bool live;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DashboardSection(
          title: title,
          live: live,
          countLabel: makeCountLabel?.call(channels),
          channels: channels,
          onOpen: onOpen,
          autofocusFirst: autofocusFirst,
        ),
        const SizedBox(height: AppSpacing.tvSectionGap),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-section ConsumerWidgets
// ─────────────────────────────────────────────────────────────────────────────

class _GroupsSection extends ConsumerWidget {
  const _GroupsSection({required this.onOpen, this.autofocusFirst = false});
  final ValueChanged<Channel> onOpen;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // DB already caps to top 15 groups — no UI-level trim needed.
    final groups = ref.watch(groupsProvider).value ?? [];
    if (groups.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          _DashboardSection(
            title: groups[i].key,
            countLabel: '${groups[i].value.length}',
            channels: groups[i].value,
            onOpen: onOpen,
            autofocusFirst: autofocusFirst && i == 0,
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

  final String title;
  final List<Channel> channels;
  final ValueChanged<Channel> onOpen;
  final String? countLabel;
  final bool live;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Passenger Focus: invisible to traversal (canRequestFocus/skipTraversal)
      // but fires onFocusChange when any descendant card is focused. We use
      // this to scroll the *section* into view (header + cards together) rather
      // than just the focused card, so the header is never pushed above the
      // viewport.
      //
      // Deferred to addPostFrameCallback so our scroll always wins over any
      // same-frame horizontal scroll from FocusableTap.
      //
      // The Padding child adds 8 px above the header, which becomes part of
      // this Focus's RenderObject. ensureVisible(alignment:0) therefore lands
      // with 8 px of breathing room above the header text.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: title, countLabel: countLabel, live: live),
            const SizedBox(height: AppSpacing.sm),

            // RepaintBoundary per row: a focused card's scale animation stays
            // in its own compositor layer and doesn't repaint sibling rows.
            RepaintBoundary(
              child: SizedBox(
                height: live
                    ? AppSpacing.tvLiveCardHeight
                    : AppSpacing.tvRowCardHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  // ignore: deprecated_member_use
                  cacheExtent: 1200,
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final isFirst = index == 0;
                    final isLast = index == channels.length - 1;
                    return Focus(
                      // Boundary guard: invisible to traversal, but onKeyEvent fires for
                      // focused descendants. Consumes LEFT at the first card
                      // and RIGHT at the last so D-pad never escapes the row.
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        final k = event.logicalKey;
                        if (isFirst && k == LogicalKeyboardKey.arrowLeft) {
                          return KeyEventResult.handled;
                        }
                        if (isLast && k == LogicalKeyboardKey.arrowRight) {
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: isLast ? 0 : AppSpacing.tvRowGap,
                        ),
                        child: SizedBox(
                          width: live
                              ? AppSpacing.tvLiveCardWidth
                              : AppSpacing.tvRowCardWidth,
                          child: live
                              ? _LiveMatchCard(
                                  channel: channels[index],
                                  autofocus: autofocusFirst && isFirst,
                                  onTap: () => onOpen(channels[index]),
                                )
                              : ChannelCard(
                                  channel: channels[index],
                                  autofocus: autofocusFirst && isFirst,
                                  onTap: () => onOpen(channels[index]),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
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

  final Channel channel;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppColors.of(isDark);
    final surface = palette.surface;
    final accent = AppColors.focus(isDark);
    final text1 = palette.text1;
    final border = palette.border;

    return FocusableTap(
      autofocus: autofocus,
      onTap: onTap,
      builder: (_, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          transform: Matrix4.diagonal3Values(
            focused ? 1.03 : 1.0,
            focused ? 1.03 : 1.0,
            1.0,
          ),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: focused ? accent : border,
              width: focused ? 2 : 1,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
          child: Row(
            children: [
              ChannelAvatar(
                logoUrl: channel.logo,
                name: channel.name,
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: text1,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ),
            ],
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

  final String title;
  final String? countLabel;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (live) ...[const _LiveDot(), const SizedBox(width: 10)],
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 12),
        if (countLabel != null)
          live
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.live.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    countLabel!,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: AppColors.live,
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
// Live dot
// ─────────────────────────────────────────────────────────────────────────────

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppColors.live,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading skeleton
// ─────────────────────────────────────────────────────────────────────────────

/// Static shimmer shown while the dashboard providers first load.
/// No animation controller needed — the skeleton disappears after one
/// async tick (providers resolve from the in-memory Riverpod cache).
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.tvEdge,
        AppSpacing.xs,
        AppSpacing.tvEdge,
        AppSpacing.xxl,
      ),
      children: [
        for (var i = 0; i < 3; i++) ...[
          _SkeletonRect(
            color: color,
            width: 120,
            height: 16,
            radius: AppSpacing.radiusSm,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: AppSpacing.tvRowCardHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Fit as many cards as the available width allows, capped at
                // perGroupLimit (30) so we never render more skeletons than the
                // real row would show.
                const maxSkeletonCards = 30;
                final count = ((constraints.maxWidth + AppSpacing.tvRowGap) /
                        (AppSpacing.tvRowCardWidth + AppSpacing.tvRowGap))
                    .floor()
                    .clamp(1, maxSkeletonCards);
                return Row(
                  children: [
                    for (var j = 0; j < count; j++) ...[  
                      _SkeletonRect(
                        color: color,
                        width: AppSpacing.tvRowCardWidth,
                        height: AppSpacing.tvRowCardHeight,
                        radius: AppSpacing.radiusMd,
                      ),
                      if (j < count - 1)
                        const SizedBox(width: AppSpacing.tvRowGap),
                    ],
                  ],
                );
              },
            ),
          ),
          if (i < 2) const SizedBox(height: AppSpacing.tvSectionGap),
        ],
      ],
    );
  }
}

class _SkeletonRect extends StatelessWidget {
  const _SkeletonRect({
    required this.color,
    required this.width,
    required this.height,
    required this.radius,
  });
  final Color color;
  final double width, height, radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
