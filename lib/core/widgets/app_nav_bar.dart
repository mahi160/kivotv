import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'focusable_tap.dart';
import 'kivo_logo.dart';

enum NavDestination { home, channels, settings }

/// Persistent top bar used on every main screen.
///
/// Left  — Kivo logo mark + wordmark (always).
/// Right — Home / Channels / Settings icon buttons.
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
        // ── Spacer pushes icons to the right ───────────────────────────────
        const Spacer(),
        // ── Nav icons ──────────────────────────────────────────────────────
        _NavIcon(
          icon: Icons.home_rounded,
          label: 'Home',
          isActive: active == NavDestination.home,
          onTap: () { if (active != NavDestination.home) context.go('/'); },
        ),
        const SizedBox(width: AppSpacing.xs),
        _NavIcon(
          icon: Icons.live_tv_rounded,
          label: 'Channels',
          isActive: active == NavDestination.channels,
          onTap: () {
            if (active != NavDestination.channels) context.go('/channels');
          },
        ),
        const SizedBox(width: AppSpacing.xs),
        _NavIcon(
          icon: Icons.settings_rounded,
          label: 'Settings',
          isActive: active == NavDestination.settings,
          onTap: () {
            if (active != NavDestination.settings) context.go('/settings');
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

// ── Single nav icon ───────────────────────────────────────────────────────────

class _NavIcon extends StatelessWidget {
  const _NavIcon({
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
    final onSurface = isDark
        ? AppColors.darkOnSurface
        : AppColors.lightOnSurface;
    final onSurfaceVariant = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;

    final iconColor = isActive
        ? AppColors.oceanDeepBlue  // semantic: current destination
        : onSurfaceVariant;

    final activeBg = isDark
        ? AppColors.sandMid.withValues(alpha: 0.12)
        : AppColors.oceanDeepBlue.withValues(alpha: 0.08);

    return Semantics(
      label:    label,
      button:   true,
      selected: isActive,
      child: FocusableTap(
        autofocus: isActive,
        onTap:     onTap,
        builder: (_, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical:   AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: focused
                ? AppColors.focusFill(isDark)
                : isActive ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: focused ? AppColors.focus(isDark) : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            size:  AppSpacing.iconLg,
            color: focused ? onSurface : iconColor,
          ),
        ),
      ),
    );
  }
}
