import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/channel_card.dart';
import '../../../core/widgets/focusable_tap.dart';
import '../../../models/channel.dart';

/// Slide-in sidebar showing the current channel list.
///
/// Supports client-side search and group filtering — no extra DB calls since
/// the full list is already in memory.
class ChannelListPanel extends StatefulWidget {
  const ChannelListPanel({
    super.key,
    required this.channels,
    required this.currentChannel,
    required this.scrollController,
    required this.onSelectChannel,
    required this.onToggleFavorite,
    this.onItemFocused,
    this.currentChannelFocusNode,
  });

  final List<Channel> channels;
  final Channel currentChannel;
  final ScrollController scrollController;
  final ValueChanged<Channel> onSelectChannel;
  final ValueChanged<Channel> onToggleFavorite;
  final ValueChanged<int>? onItemFocused;
  final FocusNode? currentChannelFocusNode;

  @override
  State<ChannelListPanel> createState() => _ChannelListPanelState();
}

class _ChannelListPanelState extends State<ChannelListPanel> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedGroup; // null = All

  List<String> get _groups {
    final seen = <String>{};
    final out = <String>[];
    for (final ch in widget.channels) {
      final g = ch.group;
      if (g != null && g.isNotEmpty && seen.add(g)) out.add(g);
    }
    return out;
  }

  List<Channel> get _filtered {
    var list = widget.channels;
    if (_selectedGroup != null) {
      list = list.where((c) => c.group == _selectedGroup).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  bool get _isFiltering => _query.isNotEmpty || _selectedGroup != null;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final groups = _groups;

    return Container(
      width: AppSpacing.tvSidebarWidth,
      decoration: const BoxDecoration(
        // Slightly lighter than pure black so the panel reads as a layer.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF2080D18), Color(0xF5060A14)],
        ),
        border: Border(
          left: BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          _Header(
            total: widget.channels.length,
            filtered: _isFiltering ? filtered.length : null,
          ),

          // ── Search ─────────────────────────────────────────────────────
          _SearchField(
            controller: _searchController,
            onChanged: (q) => setState(() => _query = q),
            onClear: () {
              setState(() => _query = '');
              _searchController.clear();
            },
          ),

          // ── Group tabs ─────────────────────────────────────────────────
          if (groups.length > 1)
            _GroupTabs(
              groups: groups,
              selected: _selectedGroup,
              onSelect: (g) => setState(
                () => _selectedGroup = _selectedGroup == g ? null : g,
              ),
            ),

          const SizedBox(height: 4),

          // ── Channel list ────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(isFiltering: _isFiltering)
                : ListView.builder(
                    controller:
                        _isFiltering ? null : widget.scrollController,
                    itemCount: filtered.length,
                    // Keep fixed extent only when unfiltered so the parent
                    // can still use O(1) jumpTo on sidebar open.
                    itemExtent:
                        _isFiltering ? null : AppSpacing.tvSidebarTile,
                    // ignore: deprecated_member_use
                    cacheExtent: 1200,
                    itemBuilder: (ctx, index) {
                      final ch = filtered[index];
                      final isCurrent = ch.url == widget.currentChannel.url;
                      // When filtering, global index is unknown — pass -1 so
                      // wrap-around logic in the player is disabled.
                      final globalIndex = _isFiltering
                          ? -1
                          : index;
                      return _SidebarItem(
                        channel: ch,
                        isCurrent: isCurrent,
                        focusNode:
                            isCurrent && !_isFiltering
                                ? widget.currentChannelFocusNode
                                : null,
                        onTap: () => widget.onSelectChannel(ch),
                        onFavorite: () => widget.onToggleFavorite(ch),
                        onFocused: () =>
                            widget.onItemFocused?.call(globalIndex),
                      );
                    },
                  ),
          ),

          // ── Hint ───────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Text(
              'MENU key to favourite',
              style: TextStyle(
                fontFamily: 'Outfit',
                color: Colors.white24,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.total, this.filtered});
  final int total;
  final int? filtered; // non-null when a filter is active

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.live_tv_rounded,
            color: Colors.white54,
            size: 17,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Channels',
              style: TextStyle(
                fontFamily: 'Outfit',
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Text(
            filtered != null ? '$filtered / $total' : '$total',
            style: const TextStyle(
              fontFamily: 'Outfit',
              color: Colors.white38,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Search field ──────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
          fontFamily: 'Outfit',
          color: Colors.white,
          fontSize: 14,
        ),
        cursorColor: AppColors.accentBright,
        decoration: InputDecoration(
          hintText: 'Search channels…',
          hintStyle: const TextStyle(
            fontFamily: 'Outfit',
            color: Colors.white30,
            fontSize: 14,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Colors.white38,
            size: 18,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? GestureDetector(
                  onTap: onClear,
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white38,
                    size: 16,
                  ),
                )
              : null,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: AppColors.accentBright,
              width: 1.5,
            ),
          ),
        ),

      ),
    );
  }
}

