import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../core/widgets/channel_card.dart';
import '../../core/widgets/circle_back_button.dart';
import '../../models/channel.dart';
import '../../providers/repository_provider.dart';
import '../../providers/sort_provider.dart';

/// Global search across every channel + live match. Reached from the nav-bar
/// search button. The field autofocuses (TV leanback IME); D-pad Down from the
/// field jumps into the results grid.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _pageSize = 60;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final List<Channel> _results = [];

  String _query = '';
  Timer? _debounce;
  bool _loading = false;
  bool _hasMore = false;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _results.clear();
        _offset = 0;
        _hasMore = _query.isNotEmpty;
        _loading = false;
      });
      if (_query.isNotEmpty) _loadNextPage();
    });
  }

  // ponytail: LIMIT/OFFSET paging over a table a background refresh may be
  // mutating concurrently can skip or duplicate a row between pages. Fine for
  // a TV search box; if it ever matters, switch to keyset pagination (order
  // by rowid > lastSeenRowid) which is stable under concurrent writes.
  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore || _query.isEmpty) return;
    // Capture before the await — if the user changes the query while we're
    // fetching, we discard the page instead of mixing it into the new query.
    final capturedQuery = _query;
    final capturedOffset = _offset;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(repositoryProvider)
          .channels(
            query: capturedQuery,
            limit: _pageSize,
            offset: capturedOffset,
            sortAlpha: ref.read(sortAlphaProvider),
          );
      if (!mounted) return;
      if (_query != capturedQuery || _offset != capturedOffset) {
        // Stale result — query or pagination changed while we were fetching.
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _results.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) _loadNextPage();
  }

  void _open(Channel c) =>
      context.push(AppRoutes.player, extra: {'channel': c});

  void _goBack() {
    if (_focus.hasFocus) {
      _focus.unfocus();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goBack();
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
                Row(
                  children: [
                    CircleBackButton(onTap: _goBack),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Focus(
                        onKeyEvent: (_, e) {
                          if (e is! KeyDownEvent) return KeyEventResult.ignored;
                          final k = e.logicalKey;
                          // ↓ moves focus into the results grid.
                          if (k == LogicalKeyboardKey.arrowDown) {
                            FocusScope.of(context).nextFocus();
                            return KeyEventResult.handled;
                          }
                          // Consume ↑ ← → so the TV focus system can’t steal
                          // focus away from the field and dismiss the keyboard.
                          if (k == LogicalKeyboardKey.arrowUp ||
                              k == LogicalKeyboardKey.arrowLeft ||
                              k == LogicalKeyboardKey.arrowRight) {
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          autofocus: true,
                          onChanged: _onChanged,
                          style: Theme.of(context).textTheme.titleMedium,
                          decoration: const InputDecoration(
                            filled: true,
                            hintText: 'Search channels & matches…',
                            prefixIcon: Icon(Icons.search_rounded, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(child: _buildResults()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    final t = Theme.of(context).textTheme.titleLarge;
    if (_query.isEmpty) {
      return Center(child: Text('Type to search', style: t));
    }
    if (_results.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(child: Text('No results for “$_query”', style: t));
    }
    final count = _results.length + (_hasMore ? 1 : 0);
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: AppSpacing.tvGridCardMaxExtent,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        mainAxisExtent: AppSpacing.tvGridCardExtent,
      ),
      itemCount: count,
      itemBuilder: (ctx, i) {
        if (i >= _results.length) {
          return const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        final c = _results[i];
        return ChannelCard(
          key: ValueKey(c.url),
          channel: c,
          autofocus: i == 0,
          onTap: () => _open(c),
        );
      },
    );
  }
}

