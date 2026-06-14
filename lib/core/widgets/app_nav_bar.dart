import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

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
    return Container(
      width: AppSpacing.logoSize * 0.7,
      height: AppSpacing.logoSize * 0.7,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.logoRadius * 0.7),
        gradient: const LinearGradient(
          colors: [AppColors.logoGradientStart, AppColors.logoGradientEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.logoGradientStart.withValues(alpha: 0.30),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Icon(
        Icons.live_tv_rounded,
        size: AppSpacing.iconMd,
        color: Colors.white,
      ),
    );
  }
}

// ── Single nav icon ───────────────────────────────────────────────────────────

class _NavIcon extends StatefulWidget {
  const _NavIcon({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavIcon> createState() => _NavIconState();
}

class _NavIconState extends State<_NavIcon> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isActive
        ? AppColors.sandMid
        : Colors.white.withValues(alpha: 0.65);

    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.isActive,
      child: Focus(
        autofocus: widget.isActive,
        onFocusChange: (v) => setState(() => _focused = v),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
               event.logicalKey == LogicalKeyboardKey.enter)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: 0.12)
                  : widget.isActive
                      ? AppColors.sandMid.withValues(alpha: 0.12)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: _focused
                    ? AppColors.sandMid.withValues(alpha: 0.6)
                    : Colors.transparent,
              ),
            ),
            child: Icon(
              widget.icon,
              size: AppSpacing.iconLg,
              color: _focused ? Colors.white : iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
