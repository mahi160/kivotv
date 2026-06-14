import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/focusable_tap.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/channel_logo.dart';
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
  });

  final List<Channel>         channels;
  final Channel               currentChannel;
  final ScrollController      scrollController;
  final ValueChanged<Channel> onSelectChannel;
  final ValueChanged<Channel> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.tvSidebarWidth,
      decoration: const BoxDecoration(
        color: Color(0xEE070B16), // near-black, slightly transparent
        border: Border(
          left: BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.darkBorder),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.format_list_bulleted_rounded,
                    color: AppColors.sandMid, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Channels',
                    style: TextStyle(
                      fontFamily:  'Inter',
                      color:       Colors.white,
                      fontSize:    18,
                      fontWeight:  FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${channels.length}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color:      Colors.white54,
                    fontSize:   14,
                  ),
                ),
              ],
            ),
          ),

          // ── List ─────────────────────────────────────────────────────────
          Expanded(
            child: channels.isEmpty
                ? const Center(
                    child: Text('Loading…',
                        style: TextStyle(
                          fontFamily: 'Inter', color: Colors.white54)),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount:  channels.length,
                    // Fixed extent enables O(1) scroll-to-current.
                    itemExtent: AppSpacing.tvSidebarTile,
                    itemBuilder: (ctx, index) {
                      final ch        = channels[index];
                      final isCurrent = ch.url == currentChannel.url;
                      return _SidebarItem(
                        channel:     ch,
                        isCurrent:   isCurrent,
                        onTap:       () => onSelectChannel(ch),
                        onLongPress: () => onToggleFavorite(ch),
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
                fontFamily: 'Inter', color: Colors.white30, fontSize: 12),
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
    required this.onLongPress,
  });

  final Channel      channel;
  final bool         isCurrent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap:       onTap,
      onLongPress:  onLongPress,
      // TV remotes can't long-press — MENU key triggers the same action.
      onMenu:       onLongPress,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        // Focused → gold tint; current-but-not-focused → ocean tint.
        color: focused
            ? AppColors.focus(true).withValues(alpha: 0.22)
            : isCurrent
                ? AppColors.oceanMid.withValues(alpha: 0.6)
                : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ChannelLogo(
              logoUrl:      channel.logo,
              size:         42,
              borderRadius: 8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment:  MainAxisAlignment.center,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily:  'Inter',
                      color:       isCurrent ? AppColors.sandMid : Colors.white,
                      fontSize:    15,
                      fontWeight:  FontWeight.w600,
                    ),
                  ),
                  if (channel.group != null && channel.group!.isNotEmpty)
                    Text(
                      channel.group!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color:   Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (channel.isFavorite)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.star_rounded,
                    size: 16, color: AppColors.sandMid),
              ),
          ],
        ),
      ),
    );
  }
}
