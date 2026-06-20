import 'package:flutter/material.dart';

/// Centralised colour tokens for Kivo.
///
/// Dark-cinematic theme: near-black canvas, a single vivid blue accent, and
/// hairline chrome. Focus is communicated by motion (scale) + an accent glow,
/// not by heavy borders. To re-skin the app, change values here only — every
/// screen reads these tokens, so nothing else needs editing.
abstract final class AppColors {
  // ── The one accent ────────────────────────────────────────────────────────
  /// Vivid electric blue — the single accent used for focus, active state,
  /// favourites and progress. Bright enough to pop on near-black.
  static const accent       = Color(0xFF4D8DFF);
  static const accentBright = Color(0xFF6FA4FF); // hover / focus glow
  static const accentDeep   = Color(0xFF2F6BE0); // pressed
  static const accentTint   = Color(0xFFA8C6FF); // light text on accent fills

  // ── Legacy brand names → mapped onto the accent/neutrals so existing
  //    widgets keep compiling while picking up the new look. ─────────────────
  static const oceanDeepBlue    = accent;
  static const warmSandyBeige   = accentBright;
  static const goldenDriftwood  = accent;        // favourite star = accent
  static const softSeashellPink = accentTint;
  static const ivoryBreeze      = Color(0xFFF3F5F9);

  // ── Neutral scale (dark) ───────────────────────────────────────────────────
  /// True near-black canvas.
  static const oceanAbyss   = Color(0xFF0A0B0F);
  /// Card / surface.
  static const oceanDeep    = Color(0xFF14161C);
  /// Elevated surface / sidebar.
  static const oceanMid     = Color(0xFF1E212B);
  static const oceanPrimary = accent;
  static const oceanBright  = accentBright;
  static const oceanOverlay = Color(0x264D8DFF);

  // ── Accent aliases (sandy scale → accent scale) ────────────────────────────
  static const sandDark  = accentDeep;
  static const sandMid   = accentBright;
  static const sandLight = accent;
  static const sandPale  = accentTint;

  // ── Dark-mode neutrals ──────────────────────────────────────────────────────
  static const darkBackground       = oceanAbyss;
  static const darkSurface          = oceanDeep;
  static const darkSurfaceVariant   = oceanMid;
  /// Hairline border — barely-there white, minimal chrome.
  static const darkBorder           = Color(0x12FFFFFF);
  static const darkBorderFocused    = accent;
  static const darkOnSurface        = Color(0xFFF3F5F9);
  static const darkOnSurfaceVariant = Color(0xFF9BA4B4);

  // ── Light-mode neutrals (kept coherent with the accent) ─────────────────────
  static const lightBackground       = Color(0xFFF4F6FA);
  static const lightSurface          = Color(0xFFFFFFFF);
  static const lightSurfaceVariant   = Color(0xFFE9EEF6);
  static const lightBorder           = Color(0x14000000);
  static const lightOnSurface        = Color(0xFF10131A);
  static const lightOnSurfaceVariant = Color(0xFF5B6472);

  // ── Semantic ────────────────────────────────────────────────────────────────
  static const error            = Color(0xFFFF5A5F);
  static const errorContainer   = Color(0x1FFF5A5F);
  static const success          = Color(0xFF34D399);
  static const successContainer = Color(0x1F34D399);
  static const warning          = Color(0xFFF5B14B);
  static const warningContainer = Color(0x1FF5B14B);

  // ── UI component colours ─────────────────────────────────────────────────────
  static const logoGradientStart = accent;
  static const logoGradientEnd   = accentBright;
  static const focusCardStart    = accent;
  static const focusCardEnd      = accentDeep;
  static const favActive         = accent;
  static const pinActive         = accentBright;

  // ── Unified D-pad focus affordance ───────────────────────────────────────────
  // SINGLE source of truth for the focus highlight. Every focusable widget uses
  // this so "what is selected" always reads the same way.
  static Color focus(bool isDark) => isDark ? accentBright : accent;

  /// Translucent accent fill for widgets that tint a background on focus.
  static Color focusFill(bool isDark) => accent.withValues(alpha: 0.16);

  // ── Gradients — subtle cinematic vignettes, near flat ────────────────────────
  static const homeGradientDark = RadialGradient(
    center: Alignment(-0.5, -0.8),
    radius: 1.4,
    colors: [Color(0xFF181B23), Color(0xFF0C0D12), oceanAbyss],
    stops:  [0.0, 0.55, 1.0],
  );

  static const listGradientDark = LinearGradient(
    begin:  Alignment.topCenter,
    end:    Alignment.bottomCenter,
    colors: [Color(0xFF101218), oceanAbyss],
  );

  static const settingsGradientDark = LinearGradient(
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
    colors: [oceanMid, oceanAbyss],
  );

  static const homeGradientLight = RadialGradient(
    center: Alignment(-0.5, -0.8),
    radius: 1.4,
    colors: [lightSurface, lightBackground, lightSurfaceVariant],
    stops:  [0.0, 0.6, 1.0],
  );

  static const listGradientLight = LinearGradient(
    begin:  Alignment.topCenter,
    end:    Alignment.bottomCenter,
    colors: [lightSurface, lightBackground],
  );
}
