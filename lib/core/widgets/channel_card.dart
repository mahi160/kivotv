import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'channel_logo.dart';
import 'focusable_tap.dart';
import '../../models/channel.dart';
import '../../providers/dashboard_provider.dart';

// ── Public card ───────────────────────────────────────────────────────────────

/// Focusable channel card used in both the grid and home dashboard rows.
///
/// Layout follows the Kivo redesign: a tinted logo band on top (real logo when
/// available, otherwise a coloured abbreviation tile) and a footer carrying the
/// channel name and its group. On focus it lifts + scales on an accent glow —
/// the strongest possible "this is selected" cue from across the room.
class ChannelCard extends ConsumerWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.autofocus = false,
  });

  final Channel channel;
  final VoidCallback onTap;

  /// Grabs D-pad focus on first build (used for the first Home card so the
  /// remote always starts on something the user can press OK on).
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Resolve the playlist name once per card build. playlistsProvider is
    // async but almost always already loaded before cards render.
    final source = ref
        .watch(playlistsProvider)
        .asData?.value
        .where((p) => p.id == channel.playlistId)
        .map((p) => p.name)
        .firstOrNull;
    final surfaceColor = isDark ? AppColors.oceanDeep : AppColors.lightSurface;
    final accent = AppColors.focus(isDark);
    final swatch = _swatch(channel.name);
    final text1 = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final text2 = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;
    final hairline = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final group = channel.group;

    return FocusableTap(
      autofocus: autofocus,
      onTap: onTap,
      builder: (context, focused) {
        // Single AnimatedContainer handles both scale + decoration so Flutter
        // only schedules one animation ticker and one repaint per focus change.
        return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            transform: Matrix4.diagonal3Values(
              focused ? 1.03 : 1.0,
              focused ? 1.03 : 1.0,
              1.0,
            ),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: focused ? accent : hairline,
                width: focused ? 2 : 1,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
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
                          color: swatch.withValues(alpha: isDark ? 0.10 : 0.08),
                          child: Center(
                            child: _CardLogo(
                              logoUrl: channel.logo,
                              name: channel.name,
                              swatch: swatch,
                            ),
                          ),
                        ),
                        if (channel.isFavorite)
                          Positioned(
                            top: 8,
                            right: 9,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0x99000000),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: AppColors.primary(isDark),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Footer: name + group ───────────────────────────────────
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: hairline)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              // Slightly brighter on focus in dark mode so the
                              // selected channel name pops against the navy lift.
                              color: (focused && isDark) ? Colors.white : text1,
                              height: 1.2,
                            ),
                          ),
                          if (group != null && group.isNotEmpty || source != null) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                if (group != null && group.isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      group,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme
                                          .bodySmall?.copyWith(color: text2),
                                    ),
                                  )
                                else
                                  const Spacer(),
                                if (source != null) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    source,
                                    maxLines: 1,
                                    style: Theme.of(context).textTheme
                                        .bodySmall?.copyWith(
                                          color: text2.withValues(alpha: 0.5),
                                          fontSize: 10,
                                        ),
                                  ),
                                ],
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
        );
      },
    );
  }

  /// Deterministic accent swatch for a channel — stable per name across
  /// sessions so the same channel always gets the same colour.
  static Color _swatch(String name) {
    const swatches = [
      Color(0xFF8B1A9A),
      Color(0xFFB03A2E),
      Color(0xFF2E4057),
      Color(0xFF6C3483),
      Color(0xFF0B5345),
      Color(0xFF1A5276),
      Color(0xFF922B21),
      Color(0xFF17408B),
      Color(0xFFA04000),
      Color(0xFF1B5E20),
      Color(0xFF5D2E8C),
      Color(0xFF004C97),
    ];
    if (name.isEmpty) return swatches[0];
    final hash = name.codeUnits.fold(0, (a, b) => a + b);
    return swatches[hash.abs() % swatches.length];
  }
}

// ── Logo (network image or coloured abbreviation tile) ──────────────────────────

class _CardLogo extends StatelessWidget {
  const _CardLogo({
    required this.logoUrl,
    required this.name,
    required this.swatch,
  });

  final String? logoUrl;
  final String name;
  final Color swatch;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return ChannelLogo(logoUrl: url, size: 48, borderRadius: 9);
    }

    // Single letter fallback — matches the sidebar’s ChannelAvatar style so
    // every surface in the app uses the same visual language.
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: swatch,
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          fontFamily: 'Outfit',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
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
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return ChannelLogo(logoUrl: url, size: size, borderRadius: size * 0.18);
    }

    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _letterBg(name),
        borderRadius: BorderRadius.circular(size * 0.18),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.46,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }

  static Color _letterBg(String name) {
    const swatches = [
      Color(0xFF3D6680),
      Color(0xFF4A7A5C),
      Color(0xFF6B5080),
      Color(0xFF7A6040),
      Color(0xFF3D6870),
      Color(0xFF7A4040),
      Color(0xFF405060),
      Color(0xFF506070),
    ];
    if (name.isEmpty) return swatches[0];
    final hash = name.codeUnits.fold(0, (a, b) => a ^ b);
    return swatches[math.max(0, hash.abs() % swatches.length)];
  }
}
