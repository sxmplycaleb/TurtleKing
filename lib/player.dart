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
}
