import 'package:flutter/material.dart';

/// A simple turtle illustration used as the home screen mascot.
///
/// Drawn with basic [CustomPaint] shapes so no image assets or packages
/// are required.
class TurtleArt extends StatelessWidget {
  const TurtleArt({super.key, this.size = 160});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _TurtlePainter(),
    );
  }
}

/// Paints a side-view turtle: shell with scutes, head, two legs, and a tail.
class _TurtlePainter extends CustomPainter {
  const _TurtlePainter();

  static const _shell = Color(0xFF388E3C);
  static const _shellPattern = Color(0xFF66BB6A);
  static const _skin = Color(0xFF8BC34A);
  static const _eye = Color(0xFF1B5E20);

  @override
  void paint(Canvas canvas, Size size) {
    // Paint in a fixed 200x200 space, scaled to the widget size.
    canvas.scale(size.width / 200, size.height / 200);

    final skin = Paint()..color = _skin;
    final shellPaint = Paint()..color = _shell;
    final patternPaint = Paint()
      ..color = _shellPattern
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    // Legs.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(116, 150), width: 38, height: 20),
      skin,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(66, 152), width: 34, height: 18),
      skin,
    );

    // Tail.
    final tail = Path()
      ..moveTo(42, 106)
      ..lineTo(22, 114)
      ..lineTo(44, 122)
      ..close();
    canvas.drawPath(tail, skin);

    // Shell.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 112), width: 116, height: 80),
      shellPaint,
    );

    // Shell scutes (segments) as a lighter outline.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 112), width: 84, height: 52),
      patternPaint,
    );
    canvas.drawLine(const Offset(100, 86), const Offset(100, 138), patternPaint);
    canvas.drawLine(const Offset(58, 112), const Offset(142, 112), patternPaint);

    // Head.
    canvas.drawCircle(const Offset(162, 86), 26, skin);

    // Eye.
    canvas.drawCircle(const Offset(168, 80), 4, Paint()..color = _eye);
  }

  @override
  bool shouldRepaint(covariant _TurtlePainter oldDelegate) => false;
}
