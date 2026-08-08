import 'package:flutter/material.dart';

import 'player.dart';

/// Placeholder shown once player setup is complete.
///
/// Exists only to verify that player setup hands off to the game flow with
/// the configured players intact. Cards and gameplay arrive in a later
/// milestone; "Back to setup" is a temporary way to return and re-configure.
class GameStartScreen extends StatelessWidget {
  const GameStartScreen({super.key, required this.players});

  /// The players configured on the setup screen, in setup order.
  final List<Player> players;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Turtle King',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Game ready', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Players: ${players.length}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                ...players.map(
                  (player) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(radius: 10, backgroundColor: player.color),
                        const SizedBox(width: 8),
                        Text(player.name, style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Back to setup'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
