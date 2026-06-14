import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/channel.dart';
import '../services/playlist_repository.dart';

class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({super.key});

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  final _searchController = TextEditingController();
  Future<List<Channel>>? _channelsFuture;
  String _query = '';
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    PlaylistRepository.instance.dashboardVersion.addListener(_loadChannels);
    _loadChannels();
  }

  @override
  void dispose() {
    PlaylistRepository.instance.dashboardVersion.removeListener(_loadChannels);
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadChannels() {
    if (!mounted) return;
    setState(() {
      _channelsFuture = PlaylistRepository.instance.allChannels(query: _query);
    });
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _query = value;
      _loadChannels();
    });
  }

  void _openPlayer(Channel channel) {
    context.go('/player', extra: {'channel': channel, 'query': _query});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF101B33), Color(0xFF060914)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(34, 24, 34, 18),
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
                  child: FutureBuilder<List<Channel>>(
                    future: _channelsFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final channels = snapshot.data!;
                      if (channels.isEmpty) {
                        return const Center(
                          child: Text(
                            'No channels found',
                            style: TextStyle(fontSize: 22),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: channels.length,
                        itemExtent: 86,
                        itemBuilder: (context, index) {
                          return _ChannelTile(
                            channel: channels[index],
                            onTap: () => _openPlayer(channels[index]),
                            onPinChanged: _loadChannels,
                          );
                        },
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
                      ? const Color(0xFFFFD166)
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
                      ? const Color(0xFF8AB4FF)
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
