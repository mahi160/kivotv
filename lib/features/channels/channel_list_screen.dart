import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../core/widgets/app_nav_bar.dart';
import '../../core/widgets/channel_card.dart';
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

  final _searchController  = TextEditingController();
  final _scrollController  = ScrollController();
  final _searchFocusNode   = FocusNode();
  final _gridScopeNode     = FocusScopeNode();
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
    _searchFocusNode.dispose();
    _gridScopeNode.dispose();
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
        if (didPop) return;
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
          // Move focus into the channel grid so D-pad works immediately.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) { if (mounted) _gridScopeNode.requestFocus(); },
          );
          return;
        }
        context.go('/');
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
                // D-pad Down on the search field jumps straight to the grid.
                Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _gridScopeNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autofocus: false,
                    onChanged: _onSearchChanged,
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      filled: true,
                      hintText: 'Search channels…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: FocusScope(
                    node: _gridScopeNode,
                    child: _buildGrid(),
                  ),
                ),
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
        return ChannelCard(
          key: ValueKey(ch.url),
          channel: ch,
          onTap: () => _openPlayer(ch),
          onFavoriteLongPress: () => _toggleFavorite(ch),
        );
      },
    );
  }
}

