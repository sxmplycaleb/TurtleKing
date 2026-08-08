import 'package:flutter/material.dart';

/// Fixed, visually distinct colors auto-assigned to players.
///
/// Colors are picked automatically — players never choose their own. The
/// palette holds exactly one color per supported player, so every player in
/// a full game has a distinct color.
class PlayerColors {
  PlayerColors._();

  /// The auto-assignment palette, in assignment order.
  ///
  /// Material 600/800 shades chosen to be distinguishable from each other
  /// and from the green brand color used by the theme.
  static const List<Color> palette = [
    Color(0xFFD32F2F), // Red
    Color(0xFF1976D2), // Blue
    Color(0xFFF9A825), // Amber
    Color(0xFF8E24AA), // Purple
    Color(0xFF00897B), // Teal
    Color(0xFFD81B60), // Pink
    Color(0xFF3949AB), // Indigo
    Color(0xFFF4511E), // Orange
    Color(0xFF43A047), // Green
    Color(0xFF6D4C41), // Brown
  ];

  /// Maximum number of players a game supports (one per palette color).
  ///
  /// Kept in sync with [palette] by hand; a test asserts both agree.
  static const int maxPlayers = 10;

  /// Minimum number of players required to start a game.
  static const int minPlayers = 2;

  /// Returns the first palette color not currently in use by [usedColors],
  /// so colors are reused once a player is removed.
  static Color nextAvailable(Set<Color> usedColors) {
    for (final color in palette) {
      if (!usedColors.contains(color)) {
        return color;
      }
    }
    throw StateError('All player colors are in use.');
  }
}
