import 'package:flutter/material.dart';

import 'player_setup_screen.dart';
import 'turtle_art.dart';

/// The Turtle King home screen.
///
/// Pure branding. The New Game button opens the player setup screen, the
/// entry point into the game flow.
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
                onPressed: () => _startNewGame(context),
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

  /// Entry point for starting a game: opens player setup.
  void _startNewGame(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlayerSetupScreen(),
      ),
    );
  }
}
