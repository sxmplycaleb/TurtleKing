import 'package:flutter/material.dart';

import 'how_to_play_screen.dart';
import 'player_setup_screen.dart';
import 'settings_screen.dart';

/// The Turtle King home screen.
///
/// Pure branding. The New Game button opens the player setup screen, the
/// entry point into the game flow; the settings button opens the
/// personalization screen. No game state is created here.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scale the logo with the screen width so it fits small phones and
    // stays prominent on larger ones.
    final logoSize = (MediaQuery.sizeOf(context).width * 0.4).clamp(
      140.0,
      200.0,
    );

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/turtle_king_emblem.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                    semanticLabel: 'Turtle King logo',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Turtle King',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _openHowToPlay(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                      textStyle: theme.textTheme.titleMedium,
                    ),
                    child: const Text('How to Play'),
                  ),
                ],
              ),
            ),
            // Settings entry, kept out of the way of the branding column.
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => _openSettings(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Entry point for starting a game: opens player setup.
  void _startNewGame(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PlayerSetupScreen()));
  }

  /// Opens the rules screen. Purely informational: no game state is
  /// created or mutated.
  void _openHowToPlay(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen()));
  }

  /// Opens the personalization screen. Pure presentation: no game state is
  /// created or mutated.
  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }
}
