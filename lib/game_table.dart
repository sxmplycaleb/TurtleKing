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
    final style = GameTableStyle.of(context);
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.5,
            colors: [style.feltTop, style.feltMid, style.feltBottom],
            stops: const [0.0, 0.55, 1.0],
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

/// A stylized shot glass whose size reflects [CupSize].
///
/// Purely presentational: the cup size is read from the authoritative
/// [GameState.cupSize] and never stored or changed here.
class TurtleKingCup extends StatelessWidget {
  const TurtleKingCup({super.key, required this.size, this.diameter = 64});

  /// The authoritative cup size to draw.
  final CupSize size;

  /// The base width of the shot glass graphic.
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final style = GameTableStyle.of(context);
    final scale = switch (size) {
      CupSize.normal => 1.0,
      CupSize.large => 1.22,
      CupSize.extraLarge => 1.44,
    };
    return Semantics(
      label: '${size.label} shot glass',
      image: true,
      child: SizedBox(
        width: diameter * scale,
        height: diameter * 0.82 * scale,
        child: CustomPaint(painter: _CupPainter(accent: style.accent)),
      ),
    );
  }
}

/// Draws a shot glass with a thick base, slight taper, and a drink fill.
class _CupPainter extends CustomPainter {
  const _CupPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shot glass body — nearly straight sides, very slightly wider at
    // the top rim than at the base, giving the classic shot-glass profile.
    final body = Path()
      ..moveTo(w * 0.15, h * 0.06)
      ..lineTo(w * 0.85, h * 0.06)
      ..lineTo(w * 0.80, h * 0.82)
      ..lineTo(w * 0.20, h * 0.82)
      ..close();

    // Glass highlight.
    final glass = Paint()
      ..color = const Color(0xFFEAF4FB).withValues(alpha: 0.50)
      ..style = PaintingStyle.fill;
    canvas.drawPath(body, glass);

    // Shot liquid fill (amber/golden — spirits-colored).
    final liquid = Path()
      ..moveTo(w * 0.19, h * 0.38)
      ..lineTo(w * 0.81, h * 0.38)
      ..lineTo(w * 0.80, h * 0.82)
      ..lineTo(w * 0.20, h * 0.82)
      ..close();
    final liquidPaint = Paint()
      ..color = const Color(0xFFE8B84B).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawPath(liquid, liquidPaint);

    // Liquid surface line.
    final surface = Paint()
      ..color = const Color(0xFFF5D98A).withValues(alpha: 0.9)
      ..strokeWidth = math.max(1.2, w * 0.02)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.19, h * 0.38),
      Offset(w * 0.81, h * 0.38),
      surface,
    );

    // Thick glass base (shot-glass signature).
    final base = Path()
      ..moveTo(w * 0.20, h * 0.82)
      ..lineTo(w * 0.80, h * 0.82)
      ..lineTo(w * 0.76, h * 0.94)
      ..quadraticBezierTo(w * 0.50, h * 0.98, w * 0.24, h * 0.94)
      ..close();
    final basePaint = Paint()
      ..color = const Color(0xFFEAF4FB).withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawPath(base, basePaint);

    // Accent rim at the top.
    final rim = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, w * 0.04);
    canvas.drawLine(
      Offset(w * 0.15, h * 0.06),
      Offset(w * 0.85, h * 0.06),
      rim,
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
    final style = GameTableStyle.of(context);
    return Semantics(
      label: 'Turtle King crown',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CrownPainter(
            fillTop: style.accentSoft,
            fillBottom: style.accent,
            outline: style.accent,
          ),
        ),
      ),
    );
  }
}

/// Draws a simple three-point crown with jewel tips and a band, tinted with
/// the active accent.
class _CrownPainter extends CustomPainter {
  const _CrownPainter({
    required this.fillTop,
    required this.fillBottom,
    required this.outline,
  });

  final Color fillTop;
  final Color fillBottom;
  final Color outline;

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
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [fillTop, fillBottom],
      ).createShader(Offset.zero & size);
    canvas.drawPath(crown, fill);

    final outlinePaint = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.03);
    canvas.drawPath(crown, outlinePaint);

    // Band line.
    final band = Paint()
      ..color = outline
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
