import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The Kivo logomark.
///
/// The shape reads as both the letter K and a play button ▶:
/// - Left vertical bar  = K's spine
/// - Two diagonal arms  = K's characteristic diagonals
/// - Arms converge at a single right-side point = ▶ play tip
/// - V-notch on the inner-left edge = K's characteristic indent
///
/// Colour: gradient left (Ocean Deep Blue) → right (Golden Driftwood).
class KivoLogo extends StatelessWidget {
  const KivoLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KivoLogoPainter()),
    );
  }
}

class _KivoLogoPainter extends CustomPainter {
  const _KivoLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Gradient: ocean blue (left) → golden driftwood (right) ──────────────
    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: const [
        AppColors.oceanDeepBlue,   // #5D768B
        AppColors.goldenDriftwood, // #E3C9A4
      ],
    ).createShader(Rect.fromLTWH(0, 0, w, h));

    final paint = Paint()
      ..shader = gradient
      ..style  = PaintingStyle.fill
      ..isAntiAlias = true;

    // ── Path ─────────────────────────────────────────────────────────────────
    //
    // Normalised coordinates (multiply by w / h):
    //
    //  (0.14, 0.08) ── (0.33, 0.08)
    //                     ╲ upper arm (quadratic bezier)
    //                      ──────────────► (0.92, 0.50)  ← play tip
    //                      ──────────────  (0.92, 0.50)
    //                     ╱ lower arm (quadratic bezier)
    //  (0.14, 0.92) ── (0.33, 0.92)
    //     │
    //   spine left side up to the notch:
    //     │ (0.14, 0.62) → (0.28, 0.50) ← notch vertex (K indent)
    //     │ (0.14, 0.38) → close
    //

    final path = Path();

    // Spine top-left → top-right corner of spine
    path.moveTo(w * 0.14, h * 0.08);
    path.lineTo(w * 0.33, h * 0.08);

    // Upper arm — slight inward curve gives dynamism without losing the K feel
    path.quadraticBezierTo(
      w * 0.62, h * 0.27,   // control point
      w * 0.92, h * 0.50,   // play tip
    );

    // Lower arm — symmetric
    path.quadraticBezierTo(
      w * 0.62, h * 0.73,   // control point
      w * 0.33, h * 0.92,   // spine bottom-right
    );

    // Spine bottom-right → bottom-left
    path.lineTo(w * 0.14, h * 0.92);

    // Up the left side of the spine to the lower edge of the notch
    path.lineTo(w * 0.14, h * 0.62);

    // Notch: the characteristic K indent that separates the two arms
    // Soft angle (not perfectly sharp) for a contemporary feel
    path.quadraticBezierTo(
      w * 0.24, h * 0.55,   // softening control
      w * 0.28, h * 0.50,   // notch vertex
    );
    path.quadraticBezierTo(
      w * 0.24, h * 0.45,   // softening control
      w * 0.14, h * 0.38,   // upper edge of notch
    );

    // Close back to spine top-left
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_KivoLogoPainter oldDelegate) => false;
}
