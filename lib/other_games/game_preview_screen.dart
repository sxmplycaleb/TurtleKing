import 'package:flutter/material.dart';

import 'game_catalog.dart';

/// Preview/detail screen for a game in the catalog.
///
/// Shows the game's artwork, name, description, and status. For Coming Soon
/// games, displays a clear "not available yet" message with no play/join
/// button.
class GamePreviewScreen extends StatelessWidget {
  const GamePreviewScreen({super.key, required this.game});

  final GameEntry game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(game.name)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Game artwork
              Center(
                child: Image.asset(
                  game.artworkAsset,
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                  semanticLabel: '${game.name} artwork',
                ),
              ),
              const SizedBox(height: 24),

              // Game name
              Center(
                child: Text(
                  game.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),

              // Status badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    game.status == GameStatus.comingSoon
                        ? 'COMING SOON'
                        : 'AVAILABLE',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Description
              Text(
                game.description,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),

              // Detailed description (if present)
              if (game.detailedDescription != null) ...[
                const SizedBox(height: 24),
                Text(
                  'How it works',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  game.detailedDescription!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],

              // Coming Soon message
              if (!game.isAvailable) ...[
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 32,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This game isn\'t available yet.\nCheck back soon.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
