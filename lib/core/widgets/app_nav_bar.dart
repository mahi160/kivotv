import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'focusable_tap.dart';
import 'kivo_logo.dart';

enum NavDestination { home, channels }

/// Persistent top bar used on every main screen.
///
/// Left  — Kivo logo mark + wordmark (always).
/// Right — Home / Channels icon buttons.
///
/// [active] highlights the current destination icon.
class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.active});

  final NavDestination active;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Branding ───────────────────────────────────────────────────────
        const _LogoMark(),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Kivo',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        // ── Spacer pushes the nav pills to the right ───────────────────────
        const Spacer(),
        // ── Nav pills ──────────────────────────────────────────────────────
        _NavPill(
          icon: Icons.home_rounded,
          label: 'Home',
          isActive: active == NavDestination.home,
          onTap: () { if (active != NavDestination.home) context.go('/'); },
        ),
        const SizedBox(width: AppSpacing.sm),
        _NavPill(
          icon: Icons.live_tv_rounded,
          label: 'Channels',
          isActive: active == NavDestination.channels,
          onTap: () {
            if (active != NavDestination.channels) context.go('/channels');
          },
        ),
      ],
    );
  }
}

// ── Logo mark ─────────────────────────────────────────────────────────────────

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    const size = 46.0;
    return Container(
      width:  size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.oceanMid, AppColors.oceanDeepBlue],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.oceanDeepBlue.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: const KivoLogo(),
    );
  }
}

// ── Single nav pill (icon + label) ──────────────────────────────────────────────

/// A labelled pill so the destination is unmistakable — icons alone are easy
/// to misread. The current destination is filled with an accent tint; the
/// focused pill gets a bold accent ring + glow so D-pad position is obvious.
/// Only the label of the active/focused pill is shown, keeping the bar minimal.
class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String   label;
  final bool     isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurfaceVariant = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;
    final accent = AppColors.focus(isDark);

    return Semantics(
      label:    label,
      button:   true,
      selected: isActive,
      child: FocusableTap(
        onTap: onTap,
        builder: (_, focused) {
          final highlighted = focused || isActive;
          // The label shows only when this pill is active or focused, so the
          // bar stays clean but the meaning is always legible where it counts.
          final showLabel = highlighted;
          final fg = focused
              ? (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface)
              : isActive ? accent : onSurfaceVariant;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve:    Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical:   AppSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: focused
                  ? AppColors.focusFill(isDark)
                  : isActive
                      ? accent.withValues(alpha: 0.12)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              border: Border.all(
                color: focused ? accent : Colors.transparent,
                width: 2,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color:      accent.withValues(alpha: 0.45),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: AppSpacing.iconMd, color: fg),
                AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  curve:    Curves.easeOut,
                  child: showLabel
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8, right: 2),
                          child: Text(
                            label,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: fg, fontWeight: FontWeight.w700),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
