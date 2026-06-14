import 'dart:async';
import 'dart:math' as math;

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
import '../../services/playlist_repository.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class ChannelListScreen extends ConsumerStatefulWidget {
  const ChannelListScreen({super.key});

  @override
  ConsumerState<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends ConsumerState<ChannelListScreen> {
  static const _pageSize   = 60;
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
        includeBroken: true,
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
    if (channel.isBroken) return;
    context.go('/player', extra: {'channel': channel, 'query': _query});
  }

  Future<void> _toggleFavorite(Channel channel) async {
    await PlaylistRepository.instance.setFavorite(channel, !channel.isFavorite);
    _resetAndLoad();
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
                Expanded(child: _buildGrid()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
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

    final itemCount = _channels.length + (_hasMore ? 1 : 0);

    return GridView.builder(
      controller: _scrollController,
      // Extra padding so focus borders on edge cells are never clipped.
      padding: const EdgeInsets.all(AppSpacing.xs),
      clipBehavior: Clip.none,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   _crossCount,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing:  AppSpacing.md,
        mainAxisExtent:   190,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= _channels.length) {
          return const Center(
            child: SizedBox(
              width: 32, height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        final ch = _channels[index];
        return _ChannelCard(
          key: ValueKey(ch.url),
          channel: ch,
          onTap: () => _openPlayer(ch),
          onFavoriteLongPress: () => _toggleFavorite(ch),
        );
      },
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _ChannelCard extends StatefulWidget {
  const _ChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
    required this.onFavoriteLongPress,
  });

  final Channel      channel;
  final VoidCallback onTap;
  final VoidCallback onFavoriteLongPress;

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool _focused = false;

  Channel get ch => widget.channel;

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final isBroken = ch.isBroken;

    // Surface & border colours adapt to dark / light mode.
    final surfaceColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.80);

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      // Outer padding so the focus border never touches the grid cell edge.
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg + 2),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.sandMid.withValues(alpha: 0.30),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : null,
        border: Border.all(
          color: _focused ? AppColors.sandMid : Colors.transparent,
          width: 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          color: _focused
              ? AppColors.oceanDeep
              : surfaceColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Content ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Avatar
                    _Avatar(logoUrl: ch.logo, name: ch.name, size: 60),
                    const SizedBox(height: 10),
                    // Channel name
                    Text(
                      ch.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _focused
                            ? Colors.white
                            : (isBroken
                                ? (isDark ? Colors.white30 : Colors.black26)
                                : null),
                        height: 1.25,
                      ),
                    ),
                    // Provider / group
                    if (ch.group != null && ch.group!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        ch.group!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _focused
                              ? Colors.white60
                              : (isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Favourite star badge ────────────────────────────────────
              if (ch.isFavorite)
                const Positioned(
                  top: 8,
                  right: 10,
                  child: Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: AppColors.sandMid,
                  ),
                ),

              // ── Broken badge ────────────────────────────────────────────
              if (isBroken)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.signal_wifi_off_rounded,
                              size: 11, color: Colors.white54),
                          SizedBox(width: 4),
                          Text(
                            'Unavailable',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // Dim broken channels
    if (isBroken) card = Opacity(opacity: 0.42, child: card);

    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onFavoriteLongPress,
        child: card,
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

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
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return ChannelLogo(
        logoUrl: url,
        size: size,
        borderRadius: size * 0.18,
      );
    }

    // Letter fallback
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _letterBg(name),
        borderRadius: BorderRadius.circular(size * 0.18),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.46,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }

  /// Stable colour derived from the channel name — same channel always
  /// gets the same colour, different channels get visually distinct ones.
  static Color _letterBg(String name) {
    const swatches = [
      Color(0xFF1A5276), // ocean blue
      Color(0xFF1E8449), // forest green
      Color(0xFF6E2F8E), // violet
      Color(0xFF9C4B0A), // amber
      Color(0xFF1A6680), // teal
      Color(0xFF7B241C), // crimson
      Color(0xFF2E4057), // slate
      Color(0xFF4A5568), // cool grey
    ];
    if (name.isEmpty) return swatches[0];
    final hash = name.codeUnits.fold(0, (a, b) => a ^ b);
    return swatches[math.max(0, hash.abs() % swatches.length)];
  }
}
