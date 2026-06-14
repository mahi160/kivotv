import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

enum NavDestination { home, channels, settings }

/// Persistent top-left icon navigation bar used on all main screens.
///
/// [active] highlights the current destination.
/// [trailing] is placed at the far right (e.g. a search field).
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.active,
    this.trailing,
  });

  final NavDestination active;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _NavIcon(
          icon: Icons.home_rounded,
          label: 'Home',
          isActive: active == NavDestination.home,
          autofocus: active == NavDestination.home,
          onTap: () {
            if (active != NavDestination.home) context.go('/');
          },
        ),
        const SizedBox(width: AppSpacing.xs),
        _NavIcon(
          icon: Icons.live_tv_rounded,
          label: 'Channels',
          isActive: active == NavDestination.channels,
          autofocus: active == NavDestination.channels,
          onTap: () {
            if (active != NavDestination.channels) context.go('/channels');
          },
        ),
        const SizedBox(width: AppSpacing.xs),
        _NavIcon(
          icon: Icons.settings_rounded,
          label: 'Settings',
          isActive: active == NavDestination.settings,
          autofocus: active == NavDestination.settings,
          onTap: () {
            if (active != NavDestination.settings) context.go('/settings');
          },
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing!,
        ],
      ],
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
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_NavIcon> createState() => _NavIconState();
}

class _NavIconState extends State<_NavIcon> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final activeColor  = AppColors.sandMid;
    final defaultColor = Colors.white.withValues(alpha: 0.65);
    final iconColor    = widget.isActive ? activeColor : defaultColor;

    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.isActive,
      child: Focus(
        autofocus: widget.autofocus,
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
