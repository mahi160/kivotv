import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Applies the Kivo brand gradient as the body background.
///
/// Chooses between [AppColors.homeGradientDark] / [AppColors.homeGradientLight]
/// automatically based on the current [Brightness].
///
/// Usage:
/// ```dart
/// Scaffold(
///   body: GradientBackground(
///     variant: GradientVariant.home,
///     child: ...,
///   ),
/// )
/// ```
enum GradientVariant { home, list, settings }

class GradientBackground extends StatelessWidget {
  const GradientBackground({
    super.key,
    required this.child,
    this.variant = GradientVariant.list,
  });

  final Widget child;
  final GradientVariant variant;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = _gradient(isDark);

    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: child,
    );
  }

  Gradient _gradient(bool isDark) {
    switch (variant) {
      case GradientVariant.home:
        return isDark ? AppColors.homeGradientDark : AppColors.homeGradientLight;
      case GradientVariant.list:
        return isDark ? AppColors.listGradientDark : AppColors.listGradientLight;
      case GradientVariant.settings:
        return isDark ? AppColors.settingsGradientDark : AppColors.listGradientLight;
    }
  }
}
