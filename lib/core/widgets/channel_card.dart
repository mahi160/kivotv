import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'channel_logo.dart';
import 'focusable_tap.dart';
import '../../models/channel.dart';

// ── Public card ───────────────────────────────────────────────────────────────

/// Focusable channel card used in both the grid and home dashboard rows.
///
/// On focus it scales up (1.08 — within the surrounding gap so it never
/// overlaps a neighbour) and lifts on an accent glow.
///
/// Parent scroll views should CLIP (default) so scrolled cards slide under
/// surrounding chrome instead of bleeding over it, and add a little internal
/// padding (e.g. top [AppSpacing.md]) so the edge row's focus glow has room.
/// A purely horizontal row may use [Clip.none] when its outer scrollable clips.
class ChannelCard extends StatelessWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.onFavoriteLongPress,
    this.autofocus = false,
  });

  final Channel      channel;
  final VoidCallback  onTap;
  final VoidCallback? onFavoriteLongPress;
  /// Grabs D-pad focus on first build (used for the first Home card so the
  /// remote always starts on something the user can press OK on).
  final bool         autofocus;

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.oceanDeep : AppColors.lightSurface;
    final accent       = AppColors.focus(isDark);

    return FocusableTap(
      autofocus:   autofocus,
      onTap:       onTap,
      onLongPress: onFavoriteLongPress,
      // TV remotes can't long-press — wire MENU key to the same action.
      onMenu:      onFavoriteLongPress,
      builder: (context, focused) {
        // Focus = motion + accent glow, not heavy chrome. The card lifts and
        // grows on an accent halo so it is unmistakable, from across the room,
        // which tile is selected — the single most important cue on a TV.
        return AnimatedScale(
          // 1.08 keeps the grown card inside the grid/row gap so a later-painted
          // neighbour never clips the focused card's ring or glow.
          scale:    focused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 170),
          curve:    Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve:    Curves.easeOut,
            decoration: BoxDecoration(
              // Surface lifts a touch on focus so the tile reads as raised.
              color: focused
                  ? (isDark ? AppColors.oceanMid : AppColors.lightSurface)
                  : surfaceColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(
                color: focused
                    ? accent
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                width:       focused ? 3 : 1,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color:        accent.withValues(alpha: 0.55),
                        blurRadius:   40,
                        spreadRadius: 2,
                      ),
                      const BoxShadow(
                        color:      Color(0x80000000),
                        blurRadius: 24,
                        offset:     Offset(0, 14),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChannelAvatar(
                          logoUrl: channel.logo,
                          name:    channel.name,
                          size:    72,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          channel.name,
                          maxLines:  2,
                          overflow:  TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            height:        1.2,
                            fontWeight:    FontWeight.w700,
                            color: focused
                                ? (isDark
                                    ? AppColors.darkOnSurface
                                    : AppColors.lightOnSurface)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Favourite — accent star on a dark disc so it reads on any
                  // logo and stays distinct from the focus affordance.
                  if (channel.isFavorite)
                    Positioned(
                      top: 10, right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Color(0xB3000000),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.star_rounded,
                            size: 18, color: AppColors.favActive),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Avatar (logo or letter fallback) ─────────────────────────────────────────

/// Shows the channel logo from the network; falls back to the first letter
/// in a deterministic colour derived from the channel name.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({
    super.key,
    required this.logoUrl,
    required this.name,
    required this.size,
  });

  final String? logoUrl;
  final String  name;
  final double  size;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return ChannelLogo(
        logoUrl:      url,
        size:         size,
        borderRadius: size * 0.18,
      );
    }

    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width:  size,
      height: size,
      decoration: BoxDecoration(
        color:        _letterBg(name),
        borderRadius: BorderRadius.circular(size * 0.18),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize:   size * 0.46,
          fontWeight: FontWeight.w800,
          color:      Colors.white,
          height:     1,
        ),
      ),
    );
  }

  static Color _letterBg(String name) {
    const swatches = [
      Color(0xFF3D6680), // muted ocean
      Color(0xFF4A7A5C), // muted green
      Color(0xFF6B5080), // muted violet
      Color(0xFF7A6040), // muted amber
      Color(0xFF3D6870), // muted teal
      Color(0xFF7A4040), // muted crimson
      Color(0xFF405060), // slate
      Color(0xFF506070), // cool grey
    ];
    if (name.isEmpty) return swatches[0];
    final hash = name.codeUnits.fold(0, (a, b) => a ^ b);
    return swatches[math.max(0, hash.abs() % swatches.length)];
  }
}
