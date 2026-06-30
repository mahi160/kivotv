import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/channel_card.dart';
import '../../../core/widgets/focusable_tap.dart';
import '../../../models/channel.dart';

/// Slide-in sidebar showing the current channel list.
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
  final ValueChanged<int>? onItemFocused;
  final FocusNode? currentChannelFocusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.tvSidebarWidth,
      decoration: const BoxDecoration(
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
          Container(
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
                  '${channels.length}',
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    color: Colors.white38,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: channels.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_empty_rounded,
                          color: Colors.white24,
                          size: 32,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Loading…',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: channels.length,
                    itemExtent: AppSpacing.tvSidebarTile,
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
        builder: (_, focused) => AnimatedContainer(
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
              ChannelAvatar(
                logoUrl: channel.logo,
                name: channel.name,
                size: 36,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                          const _PlayingDot(),
                        ],
                      ],
                    ),
                    if (channel.group != null && channel.group!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _GroupBadge(label: channel.group!),
                    ],
                  ],
                ),
              ),
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
        ),
      ),
    );
  }
}

// ── Playing dot ───────────────────────────────────────────────────────────────

class _PlayingDot extends StatefulWidget {
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
        ),
      ),
    );
  }
}
