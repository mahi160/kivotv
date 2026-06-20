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
import '../../services/playlist_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class ChannelListScreen extends ConsumerStatefulWidget {
  const ChannelListScreen({super.key});

  @override
  ConsumerState<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends ConsumerState<ChannelListScreen> {
  static const _pageSize = 60;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  // Single explicit focus node for the search field.
  // No FocusScopeNode for the grid — natural ReadingOrder traversal handles it.
  final _searchFocusNode  = FocusNode();

  final List<Channel> _channels = [];
  String _query   = '';
  Timer? _searchTimer;
  bool   _loading = false;
  bool   _hasMore = true;
  int    _offset  = 0;

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Keyboard-dismiss recovery (flutter/flutter#147772):
    // if the search keyboard closes and primaryFocus goes null, restore it
    // to the search field so the remote keeps working.
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _loadNextPage();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── keyboard-dismiss recovery ──────────────────────────────────────────────

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (FocusManager.instance.primaryFocus == null) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  // ── data ───────────────────────────────────────────────────────────────────

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
        query:  _query,
        limit:  _pageSize,
        offset: _offset,
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

    context.go('/player', extra: {'channel': channel, 'query': _query});
  }

  Future<void> _toggleFavorite(Channel channel) async {
    final newValue = !channel.isFavorite;
    await PlaylistRepository.instance.setFavorite(channel, newValue);
    if (!mounted) return;
    final idx = _channels.indexWhere((c) => c.url == channel.url);
    if (idx != -1) {
      setState(() {
        _channels[idx] = _channels[idx].copyWith(isFavorite: newValue);
      });
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // If keyboard was open for search, close it — stay on this screen.
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
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

                // ── Search field ─────────────────────────────────────────────
                // Wrapped in a plain Focus solely to intercept D-pad Down so
                // the user can jump straight to the grid without pressing Tab.
                // No FocusScopeNode — traversal continues naturally into the
                // grid below via ReadingOrderTraversalPolicy.
                Focus(
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      // Move to the next focusable widget (first grid card).
                      FocusScope.of(context).nextFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller:  _searchController,
                    focusNode:   _searchFocusNode,
                    autofocus:   false,
                    onChanged:   _onSearchChanged,
                    style:       Theme.of(context).textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      filled:     true,
                      hintText:   'Search channels…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // ── Channel grid ─────────────────────────────────────────────
                // No FocusScopeNode wrapper — grid cards are plain siblings in
                // the traversal tree. D-pad moves between them via the default
                // ReadingOrderTraversalPolicy (top-to-bottom, left-to-right).
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
      controller:    _scrollController,
      padding:       const EdgeInsets.all(AppSpacing.xs),
      clipBehavior:  Clip.none,
      gridDelegate:  const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: AppSpacing.tvGridCardMaxExtent,
        crossAxisSpacing:   AppSpacing.md,
        mainAxisSpacing:    AppSpacing.md,
        mainAxisExtent:     AppSpacing.tvGridCardExtent,
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
          key:                 ValueKey(ch.url),
          channel:             ch,
          onTap:               () => _openPlayer(ch),
          onFavoriteLongPress: () => _toggleFavorite(ch),
        );
      },
    );
  }
}
