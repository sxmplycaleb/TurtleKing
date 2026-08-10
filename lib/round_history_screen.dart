import 'package:flutter/material.dart';

import 'game_state.dart';
import 'player.dart';

/// Read-only, chronological summary of every completed round.
///
/// Pure presentation over data [GameState] already records: [GameState.roundResults]
/// for drinks / YAMADA calls / smallest hands / cup size and
/// [GameState.eliminationHistory] for eliminations. There is no second
/// history store, no gameplay mutation, and no card identity is ever shown —
/// only player names and counts.
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
                    isLatest: index == results.length - 1,
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

/// One completed round: its number, cup size, round type, every player's
/// drinks and YAMADA calls for that round, the smallest-hand penalty, and
/// anyone eliminated during it. The latest round is highlighted.
class _RoundCard extends StatelessWidget {
  const _RoundCard({
    required this.roundNumber,
    required this.result,
    required this.players,
    required this.isLatest,
    required this.eliminatedThisRound,
  });

  final int roundNumber;
  final RoundResult result;
  final List<Player> players;

  /// Whether this is the most recently completed round.
  final bool isLatest;

  final List<EliminationRecord> eliminatedThisRound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final yamadaRound = result.calledYamada.values.any((called) => called);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: isLatest
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Round $roundNumber — ${result.cupSize.label} cup',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _TypeChip(yamadaRound: yamadaRound),
              if (isLatest) _LatestChip(),
            ],
          ),
          const SizedBox(height: 8),
          for (final player in players) ...[
            Text(
              '${player.name}: ${result.drinks[player] ?? 0} drink(s)'
              '${result.calledYamada[player] ?? false ? ' · YAMADA' : ''}'
              '${result.smallestHands.contains(player) ? ' · smallest hand' : ''}',
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

/// A small pill that says whether the round ended via YAMADA or a
/// simultaneous reveal, so the two round types are distinguishable at a
/// glance.
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.yamadaRound});

  final bool yamadaRound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = yamadaRound
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        yamadaRound ? 'YAMADA round' : 'Hold-out reveal',
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Marks the most recently completed round.
class _LatestChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Latest',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
