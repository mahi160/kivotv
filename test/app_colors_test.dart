import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/core/theme/app_colors.dart';

void main() {
  group('AppColors palette (dark-cinematic, single accent)', () {
    test('accent is a vivid blue', () {
      final hsl = HSLColor.fromColor(AppColors.accent);
      expect(hsl.hue, inInclusiveRange(200, 240));
      expect(hsl.saturation, greaterThan(0.6)); // vivid, not muted
    });

    test('there is ONE accent: primary, favourite + focus all derive from it', () {
      expect(AppColors.oceanPrimary, AppColors.accent);
      expect(AppColors.favActive, AppColors.accent);
      // The D-pad focus highlight is always the (bright) accent.
      for (final c in [AppColors.focus(true), AppColors.focus(false)]) {
        expect(HSLColor.fromColor(c).hue, inInclusiveRange(200, 240));
      }
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
