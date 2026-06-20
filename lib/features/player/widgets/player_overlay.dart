import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/channel.dart';
import 'ctrl_btn.dart';
import 'icon_action.dart';
import 'live_clock.dart';

/// Gradient overlay drawn on top of the video surface.
/// Contains: back button, channel name/group, live clock (top bar)
/// and prev/play-pause/next controls + list/favourite buttons (bottom bar).
class PlayerOverlay extends StatelessWidget {
  const PlayerOverlay({
    super.key,
    required this.channel,
    required this.channelIndex,
    required this.channelTotal,
    required this.player,
    required this.showingList,
    required this.onPrevious,
    required this.onNext,
    required this.onInteraction,
    required this.onBack,
    required this.onToggleList,
    required this.onToggleFavorite,
    required this.playFocusNode,
  });

  final Channel      channel;
  final int          channelIndex;
  final int          channelTotal;
  final Player       player;
  final bool         showingList;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onInteraction;
  final VoidCallback onBack;
  final VoidCallback onToggleList;
  final VoidCallback onToggleFavorite;
  final FocusNode    playFocusNode;

  @override
  Widget build(BuildContext context) {
    final chNum = channelIndex >= 0 && channelTotal > 0
        ? '${channelIndex + 1} / $channelTotal'
        : '';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin:  Alignment.topCenter,
          end:    Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent, Color(0xCC000000)],
          stops:  [0.0, 0.42, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.tvEdge, AppSpacing.md,
          AppSpacing.tvEdge, AppSpacing.tvEdge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar: back | channel info | clock ─────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 32),
                  onPressed: () { onInteraction(); onBack(); },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _LiveBadge(),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              channel.name,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                color: Colors.white,
                                shadows: [const Shadow(blurRadius: 8)],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (channel.group != null && channel.group!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            channel.group!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.white60),
                          ),
                        ),
                    ],
                  ),
                ),
                const LiveClock(),
              ],
            ),

            const Spacer(),

            // ── Bottom bar ────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel number — left, in a legible pill
                if (chNum.isNotEmpty)
                  _ChannelNumberPill(text: chNum),

                const Spacer(),

                // Playback controls — centre. Play/pause is the big primary.
                CtrlBtn(
                  icon:      Icons.skip_previous_rounded,
                  autofocus: false,
                  onPressed: () { onInteraction(); onPrevious(); },
                ),
                const SizedBox(width: AppSpacing.md),
                StreamBuilder<bool>(
                  stream:      player.stream.playing,
                  initialData: false,
                  builder: (ctx, snap) {
                    final playing = snap.data ?? false;
                    return CtrlBtn(
                      icon: playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      autofocus: true,
                      primary:   true,
                      focusNode: playFocusNode,
                      onPressed: () { onInteraction(); player.playOrPause(); },
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.md),
                CtrlBtn(
                  icon:      Icons.skip_next_rounded,
                  autofocus: false,
                  onPressed: () { onInteraction(); onNext(); },
                ),

                const Spacer(),

                // Icon actions — right
                IconAction(
                  icon:      Icons.format_list_bulleted_rounded,
                  active:    showingList,
                  tooltip:   'Channel list',
                  onPressed: () { onInteraction(); onToggleList(); },
                ),
                const SizedBox(width: AppSpacing.sm),
                IconAction(
                  icon: channel.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  active:    channel.isFavorite,
                  tooltip:   channel.isFavorite
                      ? 'Remove from favourites'
                      : 'Add to favourites',
                  onPressed: () { onInteraction(); onToggleFavorite(); },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── LIVE badge ──────────────────────────────────────────────────────────────

/// Small "LIVE" chip shown beside the channel name — a universally understood
/// cue that this is a live broadcast, not a recording.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 8, height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            ),
          ),
          SizedBox(width: 7),
          Text(
            'LIVE',
            style: TextStyle(
              fontFamily:    'Inter',
              color:         Colors.white,
              fontSize:      13,
              fontWeight:    FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Channel-number pill ───────────────────────────────────────────────────────

/// "12 / 155" position indicator in a soft pill so it stays legible over any
/// video frame.
class _ChannelNumberPill extends StatelessWidget {
  const _ChannelNumberPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily:    'Inter',
          color:         Colors.white,
          fontSize:      18,
          fontWeight:    FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
