import 'package:flutter/material.dart';

import 'turtle_art.dart';

/// The Turtle King home screen.
///
/// Pure branding for this milestone. The New Game button is the entry point
/// into the game flow, which is implemented in a later milestone.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TurtleArt(),
              const SizedBox(height: 24),
              Text(
                'Turtle King',
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Pass & Play Card Game',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: _startNewGame,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  textStyle: theme.textTheme.titleMedium,
                ),
                child: const Text('New Game'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Entry point for starting a game.
  ///
  /// Game setup and flow are implemented in a later milestone; this stays a
  /// no-op so the button is wired up without introducing dead behavior.
  void _startNewGame() {
    // Intentionally empty in Milestone 01.
  }
}
