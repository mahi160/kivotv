import 'package:flutter/material.dart';

/// The Kivo logomark — a play glyph that sits on the brand-coloured tile drawn
/// by its parent (nav bar, drawer, splash).
///
/// Matches the redesign: a rounded vertical bar + a play triangle, rendered in
/// a single solid [color] (white by default, for contrast on the amber/teal
/// brand square).
class KivoLogo extends StatelessWidget {
  const KivoLogo({super.key, this.size = 48, this.color = Colors.white});

  final double size;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KivoLogoPainter(color)),
    );
  }
}

class _KivoLogoPainter extends CustomPainter {
  const _KivoLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Coordinates are authored on the design's 0..38 viewBox, then scaled to
    // the requested paint size so the mark stays crisp at any dimension.
    final s = size.width / 38.0;
    final paint = Paint()
      ..color       = color
      ..style       = PaintingStyle.fill
      ..isAntiAlias = true;

    // ── Vertical bar (the "spine") ──────────────────────────────────────────
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(10 * s, 10 * s, 4 * s, 18 * s),
      Radius.circular(2 * s),
    );
    canvas.drawRRect(bar, paint);

    // ── Play triangle ───────────────────────────────────────────────────────
    final triangle = Path()
      ..moveTo(16 * s, 10.5 * s)
      ..lineTo(29 * s, 19 * s)
      ..lineTo(16 * s, 27.5 * s)
      ..close();
    canvas.drawPath(triangle, paint);
  }

  @override
  bool shouldRepaint(_KivoLogoPainter oldDelegate) => oldDelegate.color != color;
}
