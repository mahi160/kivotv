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
/// Layout follows the Kivo redesign: a tinted logo band on top (real logo when
/// available, otherwise a coloured abbreviation tile) and a footer carrying the
/// channel name and its group. On focus it lifts + scales on an accent glow —
/// the strongest possible "this is selected" cue from across the room.
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
    final swatch       = _swatch(channel.name);
    final text1        = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final text2        = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;
    final hairline     = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final group        = channel.group;

    return FocusableTap(
      autofocus:   autofocus,
      onTap:       onTap,
      onLongPress: onFavoriteLongPress,
      // TV remotes can't long-press — wire MENU key to the same action.
      onMenu:      onFavoriteLongPress,
      builder: (context, focused) {
        return AnimatedScale(
          // Kept inside the row/grid gap so a later-painted neighbour never
          // clips the focused card's ring or glow.
          scale:    focused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 170),
          curve:    Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve:    Curves.easeOut,
            decoration: BoxDecoration(
              color: focused
                  ? (isDark ? AppColors.oceanMid : AppColors.lightSurface)
                  : surfaceColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color:       focused ? accent : hairline,
                width:       focused ? 2 : 1,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color:        accent.withValues(alpha: 0.45),
                        blurRadius:   34,
                        spreadRadius: 1,
                      ),
                      const BoxShadow(
                        color:      Color(0x73000000),
                        blurRadius: 22,
                        offset:     Offset(0, 12),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Logo band ──────────────────────────────────────────────
                  SizedBox(
                    height: AppSpacing.tvCardLogoBand,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: swatch.withValues(alpha: isDark ? 0.20 : 0.14),
                          child: Center(
                            child: _CardLogo(
                              logoUrl: channel.logo,
                              name:    channel.name,
                              swatch:  swatch,
                            ),
                          ),
                        ),
                        if (channel.isFavorite)
                          Positioned(
                            top: 8, right: 9,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0x99000000),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.star_rounded,
                                  size: 16, color: AppColors.primary(isDark)),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Footer: name + group ───────────────────────────────────
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: hairline)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment:  MainAxisAlignment.center,
                        children: [
                          Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                              fontWeight: FontWeight.w600,
                              // Slightly brighter on focus in dark mode so the
                              // selected channel name pops against the navy lift.
                              color: (focused && isDark) ? Colors.white : text1,
                              height: 1.2,
                            ),
                          ),
                          if (group != null && group.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Container(
                                  width: 6, height: 6,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary(isDark),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    group,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: text2),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
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

  /// Deterministic accent swatch for a channel, used to tint the logo band and
  /// the fallback abbreviation tile. Stable per name so a channel always looks
  /// the same between sessions.
  ///
  /// Static cache avoids recomputing the hash on every card rebuild (dashboard
  /// rebuilds recreate card widgets but the swatch never changes).
  static final _swatchCache = <String, Color>{};

  static Color _swatch(String name) =>
      _swatchCache.putIfAbsent(name, () {
        const swatches = [
          Color(0xFF8B1A9A), Color(0xFFB03A2E), Color(0xFF2E4057),
          Color(0xFF6C3483), Color(0xFF0B5345), Color(0xFF1A5276),
          Color(0xFF922B21), Color(0xFF17408B), Color(0xFFA04000),
          Color(0xFF1B5E20), Color(0xFF5D2E8C), Color(0xFF004C97),
        ];
        if (name.isEmpty) return swatches[0];
        final hash = name.codeUnits.fold(0, (a, b) => a + b);
        return swatches[hash.abs() % swatches.length];
      });
}

// ── Logo (network image or coloured abbreviation tile) ──────────────────────────

class _CardLogo extends StatelessWidget {
  const _CardLogo({
    required this.logoUrl,
    required this.name,
    required this.swatch,
  });

  final String? logoUrl;
  final String  name;
  final Color   swatch;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return ChannelLogo(logoUrl: url, size: 64, borderRadius: 12);
    }

    final abbr = _abbr(name);
    final fontSize = abbr.length > 3 ? 20.0 : abbr.length > 2 ? 24.0 : 30.0;
    return Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        color: swatch,
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Text(
        abbr,
        style: TextStyle(
          fontFamily:    'Outfit',
          fontSize:      fontSize,
          fontWeight:    FontWeight.w700,
          letterSpacing: 0.4,
          color:         Colors.white,
          height:        1,
        ),
      ),
    );
  }

  /// Up to three letters: the initials of the first words, or the first
  /// characters of a single-word name. Cached: channel names are immutable
  /// so the abbreviation never changes across rebuilds.
  static final _abbrCache = <String, String>{};

  static String _abbr(String name) =>
      _abbrCache.putIfAbsent(name, () {
        final words = name
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        if (words.isEmpty) return '?';
        if (words.length == 1) {
          final w = words.first;
          return (w.length <= 3 ? w : w.substring(0, 3)).toUpperCase();
        }
        return words.take(3).map((w) => w[0]).join().toUpperCase();
      });
}

// ── Avatar (logo or letter fallback) ─────────────────────────────────────────

/// Shows the channel logo from the network; falls back to the first letter
/// in a deterministic colour derived from the channel name. Retained for reuse
/// by other surfaces (e.g. lists) that want a compact channel mark.
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
          fontWeight: FontWeight.w700,
          color:      Colors.white,
          height:     1,
        ),
      ),
    );
  }

  static Color _letterBg(String name) {
    const swatches = [
      Color(0xFF3D6680), Color(0xFF4A7A5C), Color(0xFF6B5080),
      Color(0xFF7A6040), Color(0xFF3D6870), Color(0xFF7A4040),
      Color(0xFF405060), Color(0xFF506070),
    ];
    if (name.isEmpty) return swatches[0];
    final hash = name.codeUnits.fold(0, (a, b) => a ^ b);
    return swatches[math.max(0, hash.abs() % swatches.length)];
  }
}
