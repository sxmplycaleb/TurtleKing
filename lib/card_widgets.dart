import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import 'card.dart';
import 'theme.dart';

/// The single-character symbol used for [rank] on a card face, e.g. "A", "10"
/// or "K".
String rankSymbol(Rank rank) => switch (rank) {
  Rank.ace => 'A',
  Rank.two => '2',
  Rank.three => '3',
  Rank.four => '4',
  Rank.five => '5',
  Rank.six => '6',
  Rank.seven => '7',
  Rank.eight => '8',
  Rank.nine => '9',
  Rank.ten => '10',
  Rank.jack => 'J',
  Rank.queen => 'Q',
  Rank.king => 'K',
};

/// The unicode glyph used for [suit] on a card face.
String suitSymbol(Suit suit) => switch (suit) {
  Suit.hearts => '♥',
  Suit.diamonds => '♦',
  Suit.clubs => '♣',
  Suit.spades => '♠',
};

/// Whether [suit] renders in red (hearts/diamonds) rather than black.
bool isRedSuit(Suit suit) => suit == Suit.hearts || suit == Suit.diamonds;

/// The standard poker-card width/height ratio (~2.5 : 3.5).
const double _cardAspectRatio = 2.5 / 3.5;

/// A responsive default card width: roughly a quarter of the screen width,
/// clamped so cards stay readable on large phones and fit on small ones.
double defaultCardWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.26).clamp(72.0, 104.0);

/// A realistic face-up playing card.
///
/// Renders the existing [Card] model (rank + suit) with a cream surface,
/// rounded corners, subtle depth, red/black suit colors, and corner indices —
/// the standard poker-card presentation. Purely presentational: it never
/// mutates game state.
class PlayingCard extends StatelessWidget {
  const PlayingCard({
    super.key,
    required this.card,
    this.width,
    this.highlighted = false,
    this.semanticLabel,
    this.style,
  });

  /// The card to render face-up.
  final Card card;

  /// The card width; when null a responsive default is used.
  final double? width;

  /// Draws an accent border/glow to single out this card (e.g. the smallest
  /// hand at the reveal).
  final bool highlighted;

  /// Overrides the semantics label; defaults to the card's display name.
  final String? semanticLabel;

  /// The card style to render with; when null the active theme's style is
  /// used (defaulting to Classic Poker).
  final CardStyle? style;

  @override
  Widget build(BuildContext context) {
    final cardStyle = style ?? CardStyle.of(context);
    final size = width ?? defaultCardWidth(context);
    final suit = suitSymbol(card.suit);
    final ink = isRedSuit(card.suit) ? cardStyle.inkRed : cardStyle.inkDark;

    return Semantics(
      label: semanticLabel ?? card.displayName,
      image: true,
      // The corner indices and center pip are decorative: a screen reader
      // should hear one clean label, not the raw rank/suit glyphs.
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size / _cardAspectRatio,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cardStyle.faceTop, cardStyle.faceBottom],
          ),
          borderRadius: BorderRadius.circular(size * 0.09),
          border: Border.all(
            color: highlighted ? cardStyle.highlight : cardStyle.faceBorder,
            width: highlighted ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: size * 0.12,
              offset: Offset(0, size * 0.07),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Center pip: a soft watermark circle behind the large suit.
            Center(
              child: Container(
                width: size * 0.62,
                height: size * 0.62,
                decoration: BoxDecoration(
                  color: cardStyle.watermark,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Center pip: the diamond is drawn as a filled shape (font
            // diamond glyphs are thin outlines); the other suits are solid
            // glyphs already.
            Center(
              child: card.suit == Suit.diamonds
                  ? CustomPaint(
                      size: Size(size * 0.44, size * 0.44),
                      painter: _DiamondPipPainter(color: ink),
                    )
                  : Text(
                      suit,
                      style: TextStyle(
                        color: ink,
                        fontSize: size * 0.5,
                        height: 1,
                      ),
                    ),
            ),
            // Corner indices, top-left and bottom-right (rotated).
            Positioned(
              left: size * 0.07,
              top: size * 0.05,
              child: _CornerIndex(
                rank: rankSymbol(card.rank),
                suit: suit,
                ink: ink,
                size: size,
              ),
            ),
            Positioned(
              right: size * 0.07,
              bottom: size * 0.05,
              child: Transform.rotate(
                angle: math.pi,
                child: _CornerIndex(
                  rank: rankSymbol(card.rank),
                  suit: suit,
                  ink: ink,
                  size: size,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a solid diamond pip (real card pips are filled shapes).
class _DiamondPipPainter extends CustomPainter {
  const _DiamondPipPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DiamondPipPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The rank-over-suit index printed in a card corner.
class _CornerIndex extends StatelessWidget {
  const _CornerIndex({
    required this.rank,
    required this.suit,
    required this.ink,
    required this.size,
  });

  final String rank;
  final String suit;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rank,
          style: TextStyle(
            color: ink,
            fontSize: size * 0.2,
            height: 1.05,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          suit,
          style: TextStyle(color: ink, fontSize: size * 0.16, height: 1.05),
        ),
      ],
    );
  }
}

/// A face-down card: the Turtle King card back.
///
/// Deliberately takes NO [Card] and renders no rank, suit, or identity —
/// it exists so the UI can show "a card is here" without ever leaking which
/// card it is, in any channel (pixels, semantics, or keys).
class CardBack extends StatelessWidget {
  const CardBack({super.key, this.width, this.style});

  /// The card width; when null a responsive default is used.
  final double? width;

  /// The card style to render with; when null the active theme's style is
  /// used (defaulting to Classic Poker).
  final CardStyle? style;

  @override
  Widget build(BuildContext context) {
    final cardStyle = style ?? CardStyle.of(context);
    final size = width ?? defaultCardWidth(context);
    return Semantics(
      label: 'Card back',
      image: true,
      // The emblem inside is decorative; the label fully describes the back.
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size / _cardAspectRatio,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cardStyle.backSurface,
              Color.lerp(cardStyle.backSurface, Colors.black, 0.10)!,
            ],
          ),
          borderRadius: BorderRadius.circular(size * 0.09),
          border: Border.all(color: cardStyle.backBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: size * 0.12,
              offset: Offset(0, size * 0.07),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.07),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.06),
              border: Border.all(color: cardStyle.backRing, width: 1.4),
            ),
            padding: EdgeInsets.all(size * 0.05),
            child: Container(
              decoration: BoxDecoration(
                color: cardStyle.backDisc,
                shape: BoxShape.circle,
              ),
              padding: EdgeInsets.all(size * 0.08),
              child: Image.asset(
                'assets/branding/turtle_king_emblem.png',
                fit: BoxFit.contain,
                // The emblem is decorative; the enclosing Semantics already
                // labels this widget as a card back.
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The face-up card widget used by the game flow.
///
/// Kept as a thin wrapper around [PlayingCard] so existing consumers and
/// tests that reference [CardFace.card] keep working unchanged.
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.card,
    this.width,
    this.highlighted = false,
    this.style,
  });

  /// The card to render face-up.
  final Card card;

  /// The card width; when null a responsive default is used.
  final double? width;

  /// Draws an accent border/glow to single out this card (e.g. the smallest
  /// hand at the reveal).
  final bool highlighted;

  /// The card style to render with; when null the active theme's style is
  /// used (defaulting to Classic Poker).
  final CardStyle? style;

  @override
  Widget build(BuildContext context) {
    return PlayingCard(
      card: card,
      width: width,
      highlighted: highlighted,
      style: style,
    );
  }
}
