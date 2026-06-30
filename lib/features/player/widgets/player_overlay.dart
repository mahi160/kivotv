import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/focusable_tap.dart';
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
    this.providerName,
    this.driftSec = 0,
    this.streamOpenedAt,
    required this.onSync,
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

  final Channel channel;
  final String? providerName;
  final double driftSec;
  final DateTime? streamOpenedAt;
  final VoidCallback onSync;
  final int channelIndex;
  final int channelTotal;
  final Player player;
  final bool showingList;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onInteraction;
  final VoidCallback onBack;
  final VoidCallback onToggleList;
  final VoidCallback onToggleFavorite;
  final FocusNode playFocusNode;

  @override
  Widget build(BuildContext context) {
    final chNum = channelIndex >= 0 && channelTotal > 0
        ? '${channelIndex + 1} / $channelTotal'
        : '';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Colors.transparent, Color(0xAA000000)],
          stops: [0.0, 0.48, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.tvEdge,
          AppSpacing.sm,
          AppSpacing.tvEdge,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar: back | channel info | clock ─────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // FocusableTap instead of IconButton so the back button
                // gets the same gold glow ring as every other focusable
                // in the app rather than Material's grey-highlight box.
                FocusableTap(
                  onTap: () {
                    onInteraction();
                    onBack();
                  },
                  builder: (_, focused) => AnimatedContainer(
                    duration: const Duration(milliseconds: 110),
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: focused
                          ? Colors.white
                          : Colors.black.withValues(alpha: 0.55),
                      border: Border.all(
                        color: focused
                            ? AppColors.accentBright
                            : Colors.white30,
                        width: focused ? 2 : 1,
                      ),
                      boxShadow: null,
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 22,
                      color: focused ? Colors.black87 : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const _LiveBadge(),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              channel.name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (providerName != null) ...
                        [
                          const SizedBox(height: 3),
                          Text(
                            providerName!,
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              color: Colors.white54,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                    ],
                  ),
                ),
                // Category chip on the side.
                if (channel.group != null && channel.group!.isNotEmpty) ...[
                  _CategoryChip(label: channel.group!),
                  const SizedBox(width: AppSpacing.sm),
                ],
                const LiveClock(),
              ],
            ),

            const Spacer(),

            // ── Stream info row (playing time + drift) ─────────────────────────
            _StreamInfoRow(
              streamOpenedAt: streamOpenedAt,
              driftSec: driftSec,
              onSync: onSync,
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Bottom bar ────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel number — left, in a legible pill
                if (chNum.isNotEmpty) _ChannelNumberPill(text: chNum),

                const Spacer(),

                // Playback controls — centre. Play/pause is the big primary.
                CtrlBtn(
                  icon: Icons.skip_previous_rounded,
                  autofocus: false,
                  onPressed: () {
                    onInteraction();
                    onPrevious();
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: false,
                  builder: (ctx, snap) {
                    final playing = snap.data ?? false;
                    return CtrlBtn(
                      icon: playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      autofocus: true,
                      primary: true,
                      focusNode: playFocusNode,
                      onPressed: () {
                        onInteraction();
                        player.playOrPause();
                      },
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                CtrlBtn(
                  icon: Icons.skip_next_rounded,
                  autofocus: false,
                  onPressed: () {
                    onInteraction();
                    onNext();
                  },
                ),

                const Spacer(),

                // Icon actions — right
                IconAction(
                  icon: Icons.format_list_bulleted_rounded,
                  active: showingList,
                  tooltip: 'Channel list',
                  onPressed: () {
                    onInteraction();
                    onToggleList();
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                IconAction(
                  icon: channel.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  active: channel.isFavorite,
                  tooltip: channel.isFavorite
                      ? 'Remove from favourites'
                      : 'Add to favourites',
                  onPressed: () {
                    onInteraction();
                    onToggleFavorite();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Category chip ──────────────────────────────────────────────────

/// The current channel's category, shown beside the clock while watching.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Outfit',
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ── LIVE badge ─────────────────────────────────────────────────

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
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(width: 7),
          Text(
            'LIVE',
            style: TextStyle(
              fontFamily: 'Outfit',
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Outfit',
          color: Colors.white70,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Stream info row ──────────────────────────────────────────────────────────

/// Shows "Playing HH:MM" on the left and, when drifted, a focusable
/// "Xs behind live · Sync" button on the right.
class _StreamInfoRow extends StatelessWidget {
  const _StreamInfoRow({
    required this.streamOpenedAt,
    required this.driftSec,
    required this.onSync,
  });

  final DateTime? streamOpenedAt;
  final double driftSec;
  final VoidCallback onSync;

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final opened = streamOpenedAt;
    final playingFor = opened != null
        ? _formatDuration(DateTime.now().difference(opened))
        : null;
    final showDrift = driftSec > 4;

    if (playingFor == null && !showDrift) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (playingFor != null) ...[
            const Icon(Icons.play_circle_outline_rounded,
                size: 14, color: Colors.white38),
            const SizedBox(width: 5),
            Text(
              playingFor,
              style: const TextStyle(
                fontFamily: 'Outfit',
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
          ],
          const Spacer(),
          if (showDrift)
            FocusableTap(
              onTap: onSync,
              builder: (_, focused) => AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: focused
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: focused
                        ? Colors.white54
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.av_timer_rounded,
                        size: 14, color: Colors.white54),
                    const SizedBox(width: 6),
                    Text(
                      '${math.max(0, driftSec).round()}s behind live',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Sync',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        color: Color(0xFFE8B84B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
