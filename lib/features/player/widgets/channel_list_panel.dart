import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/focusable_tap.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/channel_card.dart';
import '../../../models/channel.dart';

/// Slide-in sidebar showing the current channel list.
/// Shown at the right edge of the player when the user opens it.
class ChannelListPanel extends StatelessWidget {
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

  /// Called with the list index whenever a sidebar row gains D-pad focus.
  /// Used by the player to detect boundary conditions for wrap-around.
  final ValueChanged<int>? onItemFocused;

  /// FocusNode for the currently-playing channel’s row, so the player can
  /// call requestFocus() on it when the sidebar opens.
  final FocusNode? currentChannelFocusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.tvSidebarWidth,
      decoration: const BoxDecoration(
        color: Color(0xF0060A14),
        border: Border(left: BorderSide(color: AppColors.darkBorder, width: 1)),
      ),
      child: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.format_list_bulleted_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Channels',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${channels.length}',
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // ── List ─────────────────────────────────────────────────────────
          Expanded(
            child: channels.isEmpty
                ? const Center(
                    child: Text(
                      'Loading…',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        color: Colors.white54,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: channels.length,
                    // Fixed extent enables O(1) scroll-to-current.
                    itemExtent: AppSpacing.tvSidebarTile,
                    // Pre-build ~16 items beyond the viewport so D-pad ↓
                    // focus traversal can reach off-screen rows without
                    // getting stuck at the visible boundary.
                    // ignore: deprecated_member_use
                    cacheExtent: 1200,
                    itemBuilder: (ctx, index) {
                      final ch = channels[index];
                      final isCurrent = ch.url == currentChannel.url;
                      return _SidebarItem(
                        channel: ch,
                        isCurrent: isCurrent,
                        focusNode: isCurrent ? currentChannelFocusNode : null,
                        onTap: () => onSelectChannel(ch),
                        onFavorite: () => onToggleFavorite(ch),
                        onFocused: () => onItemFocused?.call(index),
                      );
                    },
                  ),
          ),

          // ── Hint ─────────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Long press to favourite',
              style: TextStyle(
                fontFamily: 'Outfit',
                color: Colors.white30,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
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

  /// Called when this row gains D-pad focus. Used for wrap-around tracking.
  final VoidCallback? onFocused;

  @override
  Widget build(BuildContext context) {
    return Focus(
      // skipTraversal keeps this node out of the D-pad traversal order while
      // still letting onFocusChange fire when a descendant is focused.
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) onFocused?.call();
      },
      child: FocusableTap(
        focusNode: focusNode,
        onTap: onTap,
        onMenu: onFavorite, // MENU key → toggle favourite on TV remote
        builder: (_, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: focused
                ? Colors.white.withValues(alpha: 0.08)
                : isCurrent
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: focused
                    ? AppColors.accentBright
                    : isCurrent
                    ? AppColors.accent.withValues(alpha: 0.60)
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // ChannelAvatar: shows the logo when available, otherwise the
              // channel’s first letter in a deterministic colour — never a
              // generic TV icon that gives no information.
              ChannelAvatar(
                logoUrl: channel.logo,
                name: channel.name,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        color: Colors.white.withValues(
                          alpha: isCurrent ? 1.0 : 0.85,
                        ),
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (channel.group != null && channel.group!.isNotEmpty)
                      Text(
                        channel.group!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (channel.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: AppColors.sandMid,
                  ),
                ),
            ],
          ),
        ),
      ), // FocusableTap
    ); // Focus
  }
}
