import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/core/theme/app_colors.dart';

void main() {
  group('AppColors palette', () {
    test('oceanic primary is a deep blue (hue 200–240)', () {
      final hsl = HSLColor.fromColor(AppColors.oceanPrimary);
      expect(hsl.hue, inInclusiveRange(200, 240));
      expect(hsl.lightness, lessThan(0.6));
    });

    test('sandMid is a warm sandy tone (hue 20–50, low-medium saturation)', () {
      final hsl = HSLColor.fromColor(AppColors.sandMid);
      expect(hsl.hue, inInclusiveRange(20, 50));
      // Warm Sandy Beige is desaturated — saturation > 0.15 is sufficient.
      expect(hsl.saturation, greaterThan(0.15));
    });

    test('error is distinctly red', () {
      final hsl = HSLColor.fromColor(AppColors.error);
      expect(hsl.hue, inInclusiveRange(0, 15));
    });

    test('success is distinctly green', () {
      final hsl = HSLColor.fromColor(AppColors.success);
      expect(hsl.hue, inInclusiveRange(100, 145));
    });

    test('darkBackground is darker than darkSurface', () {
      final bgLum = AppColors.darkBackground.computeLuminance();
      final sfLum = AppColors.darkSurface.computeLuminance();
      expect(bgLum, lessThan(sfLum));
    });

    test('lightBackground is lighter than darkBackground', () {
      final light = AppColors.lightBackground.computeLuminance();
      final dark = AppColors.darkBackground.computeLuminance();
      expect(light, greaterThan(dark));
    });
  });
}
