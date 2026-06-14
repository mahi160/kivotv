import 'package:flutter/material.dart';

/// Centralised colour tokens for Kivo.
///
/// ┌─────────────────────────────────────────────────────┐
/// │  Brand palette (exact values as specified)          │
/// │  Ocean Deep Blue    #5D768B                         │
/// │  Warm Sandy Beige   #C8B39B                         │
/// │  Golden Driftwood   #E3C9A4                         │
/// │  Soft Seashell Pink #F2D9C7                         │
/// │  Ivory Breeze       #F8EFE5                         │
/// └─────────────────────────────────────────────────────┘
///
/// To update the brand: change values here only — nothing else.
abstract final class AppColors {
  // ── Brand swatches (verbatim) ─────────────────────────────────────────────
  static const oceanDeepBlue    = Color(0xFF5D768B);
  static const warmSandyBeige   = Color(0xFFC8B39B);
  static const goldenDriftwood  = Color(0xFFE3C9A4);
  static const softSeashellPink = Color(0xFFF2D9C7);
  static const ivoryBreeze      = Color(0xFFF8EFE5);

  // ── Primary scale — Ocean Deep Blue ──────────────────────────────────────
  /// Near-black background for dark mode.
  static const oceanAbyss    = Color(0xFF0F1A22);
  /// Dark card / surface (dark mode).
  static const oceanDeep     = Color(0xFF1A2B38);
  /// Elevated surface / sidebar (dark mode).
  static const oceanMid      = Color(0xFF253D50);
  /// Primary interactive colour — the brand blue.
  static const oceanPrimary  = oceanDeepBlue;         // #5D768B
  /// Highlight / focus ring in dark mode.
  static const oceanBright   = Color(0xFF8BA4B6);
  /// Subtle tint overlay.
  static const oceanOverlay  = Color(0x265D768B);

  // ── Accent scale — Sandy / Driftwood ─────────────────────────────────────
  /// Deepest sandy tone — hover / pressed state.
  static const sandDark      = Color(0xFFA08870);
  /// Core accent — Warm Sandy Beige.
  static const sandMid       = warmSandyBeige;         // #C8B39B
  /// Golden highlight — Golden Driftwood.
  static const sandLight     = goldenDriftwood;        // #E3C9A4
  /// Pale tint — Soft Seashell Pink.
  static const sandPale      = softSeashellPink;       // #F2D9C7

  // ── Dark-mode neutrals ────────────────────────────────────────────────────
  static const darkBackground      = oceanAbyss;
  static const darkSurface         = oceanDeep;
  static const darkSurfaceVariant  = oceanMid;
  /// 18 % ocean on black — subtle card border in dark.
  static const darkBorder          = Color(0x2E5D768B);
  /// Focused border ring in dark mode — warm golden.
  static const darkBorderFocused   = goldenDriftwood;
  static const darkOnSurface       = ivoryBreeze;
  static const darkOnSurfaceVariant = Color(0xFFD4C0AB);

  // ── Light-mode neutrals ───────────────────────────────────────────────────
  static const lightBackground      = ivoryBreeze;      // #F8EFE5
  static const lightSurface         = Color(0xFFFFFFFF);
  static const lightSurfaceVariant  = softSeashellPink; // #F2D9C7
  /// 18 % ocean on white — subtle card border in light.
  static const lightBorder          = Color(0x2E5D768B);
  static const lightOnSurface       = Color(0xFF1A2830);
  static const lightOnSurfaceVariant = Color(0xFF5C6E7C);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const error            = Color(0xFFAD4040);
  static const errorContainer   = Color(0x1FAD4040);
  static const success          = Color(0xFF4A8C5C);
  static const successContainer = Color(0x1F4A8C5C);
  static const warning          = Color(0xFF997840);
  static const warningContainer = Color(0x1F997840);

  // ── UI component colours ──────────────────────────────────────────────────
  /// Logo mark gradient: ocean → sandy.
  static const logoGradientStart = oceanDeepBlue;     // #5D768B
  static const logoGradientEnd   = warmSandyBeige;    // #C8B39B

  /// Focused card gradient (dark).
  static const focusCardStart    = oceanDeepBlue;
  static const focusCardEnd      = oceanDeep;

  /// Favourite star / active accent.
  static const favActive         = goldenDriftwood;   // #E3C9A4
  /// Pin icon active.
  static const pinActive         = oceanBright;

  // ── Unified D-pad focus affordance ────────────────────────────────────────
  // SINGLE source of truth for the focus highlight colour. Every focusable
  // widget (cards, nav, player controls, sidebar, theme picker) MUST use this
  // so the user always recognises "what is selected" the same way.
  //
  // Ocean blue on light backgrounds  → high contrast on ivory.
  // Golden driftwood on dark backgrounds → high contrast on near-black.
  /// Focus ring / border / icon highlight colour.
  static Color focus(bool isDark) => isDark ? goldenDriftwood : oceanDeepBlue;

  /// Translucent focus fill (used by widgets that tint a background on focus).
  static Color focusFill(bool isDark) =>
      (isDark ? goldenDriftwood : oceanDeepBlue).withValues(alpha: 0.14);

  // ── Gradients ─────────────────────────────────────────────────────────────
  /// Home screen — dark.
  static const homeGradientDark = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.3,
    colors: [oceanMid, oceanDeep, oceanAbyss],
    stops: [0.0, 0.5, 1.0],
  );

  /// Channel list / settings — dark.
  static const listGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [oceanDeep, oceanAbyss],
  );

  /// Settings panel — dark (slight left-right tilt).
  static const settingsGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [oceanMid, oceanAbyss],
  );

  /// Home screen — light.
  static const homeGradientLight = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.3,
    colors: [softSeashellPink, lightBackground, ivoryBreeze],
    stops: [0.0, 0.5, 1.0],
  );

  /// Channel list / settings — light.
  static const listGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [lightSurface, lightBackground],
  );
}
