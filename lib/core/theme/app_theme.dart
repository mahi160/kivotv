import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Central theme factory for Kivo.
///
/// Usage in [MaterialApp.router]:
/// ```dart
/// theme:      AppTheme.light(),
/// darkTheme:  AppTheme.dark(),
/// themeMode:  ThemeMode.system,   // light is default on most devices
/// ```
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark()  => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor:   AppColors.oceanDeepBlue,
      brightness:  brightness,
      // Override key surfaces so the brand palette is respected exactly.
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
        elevation:             0,
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
            ? AppColors.darkSurface          // #1A2B38 — solid ocean dark
            : AppColors.lightSurface,        // #FFFFFF — solid white
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
          borderSide: BorderSide(
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
        color:             isDark
            ? AppColors.darkSurface
            : AppColors.lightSurface,
        surfaceTintColor:  Colors.transparent,
        elevation:         0,
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

      // ── Text theme (Inter) ─────────────────────────────────────────────
      textTheme:        _buildTextTheme(isDark),
      primaryTextTheme: _buildTextTheme(isDark),

      // ── Focus colour — warm golden, visible on both modes ──────────────
      focusColor: AppColors.goldenDriftwood.withValues(alpha: 0.20),
    );
  }

  static TextTheme _buildTextTheme(bool isDark) {
    final onSurface = isDark
        ? AppColors.darkOnSurface
        : AppColors.lightOnSurface;
    final onSurfaceVariant = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;

    return GoogleFonts.interTextTheme().copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 42, fontWeight: FontWeight.w900,
        color: onSurface, letterSpacing: -0.5,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 34, fontWeight: FontWeight.w900,
        color: onSurface, letterSpacing: -0.25,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 26, fontWeight: FontWeight.w800,
        color: onSurface,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 22, fontWeight: FontWeight.w800,
        color: onSurface,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 19, fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 18, fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w400,
        color: onSurfaceVariant,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400,
        color: onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 18, fontWeight: FontWeight.w700,
        color: onSurface,
      ),
    );
  }
}
