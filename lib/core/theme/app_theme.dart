import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Central theme factory for Kivo.
///
/// Usage in [MaterialApp.router]:
/// ```dart
/// theme:      AppTheme.light(),
/// darkTheme:  AppTheme.dark(),
/// themeMode:  ThemeMode.system,
/// ```
abstract final class AppTheme {
  // ── Public factories ─────────────────────────────────────────────────────

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  // ── Private builder ──────────────────────────────────────────────────────

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.oceanPrimary,
      brightness: brightness,
      // Override key surfaces so the oceanic palette is respected exactly.
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      onSurface: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
      primary: AppColors.oceanPrimary,
      onPrimary: Colors.white,
      secondary: AppColors.sandMid,
      onSecondary: AppColors.oceanAbyss,
      tertiary: AppColors.sandLight,
      onTertiary: AppColors.oceanDeep,
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,

      // ── Scaffold ───────────────────────────────────────────────────────
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,

      // ── AppBar ─────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor:
            isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      // ── Elevated buttons ───────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isDark ? AppColors.oceanMid : AppColors.oceanPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          textStyle: const TextStyle(
            fontSize: 18,
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
          foregroundColor:
              isDark ? AppColors.oceanBright : AppColors.oceanPrimary,
        ),
      ),

      // ── Icon buttons ───────────────────────────────────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor:
              isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
        ),
      ),

      // ── Input fields ───────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : AppColors.lightSurfaceVariant,
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
            color: isDark ? AppColors.oceanBright : AppColors.oceanPrimary,
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
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),

      // ── Dialogs ────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
      ),

      // ── Progress indicator ─────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.oceanBright,
      ),

      // ── Text theme ─────────────────────────────────────────────────────
      // Uses the system default (Roboto on Android), size overrides below.
      textTheme: _buildTextTheme(isDark),

      // ── Focus ──────────────────────────────────────────────────────────
      // Sandy accent for focus highlights — visible on both dark/light.
      focusColor: AppColors.sandMid.withValues(alpha: 0.18),
    );
  }

  static TextTheme _buildTextTheme(bool isDark) {
    final base = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final onSurface = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final onSurfaceVariant =
        isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant;

    return base.copyWith(
      // Display / hero text (app title)
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 42,
        fontWeight: FontWeight.w900,
        color: onSurface,
      ),
      // Screen headings
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w900,
        color: onSurface,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: onSurface,
      ),
      // Section labels
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: onSurface,
      ),
      // List tile primary text
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: onSurface,
      ),
      // Body / descriptions
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 18,
        color: onSurface,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 16,
        color: onSurfaceVariant,
      ),
      // Captions / metadata
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 14,
        color: onSurfaceVariant,
      ),
    );
  }
}