// ── Group tabs ────────────────────────────────────────────────────────────────

class _GroupTabs extends StatelessWidget {
  const _GroupTabs({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<String> groups;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _GroupChip(
            label: 'All',
            selected: selected == null,
            // Passing empty string signals "clear filter" to the parent toggle.
            onTap: selected != null ? () => onSelect(selected!) : null,
          ),
          ...groups.map(
            (g) => _GroupChip(
              label: g,
              selected: selected == g,
              onTap: () => onSelect(g),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap: onTap ?? () {},
      builder: (_, focused) {
        final active = selected || focused;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentBright.withValues(alpha: 0.20)
                : focused
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? AppColors.accentBright.withValues(alpha: 0.70)
                  : focused
                  ? Colors.white38
                  : Colors.white12,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Outfit',
                color: active ? Colors.white : Colors.white54,
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isFiltering});
  final bool isFiltering;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFiltering
                ? Icons.search_off_rounded
                : Icons.hourglass_empty_rounded,
            color: Colors.white24,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            isFiltering ? 'No matches' : 'Loading…',
            style: const TextStyle(
              fontFamily: 'Outfit',
              color: Colors.white38,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar row ───────────────────────────────────────────────────────────────

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.channel,
    required this.isCurrent,
    required this.onTap,
    required this.onFavorite,
    this.focusNode,
    this.onFocused,
  });

  final Channel channel;
  final bool isCurrent;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback? onFocused;

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) onFocused?.call();
      },
      child: FocusableTap(
        focusNode: focusNode,
        onTap: onTap,
        onMenu: onFavorite,
        builder: (_, focused) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.10)
                  : isCurrent
                  ? AppColors.accentBright.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: focused
                      ? AppColors.accentBright
                      : isCurrent
                      ? AppColors.accentBright.withValues(alpha: 0.55)
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                // Avatar
                ChannelAvatar(
                  logoUrl: channel.logo,
                  name: channel.name,
                  size: 36,
                ),
                const SizedBox(width: 11),

                // Name + group
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Name row: name + playing dot
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                color: Colors.white.withValues(
                                  alpha: isCurrent ? 1.0 : 0.88,
                                ),
                                fontSize: 13.5,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 6),
                            _PlayingDot(),
                          ],
                        ],
                      ),

                      // Group badge
                      if (channel.group != null &&
                          channel.group!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _GroupBadge(label: channel.group!),
                      ],
                    ],
                  ),
                ),

                // Favourite star
                if (channel.isFavorite)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: AppColors.sandMid,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Playing indicator dot ─────────────────────────────────────────────────────

class _PlayingDot extends StatefulWidget {
  // ignore: unused_element
  const _PlayingDot();

  @override
  State<_PlayingDot> createState() => _PlayingDotState();
}

class _PlayingDotState extends State<_PlayingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: AppColors.accentBright,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accentBright.withValues(alpha: 0.6),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Group badge ───────────────────────────────────────────────────────────────

class _GroupBadge extends StatelessWidget {
  const _GroupBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'Outfit',
          color: Colors.white38,
          fontSize: 10.5,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
