import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Central theme factory for Kivo.
///
/// Uses the bundled Inter font (assets/fonts/) rather than fetching it from
/// the network at runtime, so the UI is pixel-perfect on first launch even
/// on TVs with slow or no internet connectivity.
///
/// Usage in [MaterialApp.router]:
/// ```dart
/// theme:      AppTheme.light(),
/// darkTheme:  AppTheme.dark(),
/// themeMode:  ThemeMode.system,
/// ```
abstract final class AppTheme {
  /// [dynamicScheme] is the wallpaper-derived Material You scheme when the
  /// platform provides one (phones / some Google TV). It's null on most
  /// Android TV hardware, where we fall back to the fixed cinematic palette.
  static ThemeData light([ColorScheme? dynamicScheme]) =>
      _build(Brightness.light, dynamicScheme);
  static ThemeData dark([ColorScheme? dynamicScheme]) =>
      _build(Brightness.dark, dynamicScheme);

  static ThemeData _build(Brightness brightness, [ColorScheme? dynamicScheme]) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor:   AppColors.oceanDeepBlue,
          brightness:  brightness,
          surface:     isDark ? AppColors.darkSurface     : AppColors.lightSurface,
          onSurface:   isDark ? AppColors.darkOnSurface   : AppColors.lightOnSurface,
          primary:     AppColors.oceanDeepBlue,
          onPrimary:   Colors.white,
          secondary:   AppColors.warmSandyBeige,
          onSecondary: AppColors.lightOnSurface,
          tertiary:    AppColors.goldenDriftwood,
          onTertiary:  AppColors.lightOnSurface,
          error:       AppColors.error,
        );

    return ThemeData(
      useMaterial3:  true,
      brightness:    brightness,
      colorScheme:   colorScheme,

      // ── Scaffold ───────────────────────────────────────────────────────
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,

      // ── AppBar ─────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor:  Colors.transparent,
        foregroundColor:  isDark
            ? AppColors.darkOnSurface
            : AppColors.lightOnSurface,
        elevation:              0,
        scrolledUnderElevation: 0,
      ),

      // ── Elevated buttons ───────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.oceanDeepBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical:   AppSpacing.sm + 4,
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize:   18,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      ),

      // ── Text buttons ───────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.oceanDeepBlue,
        ),
      ),

      // ── Icon buttons ───────────────────────────────────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: isDark
              ? AppColors.darkOnSurface
              : AppColors.lightOnSurface,
        ),
      ),

      // ── Input fields ───────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurface
            : AppColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(
            color: AppColors.oceanDeepBlue,
            width: 2,
          ),
        ),
        hintStyle: TextStyle(
          color: isDark
              ? AppColors.darkOnSurfaceVariant
              : AppColors.lightOnSurfaceVariant,
        ),
      ),

      // ── Cards ──────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color:            isDark
            ? AppColors.darkSurface
            : AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation:        0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),

      // ── Dialogs ────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
      ),

      // ── Progress indicator ─────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.oceanDeepBlue,
      ),

      // ── Text theme (Inter, bundled) ────────────────────────────────────
      textTheme:        _buildTextTheme(isDark),
      primaryTextTheme: _buildTextTheme(isDark),

      // ── Focus colour — follows unified focus token ─────────────────────
      focusColor: AppColors.focusFill(isDark),
    );
  }

  static TextTheme _buildTextTheme(bool isDark) {
    final onSurface = isDark
        ? AppColors.darkOnSurface
        : AppColors.lightOnSurface;
    final onSurfaceVariant = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;

    // All styles use the bundled Inter family. FontWeight values must match
    // the weights declared in pubspec.yaml (400/500/600/700/900).
    TextStyle inter({
      required double fontSize,
      required FontWeight fontWeight,
      required Color color,
      double? letterSpacing,
      double? height,
    }) =>
        TextStyle(
          fontFamily:    'Inter',
          fontSize:      fontSize,
          fontWeight:    fontWeight,
          color:         color,
          letterSpacing: letterSpacing,
          height:        height,
        );

    return TextTheme(
      displayLarge:  inter(fontSize: 42, fontWeight: FontWeight.w900,
          color: onSurface, letterSpacing: -0.5),
      headlineLarge: inter(fontSize: 34, fontWeight: FontWeight.w900,
          color: onSurface, letterSpacing: -0.25),
      headlineMedium: inter(fontSize: 26, fontWeight: FontWeight.w700,
          color: onSurface),
      titleLarge:  inter(fontSize: 22, fontWeight: FontWeight.w700,
          color: onSurface),
      titleMedium: inter(fontSize: 19, fontWeight: FontWeight.w700,
          color: onSurface),
      titleSmall:  inter(fontSize: 16, fontWeight: FontWeight.w600,
          color: onSurface),
      bodyLarge:   inter(fontSize: 18, fontWeight: FontWeight.w400,
          color: onSurface),
      bodyMedium:  inter(fontSize: 16, fontWeight: FontWeight.w400,
          color: onSurfaceVariant),
      bodySmall:   inter(fontSize: 14, fontWeight: FontWeight.w400,
          color: onSurfaceVariant),
      labelLarge:  inter(fontSize: 18, fontWeight: FontWeight.w700,
          color: onSurface),
    );
  }
}
