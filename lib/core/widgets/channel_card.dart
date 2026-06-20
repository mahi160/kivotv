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
/// Focus border uses [BorderSide.strokeAlignOutside] with outer padding so
/// the ring never clips against a parent scroll view.
/// Wrap the parent [ListView] / [GridView] with
/// [clipBehavior: Clip.none] and [padding: EdgeInsets.all(AppSpacing.xs)]
/// to guarantee the shadow and ring paint fully.
class ChannelCard extends StatelessWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.onFavoriteLongPress,
  });

  final Channel      channel;
  final VoidCallback  onTap;
  final VoidCallback? onFavoriteLongPress;

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? AppColors.oceanDeep   // #1A2B38 — above the near-black bg
        : AppColors.lightSurface;

    return FocusableTap(
      onTap:       onTap,
      onLongPress: onFavoriteLongPress,
      // TV remotes can't long-press — wire MENU key to the same action.
      onMenu:      onFavoriteLongPress,
      builder: (context, focused) {
        Widget card = AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve:    Curves.easeOut,
          // 3-px padding keeps the focus ring inside the allocated cell area
          // so it never gets clipped by a scroll view.
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg + 2),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color:      AppColors.focus(isDark).withValues(alpha: 0.28),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
            border: Border.all(
              color: focused
                  ? AppColors.focus(isDark)
                  : (isDark ? AppColors.oceanMid : AppColors.lightBorder),
              width:       focused ? 2 : 1,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve:    Curves.easeOut,
              color:    surfaceColor,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Content ───────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChannelAvatar(
                          logoUrl: channel.logo,
                          name:    channel.name,
                          size:    56,
                        ),
                        const SizedBox(height: 9),
                        Text(
                          channel.name,
                          maxLines:  2,
                          overflow:  TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(height: 1.25),
                        ),
                        if (channel.group?.isNotEmpty == true) ...[
                          const SizedBox(height: 3),
                          Text(
                            channel.group!,
                            maxLines:  1,
                            overflow:  TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Favourite badge ───────────────────────────────────
                  if (channel.isFavorite)
                    const Positioned(
                      top: 8, right: 10,
                      child: Icon(Icons.star_rounded,
                          size: 16, color: AppColors.goldenDriftwood),
                    ),

                ],
              ),
            ),
          ),
        );

        return card;
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
