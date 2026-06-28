import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The Kivo TV-set logomark — self-contained, renders at any [size].
///
/// Matches the launcher icon exactly:
///   • Navy card background
///   • Amber rounded-rect TV outline with antennae + base bar
///   • Dark screen interior
///   • Amber vertical bar + steel-blue play triangle (the KivoLogo mark)
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
  @override
  void paint(Canvas canvas, Size sz) {
    final s = sz.width; // square canvas
    final amber = AppColors.accent;
    final navyCard  = AppColors.oceanDeep;   // #0E1929
    final navyScreen = AppColors.oceanAbyss; // #070D1A
    const steel = Color(0xFF6B8CAE);

    final paint = Paint()..isAntiAlias = true;

    // ── Card background ──────────────────────────────────────────────────────
    paint.color = navyCard;
    final cr = s * 0.22;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(cr)),
      paint,
    );

    // ── TV layout ─────────────────────────────────────────────────────────────
    final antH  = s * 0.155;
    final baseH = s * 0.065;
    final padLR = s * 0.175;

    final tvX   = padLR;
    final tvY   = s * 0.20 + antH;
    final tvW   = s - 2 * padLR;
    final tvH   = s - tvY - baseH - s * 0.06;
    final tvR   = tvW * 0.17;
    final bdr   = s * 0.030;

    // Amber TV body
    paint.color = amber;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(tvX, tvY, tvW, tvH), Radius.circular(tvR)),
      paint,
    );

    // Screen interior
    paint.color = navyScreen;
    final si = bdr;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(tvX+si, tvY+si, tvW-2*si, tvH-2*si),
        Radius.circular(math.max(2, tvR - si))),
      paint,
    );

    // ── Antennae ─────────────────────────────────────────────────────────────
    paint
      ..color       = amber
      ..strokeWidth = bdr * 1.15
      ..strokeCap   = StrokeCap.round
      ..style       = PaintingStyle.stroke;

    final lbx = tvX + tvW * 0.30;
    final rbx = tvX + tvW * 0.70;
    final bby = tvY;
    final alen = s * 0.165;

    canvas.drawLine(
      Offset(lbx, bby),
      Offset(lbx - alen * 0.55, bby - alen),
      paint,
    );
    canvas.drawLine(
      Offset(rbx, bby),
      Offset(rbx + alen * 0.55, bby - alen),
      paint,
    );

    // ── Base bar ──────────────────────────────────────────────────────────────
    paint.style = PaintingStyle.fill;
    final barW   = tvW * 0.33;
    final barThk = s * 0.030;
    final barX   = (s - barW) / 2;
    final barY   = tvY + tvH + s * 0.018;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barX, barY, barW, barThk),
        Radius.circular(barThk / 2)),
      paint,
    );

    // ── KivoLogo mark centred in screen ──────────────────────────────────────
    final sx = tvX + si;
    final sy = tvY + si;
    final sw = tvW - 2 * si;
    final sh = tvH - 2 * si;

    final mark = math.min(sw, sh) * 0.64;
    final mx   = sx + (sw - mark) / 2 + mark * 0.02;
    final my   = sy + (sh - mark) / 2;
    final ms   = mark / 38.0;
    final mr   = math.max(1.0, 2 * ms);

    // Vertical bar — amber
    paint.color = amber;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(mx + 10*ms, my + 10*ms, 4*ms, 18*ms),
        Radius.circular(mr)),
      paint,
    );

    // Play triangle — steel blue
    paint.color = steel;
    final path = Path()
      ..moveTo(mx + 16*ms, my + 10.5*ms)
      ..lineTo(mx + 29*ms, my + 19.0*ms)
      ..lineTo(mx + 16*ms, my + 27.5*ms)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_KivoLogoPainter _) => false;
}
