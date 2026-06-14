import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

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
                      color: Colors.white, size: 28),
                  onPressed: () { onInteraction(); onBack(); },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                          color: Colors.white,
                          shadows: [const Shadow(blurRadius: 8)],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (channel.group != null && channel.group!.isNotEmpty)
                        Text(
                          channel.group!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.white60),
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
                // Channel number — left
                if (chNum.isNotEmpty)
                  Text(
                    chNum,
                    style: const TextStyle(
                      fontFamily:  'Inter',
                      color:       Colors.white70,
                      fontSize:    16,
                      fontWeight:  FontWeight.w600,
                      shadows:     [Shadow(blurRadius: 6)],
                    ),
                  ),

                const Spacer(),

                // Playback controls — centre
                CtrlBtn(
                  icon:      Icons.skip_previous_rounded,
                  autofocus: false,
                  onPressed: () { onInteraction(); onPrevious(); },
                ),
                const SizedBox(width: AppSpacing.sm),
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
                      focusNode: playFocusNode,
                      onPressed: () { onInteraction(); player.playOrPause(); },
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
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
                const SizedBox(width: AppSpacing.xs),
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
