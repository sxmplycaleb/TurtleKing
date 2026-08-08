import 'package:flutter/material.dart';

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
