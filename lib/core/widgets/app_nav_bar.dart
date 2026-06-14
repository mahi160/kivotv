import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
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
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.headlineLarge,
            children: const [
              TextSpan(text: 'Kivo '),
              TextSpan(
                text: 'TV',
                style: TextStyle(
                  color: AppColors.oceanDeepBlue,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark
        ? AppColors.darkOnSurface
        : AppColors.lightOnSurface;
    final onSurfaceVariant = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;

    final iconColor = widget.isActive
        ? AppColors.oceanDeepBlue          // consistent on both themes
        : onSurfaceVariant;                // readable on both bg colours

    final focusBg = AppColors.focusFill(isDark);
    final activeBg = isDark
        ? AppColors.sandMid.withValues(alpha: 0.12)
        : AppColors.oceanDeepBlue.withValues(alpha: 0.08);

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
              color: _focused ? focusBg : widget.isActive ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: _focused
                    ? AppColors.focus(isDark)
                    : Colors.transparent,
              ),
            ),
            child: Icon(
              widget.icon,
              size: AppSpacing.iconLg,
              color: _focused ? onSurface : iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
