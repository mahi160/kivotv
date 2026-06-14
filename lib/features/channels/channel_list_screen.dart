import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../core/widgets/app_nav_bar.dart';
import '../../core/widgets/channel_logo.dart';
import '../../models/channel.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/playlist_repository.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class ChannelListScreen extends ConsumerStatefulWidget {
  const ChannelListScreen({super.key});

  @override
  ConsumerState<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends ConsumerState<ChannelListScreen> {
  static const _pageSize   = 60; // divisible by 3 keeps rows complete
  static const _crossCount = 3;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Channel> _channels = [];
  String _query   = '';
  Timer? _searchTimer;
  bool  _loading  = false;
  bool  _hasMore  = true;
  int   _offset   = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _resetAndLoad() {
    if (!mounted) return;
    setState(() {
      _channels.clear();
      _offset  = 0;
      _hasMore = true;
      _loading = false;
    });
    _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await PlaylistRepository.instance.channels(
        query: _query,
        limit: _pageSize,
        offset: _offset,
        includeBroken: true, // show broken channels grayed out
      );
      if (!mounted) return;
      setState(() {
        _channels.addAll(page);
        _offset  += page.length;
        _hasMore  = page.length == _pageSize;
        _loading  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) _loadNextPage();
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _query = value;
      _resetAndLoad();
    });
  }

  void _openPlayer(Channel channel) {
    if (channel.isBroken) return; // broken — do nothing
    context.go('/player', extra: {'channel': channel, 'query': _query});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<DashboardData>>(dashboardProvider, (prev, next) {
      if (next is AsyncData) _resetAndLoad();
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        body: GradientBackground(
          variant: GradientVariant.list,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.tvEdgeSm,
              AppSpacing.md,
              AppSpacing.tvEdgeSm,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppNavBar(active: NavDestination.channels),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _searchController,
                  autofocus: false,
                  onChanged: _onSearchChanged,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: 'Search channels…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(child: _buildGrid(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    if (_channels.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_channels.isEmpty) {
      return Center(
        child: Text(
          'No channels found',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      );
    }

    // Total items = channels + optional loading footer cell
    final footerCount = _hasMore ? 1 : 0;
    final itemCount   = _channels.length + footerCount;

    return GridView.builder(
      controller: _scrollController,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   _crossCount,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing:  AppSpacing.sm,
        mainAxisExtent:   180,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Footer spinner occupies one full row (spans via SizedBox width)
        if (index >= _channels.length) {
          return const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        final ch = _channels[index];
        return _ChannelCard(
          channel: ch,
          onTap: () => _openPlayer(ch),
          onToggleFavorite: () async {
            await PlaylistRepository.instance.setFavorite(ch, !ch.isFavorite);
            _resetAndLoad();
          },
          onTogglePin: () async {
            await PlaylistRepository.instance.setPinned(ch, !ch.isPinned);
            _resetAndLoad();
          },
        );
      },
    );
  }
}

// ── Grid card ─────────────────────────────────────────────────────────────────

class _ChannelCard extends StatefulWidget {
  const _ChannelCard({
    required this.channel,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onTogglePin,
  });

  final Channel      channel;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePin;

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool _focused = false;

  Channel get ch => widget.channel;

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final isBroken  = ch.isBroken;

    final card = FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale:    _focused ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 130),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            decoration: BoxDecoration(
              color: _focused
                  ? AppColors.oceanMid
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.black.withValues(alpha: 0.04)),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: _focused
                    ? AppColors.sandMid
                    : (isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder),
                width: _focused ? 2 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppColors.sandMid.withValues(alpha: 0.22),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Stack(
              children: [
                // ── Main content ─────────────────────────────────────────
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Logo or letter avatar
                    _Avatar(
                      logoUrl: ch.logo,
                      name:    ch.name,
                      size:    56,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Channel name
                    Text(
                      ch.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: isBroken
                            ? (isDark
                                ? Colors.white38
                                : Colors.black38)
                            : null,
                      ),
                    ),
                    // Provider / group
                    if (ch.group != null && ch.group!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        ch.group!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),

                // ── Status badges (top corners) ──────────────────────────
                if (ch.isFavorite || ch.isPinned)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (ch.isFavorite)
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: AppColors.sandMid,
                          )
                        else
                          const SizedBox.shrink(),
                        if (ch.isPinned)
                          const Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: AppColors.oceanBright,
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                  ),

                // ── Broken overlay ───────────────────────────────────────
                if (isBroken)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.signal_wifi_off_rounded,
                            size: 12,
                            color: Colors.white54,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Unavailable',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Action buttons on focus ──────────────────────────────
                if (_focused && !isBroken)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ActionBtn(
                          icon: ch.isFavorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: AppColors.sandMid,
                          onTap: widget.onToggleFavorite,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _ActionBtn(
                          icon: ch.isPinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          color: AppColors.oceanBright,
                          onTap: widget.onTogglePin,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Reduce opacity for broken streams
    if (isBroken) {
      return Opacity(opacity: 0.45, child: card);
    }
    return card;
  }
}

// ── Logo or letter avatar ─────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.logoUrl,
    required this.name,
    required this.size,
  });

  final String? logoUrl;
  final String  name;
  final double  size;

  @override
  Widget build(BuildContext context) {
    // Try the network logo first
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return ChannelLogo(logoUrl: url, size: size, borderRadius: size * 0.2);
    }

    // Fallback: first letter in a colored circle
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _letterColor(name),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.44,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }

  /// Deterministic pastel-ish colour from the channel name so each letter
  /// gets a consistent, visually distinct background.
  static Color _letterColor(String name) {
    const palette = [
      Color(0xFF1A5276), // deep ocean
      Color(0xFF1E8449), // forest green
      Color(0xFF6E2F8E), // purple
      Color(0xFF9C4B0A), // amber brown
      Color(0xFF1A6680), // teal
      Color(0xFF7B241C), // crimson
      Color(0xFF2E4057), // slate
      Color(0xFF4A235A), // violet
    ];
    if (name.isEmpty) return palette[0];
    final idx = name.codeUnits.fold(0, (a, b) => a ^ b) % palette.length;
    return palette[math.max(0, idx)];
  }
}

// ── Small action button ───────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
