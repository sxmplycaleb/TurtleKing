import 'package:flutter/material.dart';

import 'game_state.dart';
import 'player.dart';

/// Read-only, chronological summary of every completed round.
///
/// Pure presentation over data [GameState] already records: [GameState.roundResults]
/// for captures and per-round penalties and [GameState.eliminationHistory] for
/// eliminations. There is no second history store, no gameplay mutation, and
/// no card identity is ever shown — only player names, capture counts,
/// penalty counts, and eliminations.
class RoundHistoryScreen extends StatelessWidget {
  const RoundHistoryScreen({super.key, required this.game});

  /// The authoritative game being summarized. Read-only.
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = game.roundResults;
    return Scaffold(
      appBar: AppBar(title: const Text('Round History')),
      body: SafeArea(
        child: results.isEmpty
            ? Center(
                child: Text(
                  'No completed rounds yet.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: results.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final roundNumber = index + 1;
                  return _RoundCard(
                    roundNumber: roundNumber,
                    result: results[index],
                    players: game.players,
                    eliminatedThisRound: game.eliminationHistory
                        .where((record) => record.round == roundNumber)
                        .toList(),
                  );
                },
              ),
      ),
    );
  }
}

/// One completed round: its number, every player's capture and penalty
/// counts for that round, and anyone eliminated during it.
class _RoundCard extends StatelessWidget {
  const _RoundCard({
    required this.roundNumber,
    required this.result,
    required this.players,
    required this.eliminatedThisRound,
  });

  final int roundNumber;
  final RoundResult result;
  final List<Player> players;
  final List<EliminationRecord> eliminatedThisRound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Round $roundNumber',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          for (final player in players) ...[
            Text(
              '${player.name}: ${result.scores[player] ?? 0} captured · '
              '${result.penalties[player] ?? 0} penalty',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
          ],
          if (eliminatedThisRound.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Eliminated: '
              '${eliminatedThisRound.map((record) => record.player.name).join(', ')}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
