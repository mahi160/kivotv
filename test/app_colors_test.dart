import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/core/theme/app_colors.dart';

void main() {
  group('AppColors palette (warm-cinematic, one accent per mode)', () {
    test('dark accent is a warm amber', () {
      final hsl = HSLColor.fromColor(AppColors.accent);
      expect(hsl.hue, inInclusiveRange(20, 45));
      expect(hsl.saturation, greaterThan(0.6)); // vivid, not muted
    });

    test('light accent is a teal', () {
      final hsl = HSLColor.fromColor(AppColors.lightAccent);
      expect(hsl.hue, inInclusiveRange(180, 210));
      expect(hsl.saturation, greaterThan(0.4));
    });

    test('there is ONE accent per mode: primary, favourite + focus derive from it', () {
      // Dark mode: everything is the amber accent.
      expect(AppColors.oceanPrimary, AppColors.accent);
      expect(AppColors.favActive, AppColors.accent);
      expect(AppColors.primary(true), AppColors.accent);
      expect(HSLColor.fromColor(AppColors.focus(true)).hue,
          inInclusiveRange(20, 45));
      // Light mode: everything is the teal accent.
      expect(AppColors.primary(false), AppColors.lightAccent);
      expect(HSLColor.fromColor(AppColors.focus(false)).hue,
          inInclusiveRange(180, 210));
    });

    test('error is distinctly red', () {
      final hue = HSLColor.fromColor(AppColors.error).hue;
      expect(hue >= 350 || hue <= 20, isTrue, reason: 'hue=$hue');
    });

    test('success is distinctly green', () {
      expect(HSLColor.fromColor(AppColors.success).hue, inInclusiveRange(120, 170));
    });

    test('canvas is near-black and darker than the card surface', () {
      expect(AppColors.darkBackground.computeLuminance(), lessThan(0.02));
      expect(
        AppColors.darkBackground.computeLuminance(),
        lessThan(AppColors.darkSurface.computeLuminance()),
      );
    });

    test('lightBackground is lighter than darkBackground', () {
      expect(
        AppColors.lightBackground.computeLuminance(),
        greaterThan(AppColors.darkBackground.computeLuminance()),
      );
    });
  });
}
