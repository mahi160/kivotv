import 'package:flutter/material.dart';

/// Centralised colour tokens for Kivo.
///
/// Primary palette: Deep Oceanic Blue
/// Accent palette:  Desert-Beach-Sandy
///
/// To update the brand, change values here only — nowhere else.
abstract final class AppColors {
  // ── Primary – Deep Oceanic Blue ──────────────────────────────────────────
  /// Darkest background, used for Scaffold / body.
  static const oceanAbyss = Color(0xFF070B16);

  /// Dark surface: card backgrounds, list tiles.
  static const oceanDeep = Color(0xFF0D1F3C);

  /// Mid surface: elevated cards, dialogs.
  static const oceanMid = Color(0xFF1A3A6B);

  /// Primary interactive: buttons, links.
  static const oceanPrimary = Color(0xFF2D6AB4);

  /// Bright highlight: focus rings, active icons, selected states.
  static const oceanBright = Color(0xFF5B9BD5);

  /// Subtle tint for gradient overlays (same as oceanMid at ~15% opacity).
  static const oceanOverlay = Color(0x261A3A6B);

  // ── Accent – Desert-Beach-Sandy ──────────────────────────────────────────
  /// Deep sand: accent text on dark surfaces, dark-mode tertiary.
  static const sandDark = Color(0xFF8B6914);

  /// Warm amber: active icons, favourite stars, accent buttons.
  static const sandMid = Color(0xFFD4A84B);

  /// Sandy highlight: focus glow on dark surfaces, chips.
  static const sandLight = Color(0xFFF2D07A);

  /// Pale sand: light-mode accent backgrounds, tinted surfaces.
  static const sandPale = Color(0xFFFAE8C4);

  // ── Light-mode neutrals ──────────────────────────────────────────────────
  static const lightBackground = Color(0xFFF0F4F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVariant = Color(0xFFE2EAF4);
  static const lightBorder = Color(0x1A0D1F3C); // oceanDeep 10%
  static const lightOnSurface = Color(0xFF0D1F3C);
  static const lightOnSurfaceVariant = Color(0xFF3A5070);

  // ── Dark-mode neutrals ───────────────────────────────────────────────────
  static const darkBackground = oceanAbyss;
  static const darkSurface = oceanDeep;
  static const darkSurfaceVariant = Color(0xFF162840);
  static const darkBorder = Color(0x28FFFFFF); // white 16%
  static const darkBorderFocused = Color(0xFFBFD7FF);
  static const darkOnSurface = Color(0xFFEDF3FF);
  static const darkOnSurfaceVariant = Color(0xFFB0C8E8);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const error = Color(0xFFEF4444);
  static const errorContainer = Color(0x1FEF4444); // error 12%
  static const success = Color(0xFF22C55E);
  static const successContainer = Color(0x1F22C55E);
  static const warning = Color(0xFFF59E0B);
  static const warningContainer = Color(0x1FF59E0B);

  // ── Gradients ────────────────────────────────────────────────────────────
  /// Home screen radial gradient (dark).
  static const homeGradientDark = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.25,
    colors: [oceanMid, oceanAbyss, Color(0xFF02040A)],
    stops: [0, 0.52, 1],
  );

  /// Channel list / settings linear gradient (dark).
  static const listGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [oceanDeep, Color(0xFF060914)],
  );

  /// Settings panel gradient (dark).
  static const settingsGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF17223D), Color(0xFF060914)],
  );

  /// Home screen light gradient.
  static const homeGradientLight = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.25,
    colors: [lightSurfaceVariant, lightBackground, Color(0xFFD8E6F5)],
    stops: [0, 0.52, 1],
  );

  /// Channel list / settings light gradient.
  static const listGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [lightSurface, lightBackground],
  );
}
