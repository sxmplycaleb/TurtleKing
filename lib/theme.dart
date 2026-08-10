import 'package:flutter/material.dart';

/// The Turtle King brand palette, shared across screens.
///
/// Navy/gold is the product identity (splash, launcher, logo); the deep
/// greens are the card-table felt used by the game screen.
abstract final class TurtleKingColors {
  /// Brand navy (splash background, card-back emblem disc).
  static const navy = Color(0xFF0B263C);

  /// Brand gold (crowns, rims, highlights).
  static const gold = Color(0xFFD4AF37);

  /// Darker gold for outlines on light backgrounds.
  static const goldDark = Color(0xFFB8860B);

  /// The felt green at the center of the table light.
  static const felt = Color(0xFF1C5C43);

  /// The deep green at the table edges.
  static const feltDark = Color(0xFF08211A);

  /// The cream surface of a card face.
  static const cardCream = Color(0xFFFDFBF4);

  /// The red used for hearts/diamonds.
  static const suitRed = Color(0xFFC62828);

  /// The near-black used for spades/clubs.
  static const suitBlack = Color(0xFF212121);
}

/// Builds the shared visual theme for Turtle King.
///
/// Kept intentionally small: colors and typography can grow here as the
/// game UI is built out in later milestones.
ThemeData buildTheme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32));

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
  );
}
