import 'package:flutter/material.dart';

/// A single player configured before a game begins.
///
/// Intentionally minimal and immutable: identity, display name, and color.
/// Gameplay state (score, hand, etc.) belongs in later milestones.
class Player {
  const Player({required this.id, required this.name, required this.color});

  /// Unique identifier for this player within the game session.
  final String id;

  /// The player's display name (trimmed, never empty).
  final String name;

  /// The player's assigned color, used to tell players apart.
  final Color color;

  /// Value equality: two players are equal when their identity, display
  /// name, and color all match. Gameplay code (e.g. comparing the current
  /// player against the roster) relies on this being stable.
  @override
  bool operator ==(Object other) {
    return other is Player &&
        other.id == id &&
        other.name == name &&
        other.color == color;
  }

  @override
  int get hashCode => Object.hash(id, name, color);
}
