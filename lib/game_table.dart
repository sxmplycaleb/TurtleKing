import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_state.dart';
import 'theme.dart';

/// The felt card-table background of the game screen.
///
/// A deep green radial "table light" gradient with a subtle, deterministic
/// felt texture and a soft vignette. Pure decoration — it never touches
/// game state and stays quiet enough that cards and text remain the focus.
class GameTableBackground extends StatelessWidget {
  const GameTableBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.5,
            colors: [
              Color(0xFF1C5C43), // table light center
              Color(0xFF11402F),
              TurtleKingColors.feltDark,
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: CustomPaint(painter: _FeltTexturePainter()),
      ),
    );
  }
}

/// Paints sparse, faint darker flecks so the felt reads as cloth, not flat
/// color. Deterministic (fixed seed) so it never changes between frames.
class _FeltTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.05);
    for (var i = 0; i < 220; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final r = 0.5 + random.nextDouble() * 0.9;
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A stylized water cup whose size reflects [CupSize].
///
/// Purely presentational: the cup size is read from the authoritative
/// [GameState.cupSize] and never stored or changed here.
class TurtleKingCup extends StatelessWidget {
  const TurtleKingCup({super.key, required this.size, this.diameter = 64});

  /// The authoritative cup size to draw.
  final CupSize size;

  /// The base diameter of the cup graphic.
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final scale = switch (size) {
      CupSize.normal => 1.0,
      CupSize.large => 1.22,
      CupSize.extraLarge => 1.44,
    };
    return Semantics(
      label: '${size.label} cup',
      image: true,
      child: SizedBox(
        width: diameter * scale,
        height: diameter * 1.25 * scale,
        child: CustomPaint(painter: _CupPainter()),
      ),
    );
  }
}

/// Draws a glass cup with a gold rim and a rising water fill.
class _CupPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Cup body (trapezoid, wider at the rim).
    final body = Path()
      ..moveTo(w * 0.20, h * 0.28)
      ..lineTo(w * 0.80, h * 0.28)
      ..lineTo(w * 0.72, h * 0.88)
      ..quadraticBezierTo(w * 0.50, h * 0.94, w * 0.28, h * 0.88)
      ..close();

    // Glass highlight.
    final glass = Paint()
      ..color = const Color(0xFFEAF4FB).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawPath(body, glass);

    // Water fill.
    final water = Path()
      ..moveTo(w * 0.225, h * 0.55)
      ..lineTo(w * 0.775, h * 0.55)
      ..lineTo(w * 0.72, h * 0.88)
      ..quadraticBezierTo(w * 0.50, h * 0.94, w * 0.28, h * 0.88)
      ..close();
    final waterPaint = Paint()
      ..color = const Color(0xFF4FA3D9).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawPath(water, waterPaint);

    // Water surface line.
    final surface = Paint()
      ..color = const Color(0xFFD6F0FF).withValues(alpha: 0.9)
      ..strokeWidth = math.max(1.2, w * 0.02)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.225, h * 0.55),
      Offset(w * 0.775, h * 0.55),
      surface,
    );

    // Gold rim.
    final rim = Paint()
      ..color = TurtleKingColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, w * 0.05);
    canvas.drawLine(
      Offset(w * 0.20, h * 0.28),
      Offset(w * 0.80, h * 0.28),
      rim,
    );

    // Handle on the right.
    final handle = Paint()
      ..color = const Color(0xFFEAF4FB).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, w * 0.05);
    canvas.drawArc(
      Rect.fromLTWH(w * 0.72, h * 0.34, w * 0.22, h * 0.34),
      -0.9,
      1.9,
      false,
      handle,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A gold crown emblem used for the Turtle King victory presentation.
class TurtleKingCrown extends StatelessWidget {
  const TurtleKingCrown({super.key, this.size = 72});

  /// The crown's bounding size.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Turtle King crown',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CrownPainter()),
      ),
    );
  }
}

/// Draws a simple three-point gold crown with jewel tips and a band.
class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final crown = Path()
      ..moveTo(w * 0.10, h * 0.72)
      ..lineTo(w * 0.10, h * 0.42)
      ..lineTo(w * 0.30, h * 0.58)
      ..lineTo(w * 0.50, h * 0.16)
      ..lineTo(w * 0.70, h * 0.58)
      ..lineTo(w * 0.90, h * 0.42)
      ..lineTo(w * 0.90, h * 0.72)
      ..close();

    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE082), TurtleKingColors.gold],
      ).createShader(Offset.zero & size);
    canvas.drawPath(crown, fill);

    final outline = Paint()
      ..color = TurtleKingColors.goldDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.03);
    canvas.drawPath(crown, outline);

    // Band line.
    final band = Paint()
      ..color = TurtleKingColors.goldDark
      ..strokeWidth = math.max(1.2, w * 0.03);
    canvas.drawLine(
      Offset(w * 0.10, h * 0.60),
      Offset(w * 0.90, h * 0.60),
      band,
    );

    // Jewels on the side points.
    final jewel = Paint()..color = const Color(0xFF3E7CB1);
    for (final x in [0.10, 0.90]) {
      canvas.drawCircle(Offset(w * x, h * 0.42), w * 0.045, jewel);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
