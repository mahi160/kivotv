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
    context.go('/player', extra: {'channel': channel});
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColors.primary(isDark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back on Home leaves the app — standard TV behaviour, no confirm dialog.
        SystemNavigator.pop();
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
                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.tvEdge, 4, AppSpacing.tvEdge, 0,
                  ),
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
              ]),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.tvEdge,
                    AppSpacing.md,
                    AppSpacing.tvEdge,
                    AppSpacing.md,
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
                        child: ref.watch(dashboardProvider).when(
                          skipLoadingOnReload: true,
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(
                            child: Text('Failed to load dashboard: $e'),
                          ),
                          data: (data) {
                            // Transient first boot before channels seed.
                            if (data.isEmpty) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            final hasLive   = data.live.isNotEmpty;
                            final hasFav    = data.favorites.isNotEmpty;
                            final hasRecent = data.recent.isNotEmpty;
                            // The top-most row autofocuses its first card so the
                            // remote always lands on something pressable.
                            final afGroups = !hasLive && !hasFav && !hasRecent;
                            return ListView(
                              // Clips (default) so scrolling rows slide UNDER
                              // the fixed header instead of bleeding over it
                              // (= the header reads as sticky). Small L/R + top
                              // padding keeps the edge/first-row focus glow
                              // inside the clipped viewport.
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.sm,
                                AppSpacing.sm,
                                AppSpacing.sm,
                                AppSpacing.xxl,
                              ),
                              children: [
                                if (hasLive) ...[
                                  _DashboardSection(
                                    title: 'Live Now',
                                    live:  true,
                                    countLabel: '${data.live.length} matches',
                                    channels: data.live,
                                    emptyText: '',
                                    onOpen: _open,
                                    autofocusFirst: true,
                                  ),
                                  const SizedBox(height: AppSpacing.tvSectionGap),
                                ],
                                if (hasFav) ...[
                                  _DashboardSection(
                                    title: 'Favourites',
                                    countLabel: '${data.favorites.length} channels',
                                    channels: data.favorites,
                                    emptyText: '',
                                    onOpen: _open,
                                    autofocusFirst: !hasLive,
                                  ),
                                  const SizedBox(height: AppSpacing.tvSectionGap),
                                ],
                                if (hasRecent) ...[
                                  _DashboardSection(
                                    title: 'Recently watched',
                                    channels: data.recent,
                                    emptyText: '',
                                    onOpen: _open,
                                    autofocusFirst: !hasLive && !hasFav,
                                  ),
                                  const SizedBox(height: AppSpacing.tvSectionGap),
                                ],
                                // Everything else, one row per category.
                                for (var i = 0; i < data.groups.length; i++) ...[
                                  _DashboardSection(
                                    title:      data.groups[i].key,
                                    countLabel: '${data.groups[i].value.length}',
                                    channels:   data.groups[i].value,
                                    emptyText:  '',
                                    onOpen:     _open,
                                    autofocusFirst: afGroups && i == 0,
                                  ),
                                  if (i < data.groups.length - 1)
                                    const SizedBox(height: AppSpacing.tvSectionGap),
                                ],
                              ],
                            );
                          },
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

/// One Home section rendered as a single horizontal "Netflix row" of channel
/// cards. D-pad ◀ ▶ moves within the row; ▲ ▼ jumps between rows.
class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.channels,
    required this.emptyText,
    required this.onOpen,
    this.countLabel,
    this.live = false,
    this.autofocusFirst = false,
  });

  final String title;
  final List<Channel> channels;
  final String emptyText;
  final ValueChanged<Channel> onOpen;
  final String? countLabel;
  final bool live;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ───────────────────────────────────────────────
        _SectionHeader(title: title, countLabel: countLabel, live: live),
        const SizedBox(height: AppSpacing.md),

        // ── Row of cards (or empty hint) ─────────────────────────────────
        // Live matches use a slim logo+name card; everything else uses the
        // poster card.
        channels.isEmpty
            ? _EmptyRow(text: emptyText)
            : SizedBox(
                height: live
                    ? AppSpacing.tvLiveCardHeight
                    : AppSpacing.tvRowCardHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  // Generous cache so directional D-pad focus can reach (and
                  // auto-scroll to) cards just off the visible edge.
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
      ],
    );
  }
}

/// Slim live-match card: small logo + name on one line. Focus = accent ring +
/// glow + a light scale, matching the rest of the app's focus language.
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

/// Section header. The "Live Now" variant shows a pulsing red dot and a red
/// match-count badge; other sections show the title with a muted count.
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
          const _PulsingDot(),
          const SizedBox(width: 10),
        ],
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(width: 12),
        if (countLabel != null)
          live
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
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

/// Small pulsing red dot used in the Live Now header.
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
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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

