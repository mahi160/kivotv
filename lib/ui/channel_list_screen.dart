import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/gradient_background.dart';

import '../models/channel.dart';
import '../services/playlist_repository.dart';

class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({super.key});

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  static const _pageSize = 50;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Channel> _channels = [];
  String _query = '';
  Timer? _searchTimer;
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    PlaylistRepository.instance.dashboardVersion.addListener(_resetAndLoad);
    _scrollController.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    PlaylistRepository.instance.dashboardVersion.removeListener(_resetAndLoad);
    _searchTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _resetAndLoad() {
    if (!mounted) return;
    setState(() {
      _channels.clear();
      _offset = 0;
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
      );
      if (!mounted) return;
      setState(() {
        _channels.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadNextPage();
    }
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

  @override
  Widget build(BuildContext context) {
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
              AppSpacing.sm + 4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'All Channels',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 460,
                      child: TextField(
                        controller: _searchController,
                        autofocus: false,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(
                          hintText: 'Search name or group',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: _channels.isEmpty && _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _channels.isEmpty
                          ? const Center(
                              child: Text(
                                'No channels found',
                                style: TextStyle(fontSize: 22),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              // +1 for the loading footer
                              itemCount: _channels.length + (_hasMore ? 1 : 0),
                              itemExtent: 86,
                              itemBuilder: (context, index) {
                                if (index == _channels.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return _ChannelTile(
                                  channel: _channels[index],
                                  onTap: () => _openPlayer(_channels[index]),
                                  onPinChanged: _resetAndLoad,
                                );
                              },
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

class _ChannelTile extends StatefulWidget {
  const _ChannelTile({
    required this.channel,
    required this.onTap,
    required this.onPinChanged,
  });

  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback onPinChanged;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      child: AnimatedScale(
        scale: _focused ? 1.015 : 1,
        duration: const Duration(milliseconds: 110),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: _focused
                ? const Color(0xFF24456F)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _focused
                  ? const Color(0xFFBFD7FF)
                  : Colors.white.withValues(alpha: 0.10),
              width: _focused ? 2 : 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.22),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 6,
            ),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.live_tv_rounded),
            ),
            title: Text(
              widget.channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              widget.channel.group ?? 'Ungrouped',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: widget.channel.isFavorite
                      ? 'Unfavorite'
                      : 'Favorite',
                  icon: Icon(
                    widget.channel.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                  ),
                  color: widget.channel.isFavorite
                      ? AppColors.favActive
                      : Colors.white70,
                  onPressed: () async {
                    await PlaylistRepository.instance.setFavorite(
                      widget.channel,
                      !widget.channel.isFavorite,
                    );
                    widget.onPinChanged();
                  },
                ),
                IconButton(
                  tooltip: widget.channel.isPinned ? 'Unpin' : 'Pin',
                  icon: Icon(
                    widget.channel.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                  ),
                  color: widget.channel.isPinned
                      ? AppColors.pinActive
                      : Colors.white70,
                  onPressed: () async {
                    await PlaylistRepository.instance.setPinned(
                      widget.channel,
                      !widget.channel.isPinned,
                    );
                    widget.onPinChanged();
                  },
                ),
              ],
            ),
            onTap: widget.onTap,
          ),
        ),
      ),
    );
  }
}
