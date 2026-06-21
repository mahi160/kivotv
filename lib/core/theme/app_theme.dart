import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Central theme factory for Kivo.
///
/// Uses the bundled Outfit font (assets/fonts/) rather than fetching it from
/// the network at runtime, so the UI is pixel-perfect on first launch even
/// on TVs with slow or no internet connectivity.
///
/// The app uses a fixed cinematic palette (no Material You / dynamic colour) so
/// the brand look is identical on every device.
///
/// Usage in [MaterialApp.router]:
/// ```dart
/// theme:      AppTheme.light(),
/// darkTheme:  AppTheme.dark(),
/// themeMode:  ref.watch(themeModeProvider),
/// ```
abstract final class AppTheme {
  static const fontFamily = 'Outfit';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark()  => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark  = brightness == Brightness.dark;
    final primary = AppColors.primary(isDark);

    final colorScheme = ColorScheme.fromSeed(
      seedColor:   primary,
      brightness:  brightness,
      surface:     isDark ? AppColors.darkSurface   : AppColors.lightSurface,
      onSurface:   isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
      primary:     primary,
      onPrimary:   isDark ? AppColors.darkBackground : Colors.white,
      secondary:   AppColors.accentBright,
      onSecondary: AppColors.lightOnSurface,
      tertiary:    primary,
      onTertiary:  isDark ? AppColors.darkBackground : Colors.white,
      error:       AppColors.error,
    );

    return ThemeData(
      useMaterial3:  true,
      brightness:    brightness,
      colorScheme:   colorScheme,
      fontFamily:    fontFamily,

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
          backgroundColor: primary,
          foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical:   AppSpacing.sm + 4,
          ),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
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
        style: TextButton.styleFrom(foregroundColor: primary),
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
          borderSide: BorderSide(color: primary, width: 2),
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

      // ── Drawer ─────────────────────────────────────────────────────────
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? AppColors.darkHeader : AppColors.lightHeader,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
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
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),

      // ── Text theme (Outfit, bundled) ───────────────────────────────────
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

    // All styles use the bundled Outfit family. FontWeight values must match
    // the weights declared in pubspec.yaml (400/500/600/700/900).
    TextStyle outfit({
      required double fontSize,
      required FontWeight fontWeight,
      required Color color,
      double? letterSpacing,
      double? height,
    }) =>
        TextStyle(
          fontFamily:    fontFamily,
          fontSize:      fontSize,
          fontWeight:    fontWeight,
          color:         color,
          letterSpacing: letterSpacing,
          height:        height,
        );

    return TextTheme(
      displayLarge:  outfit(fontSize: 42, fontWeight: FontWeight.w700,
          color: onSurface, letterSpacing: -0.5),
      headlineLarge: outfit(fontSize: 34, fontWeight: FontWeight.w700,
          color: onSurface, letterSpacing: -0.6),
      headlineMedium: outfit(fontSize: 26, fontWeight: FontWeight.w600,
          color: onSurface, letterSpacing: -0.3),
      titleLarge:  outfit(fontSize: 22, fontWeight: FontWeight.w600,
          color: onSurface, letterSpacing: -0.3),
      titleMedium: outfit(fontSize: 19, fontWeight: FontWeight.w600,
          color: onSurface),
      titleSmall:  outfit(fontSize: 16, fontWeight: FontWeight.w500,
          color: onSurface),
      bodyLarge:   outfit(fontSize: 18, fontWeight: FontWeight.w400,
          color: onSurface),
      bodyMedium:  outfit(fontSize: 16, fontWeight: FontWeight.w400,
          color: onSurfaceVariant),
      bodySmall:   outfit(fontSize: 14, fontWeight: FontWeight.w400,
          color: onSurfaceVariant),
      labelLarge:  outfit(fontSize: 18, fontWeight: FontWeight.w600,
          color: onSurface),
    );
  }
}
