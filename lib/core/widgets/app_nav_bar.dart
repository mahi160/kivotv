import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'focusable_tap.dart';
import 'kivo_logo.dart';

/// Persistent top bar. With the Netflix-style single-screen Home there's no
/// destination switching, so the bar is just: settings hamburger + brand.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.onOpenMenu,
    required this.onSearch,
  });

  final VoidCallback onOpenMenu;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: AppSpacing.tvHeaderHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CircleNavButton(
            icon: Icons.menu_rounded,
            tooltip: 'Settings',
            bordered: false,
            onTap: onOpenMenu,
          ),
          const SizedBox(width: AppSpacing.xs),
          const _LogoMark(),
          const SizedBox(width: 10),
          Text(
            'kivo',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.8,
              color: isDark
                  ? AppColors.darkOnSurface
                  : AppColors.lightOnSurface,
            ),
          ),
          const Spacer(),
          _CircleNavButton(
            icon: Icons.search_rounded,
            tooltip: 'Search',
            bordered: true,
            onTap: onSearch,
          ),
        ],
      ),
    );
  }
}

// ── Logo mark ─────────────────────────────────────────────────────────────────

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColors.primary(isDark);
    const size = 34.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(9),
        boxShadow: null,
      ),
      padding: const EdgeInsets.all(6),
      child: const KivoLogo(),
    );
  }
}

// ── Circular nav button (settings hamburger) ────────────────────────────────────

class _CircleNavButton extends StatelessWidget {
  const _CircleNavButton({
    required this.icon,
    required this.tooltip,
    required this.bordered,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool bordered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.focus(isDark);
    final onVariant = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;

    return Semantics(
      label: tooltip,
      button: true,
      child: FocusableTap(
        onTap: onTap,
        builder: (_, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: focused ? AppColors.focusFill(isDark) : Colors.transparent,
            border: Border.all(
              color: focused
                  ? accent
                  : bordered
                  ? (isDark ? AppColors.darkBorder : AppColors.lightBorder)
                  : Colors.transparent,
              width: focused ? 2 : 1,
            ),
            boxShadow: null,
          ),
          child: Icon(
            icon,
            size: AppSpacing.iconSm + 2,
            color: focused ? accent : onVariant,
          ),
        ),
      ),
    );
  }
}
