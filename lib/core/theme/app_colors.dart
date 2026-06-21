import 'package:flutter/material.dart';

/// Centralised colour tokens for Kivo.
///
/// Warm-cinematic theme: a deep navy canvas with a single amber accent in dark
/// mode, and a soft cream canvas with a teal accent in light mode. Focus is
/// communicated by motion (scale) + an accent glow, not by heavy borders.
///
/// The accent is brightness-dependent (amber on dark, teal on light), so prefer
/// the [primary] / [focus] / [focusGlow] helpers over the raw `accent`
/// constant when a widget can render in either mode. The bare [accent]
/// constant is the dark-mode amber, kept for the always-dark player chrome and
/// for legacy references.
abstract final class AppColors {
  // ── The accent (dark = amber, light = teal) ────────────────────────────────
  /// Dark-mode amber accent — the single accent for focus, active state,
  /// favourites and progress on the navy canvas.
  static const accent       = Color(0xFFE5803A);
  static const accentBright = Color(0xFFF2965A); // hover / focus glow
  static const accentDeep   = Color(0xFFC9692A); // pressed
  static const accentTint   = Color(0xFFFFC79E); // light text on accent fills

  /// Light-mode teal accent.
  static const lightAccent      = Color(0xFF1A7FA0);
  static const lightAccentFocus = Color(0xFF2490BF);

  // ── Legacy brand names → mapped onto the accent/neutrals so existing
  //    widgets keep compiling while picking up the new look. ─────────────────
  static const oceanDeepBlue    = accent;
  static const warmSandyBeige   = accentBright;
  static const goldenDriftwood  = accent;        // favourite star = accent
  static const softSeashellPink = accentTint;
  static const ivoryBreeze      = Color(0xFFEDE8DF);

  // ── Neutral scale (dark) ───────────────────────────────────────────────────
  /// Deep navy canvas.
  static const oceanAbyss   = Color(0xFF070D1A);
  /// Card / surface.
  static const oceanDeep    = Color(0xFF0E1929);
  /// Elevated surface / focused-card lift / sidebar.
  static const oceanMid     = Color(0xFF15233A);
  /// Header / top-bar surface.
  static const darkHeader   = Color(0xFF09121F);
  static const oceanPrimary = accent;
  static const oceanBright  = accentBright;
  static const oceanOverlay = Color(0x26E5803A);

  // ── Accent aliases (sandy scale → accent scale) ────────────────────────────
  static const sandDark  = accentDeep;
  static const sandMid   = accentBright;
  static const sandLight = accent;
  static const sandPale  = accentTint;

  // ── Dark-mode neutrals ──────────────────────────────────────────────────────
  static const darkBackground       = oceanAbyss;
  static const darkSurface          = oceanDeep;
  static const darkSurfaceVariant   = oceanMid;
  /// Hairline border — subtle navy line.
  static const darkBorder           = Color(0xFF162033);
  static const darkBorderFocused    = accent;
  static const darkOnSurface        = Color(0xFFEDE8DF);
  static const darkOnSurfaceVariant = Color(0xFF7A8FA0);

  // ── Light-mode neutrals (warm cream, coherent with the teal accent) ─────────
  static const lightBackground       = Color(0xFFF5F0E8);
  static const lightSurface          = Color(0xFFFFFFFF);
  static const lightHeader           = Color(0xFFFFFFFF);
  static const lightSurfaceVariant   = Color(0xFFEDE7DB);
  static const lightBorder           = Color(0xFFDED6C8);
  static const lightOnSurface        = Color(0xFF16273A);
  static const lightOnSurfaceVariant = Color(0xFF6A7D90);

  // ── Semantic ────────────────────────────────────────────────────────────────
  /// Broadcast-red used for LIVE markers and errors.
  static const error            = Color(0xFFE53935);
  static const errorContainer   = Color(0x1FE53935);
  static const success          = Color(0xFF34D399);
  static const successContainer = Color(0x1F34D399);
  static const warning          = Color(0xFFF5B14B);
  static const warningContainer = Color(0x1FF5B14B);

  /// Pulsing LIVE dot / badge colour.
  static const live = Color(0xFFE53935);

  // ── UI component colours ─────────────────────────────────────────────────────
  static const logoGradientStart = accent;
  static const logoGradientEnd   = accentBright;
  static const focusCardStart    = accent;
  static const focusCardEnd      = accentDeep;
  static const favActive         = accent;
  static const pinActive         = accentBright;

  // ── Brightness-aware accent helpers ──────────────────────────────────────────
  // SINGLE source of truth for the accent + focus highlight, so "what is the
  // brand colour" and "what is selected" always read the same way in both modes.

  /// The brand accent for the current brightness (amber on dark, teal on light).
  static Color primary(bool isDark) => isDark ? accent : lightAccent;

  /// Translucent accent fill (the design's `--kv-primary-sub`).
  static Color primarySub(bool isDark) =>
      (isDark ? accent : lightAccent).withValues(alpha: isDark ? 0.12 : 0.10);

  /// The D-pad focus highlight colour.
  static Color focus(bool isDark) => isDark ? accent : lightAccentFocus;

  /// Translucent accent fill for widgets that tint a background on focus.
  static Color focusFill(bool isDark) =>
      focus(isDark).withValues(alpha: 0.16);

  /// Soft accent halo used behind a focused card.
  static Color focusGlow(bool isDark) =>
      focus(isDark).withValues(alpha: isDark ? 0.20 : 0.18);

  // ── Gradients — near-flat backgrounds matching the design's solid canvas ────
  static const homeGradientDark = RadialGradient(
    center: Alignment(-0.4, -0.8),
    radius: 1.5,
    colors: [Color(0xFF0B1426), Color(0xFF080F1E), oceanAbyss],
    stops:  [0.0, 0.55, 1.0],
  );

  static const listGradientDark = LinearGradient(
    begin:  Alignment.topCenter,
    end:    Alignment.bottomCenter,
    colors: [Color(0xFF0A1120), oceanAbyss],
  );

  static const settingsGradientDark = LinearGradient(
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
    colors: [oceanMid, oceanAbyss],
  );

  static const homeGradientLight = RadialGradient(
    center: Alignment(-0.4, -0.8),
    radius: 1.5,
    colors: [Color(0xFFFBF7F0), lightBackground, lightSurfaceVariant],
    stops:  [0.0, 0.6, 1.0],
  );

  static const listGradientLight = LinearGradient(
    begin:  Alignment.topCenter,
    end:    Alignment.bottomCenter,
    colors: [Color(0xFFFBF7F0), lightBackground],
  );
}
