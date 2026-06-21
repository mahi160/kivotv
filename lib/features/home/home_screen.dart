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
  // Timestamp of the last time this screen mounted. Used to swallow any
  // residual back event that arrives shortly after returning from the player:
  // on some TV firmware (TCL / Realtek) the back button fires through both
  // the key-event pipeline AND the Activity’s onBackPressed(), so the second
  // event can arrive on the home screen a few ms after the first navigated
  // away from the player. We ignore back-to-exit for 600 ms after mount.
  DateTime _mountedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset the guard whenever the route becomes active again (e.g. after
    // returning from the player via go('/')).
    _mountedAt = DateTime.now();
  }

  void _open(Channel channel) {
    context.push('/player', extra: {'channel': channel});
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final primary  = AppColors.primary(isDark);
    final isReady  = ref.watch(dashboardReadyProvider);
    final fetching    = ref.watch(isFetchingProvider).asData?.value == true;
    final fetchErrMsg = ref.watch(fetchErrorProvider).asData?.value;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Swallow back events that arrive within 600 ms of mounting.
        // Some TV firmware (e.g. TCL/Realtek) delivers KEYCODE_BACK through
        // both the key-event pipeline and onBackPressed() independently, so
        // the second copy can land here just after returning from the player.
        if (DateTime.now().difference(_mountedAt).inMilliseconds < 600) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: GradientBackground(
          variant: GradientVariant.home,
          child: Column(
            children: [
              // Slim error banner when a background fetch failed.
              if (fetchErrMsg != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.tvEdge, 6, AppSpacing.tvEdge, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 13,
                          color: AppColors.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fetchErrMsg,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

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
                        // ClipRect contains the list within its allocated
                        // space so rows scrolled above the viewport don’t
                        // bleed over the nav bar.
                        child: ClipRect(
                          child: RepaintBoundary(
                            child: isReady
                                ? _DashboardList(onOpen: _open)
                                : const Center(
                                    child: CircularProgressIndicator()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ),    // SafeArea
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
  final ValueChanged<Channel> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live   = ref.watch(liveMatchesProvider).value ?? [];
    final favs   = ref.watch(favoritesProvider).value ?? [];
    final recent = ref.watch(recentProvider).value ?? [];
    final groups = ref.watch(groupsProvider).value ?? [];

    // Exactly one section gets autofocus — the first non-empty one.
    var autofocusClaimed = false;
    bool claim(List<dynamic> list) {
      if (autofocusClaimed || list.isEmpty) return false;
      autofocusClaimed = true;
      return true;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xxl),
      children: [
        _ChannelSection(
          channels:       live,
          title:          'Live Now',
          live:           true,
          onOpen:         onOpen,
          makeCountLabel: (ch) => '${ch.length} matches',
          autofocusFirst: claim(live),
        ),
        _ChannelSection(
          channels:       favs,
          title:          'Favourites',
          onOpen:         onOpen,
          makeCountLabel: (ch) => '${ch.length} channels',
          autofocusFirst: claim(favs),
        ),
        _ChannelSection(
          channels:       recent,
          title:          'Recently watched',
          onOpen:         onOpen,
          autofocusFirst: claim(recent),
        ),
        _GroupsSection(onOpen: onOpen, autofocusFirst: claim(groups)),
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

  final List<Channel>                    channels;
  final String                           title;
  final ValueChanged<Channel>            onOpen;
  final String? Function(List<Channel>)? makeCountLabel;
  final bool                             live;
  final bool                             autofocusFirst;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DashboardSection(
          title:          title,
          live:           live,
          countLabel:     makeCountLabel?.call(channels),
          channels:       channels,
          onOpen:         onOpen,
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
            title:          groups[i].key,
            countLabel:     '${groups[i].value.length}',
            channels:       groups[i].value,
            onOpen:         onOpen,
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
              itemBuilder: (context, index) {
                final isFirst = index == 0;
                final isLast  = index == channels.length - 1;
                return Focus(
                  // Boundary guard: consume LEFT at the first card and RIGHT
                  // at the last card so D-pad navigation never escapes the row
                  // horizontally into another row.
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    final k = event.logicalKey;
                    if (isFirst && k == LogicalKeyboardKey.arrowLeft)  return KeyEventResult.handled;
                    if (isLast  && k == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
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
                              channel:   channels[index],
                              autofocus: autofocusFirst && isFirst,
                              onTap:     () => onOpen(channels[index]),
                            )
                          : ChannelCard(
                              channel:   channels[index],
                              autofocus: autofocusFirst && isFirst,
                              onTap:     () => onOpen(channels[index]),
                            ),
                    ),
                  ),
                );
              },
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
