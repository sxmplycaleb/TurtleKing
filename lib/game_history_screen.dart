import 'package:flutter/material.dart';

import 'game_state.dart';

/// Read-only, chronological replay of the whole game.
///
/// Pure presentation over the data [GameState] already records: the
/// [GameState.events] replay log, [GameState.roundResults], and the final
/// [GameState.finalResult]. It never mutates gameplay state and never shows
/// a card identity — the log records facts (who did what, when, with which
/// cup) but no hidden hands.
class GameHistoryScreen extends StatelessWidget {
  const GameHistoryScreen({super.key, required this.game});

  /// The authoritative game being replayed. Read-only.
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = game.events;
    return Scaffold(
      appBar: AppBar(title: const Text('Game History')),
      body: SafeArea(
        child: events.isEmpty
            ? Center(
                child: Text(
                  'No game events recorded yet.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GameSummary(game: game),
                    const SizedBox(height: 16),
                    Text(
                      'Timeline',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final event in events)
                      _EventRow(event: event, game: game),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The game-level header: players, rounds played, final result (Turtle King,
/// finalists, eliminated) and lifetime drinks. Everything here is aggregate
/// data — no card identities.
class _GameSummary extends StatelessWidget {
  const _GameSummary({required this.game});

  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = game.finalResult;
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
            result == null ? 'Game in progress' : 'Game complete',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: result == null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${game.players.length} players · '
            '${game.completedRounds} round(s) completed',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Players: ${game.players.map((p) => p.name).join(', ')}',
            style: theme.textTheme.bodyMedium,
          ),
          if (result != null) ...[
            const SizedBox(height: 8),
            if (result.turtleKings.isNotEmpty)
              Text(
                'Turtle King: '
                '${result.turtleKings.map((p) => p.name).join(', ')}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            if (result.turtleKings.isEmpty)
              Text(
                'No Turtle King — every player was eliminated.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            if (result.finalists.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Finalists: '
                '${result.finalists.map((p) => p.name).join(', ')}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (result.eliminated.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Eliminated: '
                '${result.eliminated.map((p) => p.name).join(', ')}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
          const SizedBox(height: 8),
          for (final player in game.players)
            Text(
              '${player.name}: ${game.drinksOf(player)} drink(s)',
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}

/// One row of the chronological event timeline. Renders a small icon, a
/// concise description, and (when applicable) the player's name. No card
/// identity is ever rendered.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.game});

  final GameEvent event;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = _describe();
    final names = _names();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 12),
            child: Icon(
              _iconFor(event.type),
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
                children: [
                  if (names != null)
                    TextSpan(
                      text: '$names ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  TextSpan(text: description),
                  if (event.round > 0)
                    TextSpan(
                      text: ' · round ${event.round}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The bold names shown before the description, or null for game-level
  /// events without an actor.
  String? _names() {
    if (event.player != null) return event.player!.name;
    if (event.players.isNotEmpty) {
      return event.players.map((p) => p.name).join(', ');
    }
    return null;
  }

  /// A concise, player-facing description of the event. Deliberately free of
  /// card identities — the log records facts, not hidden hands.
  String _describe() {
    switch (event.type) {
      case GameEventType.gameStarted:
        return 'the game began with ${game.players.length} players';
      case GameEventType.roundStarted:
        return 'started round ${event.round}';
      case GameEventType.cardsDealt:
        return 'were dealt two fresh cards';
      case GameEventType.playerViewed:
        return 'looked at their one visible card';
      case GameEventType.handoff:
        return 'passed the phone';
      case GameEventType.pouringStarted:
        return 'water pouring began';
      case GameEventType.playerHeldOut:
        return 'held out';
      case GameEventType.playerCalledYamada:
        return 'called YAMADA (strategic surrender)';
      case GameEventType.yamadaDrink:
        return 'took 1 shot (wrong YAMADA)';
      case GameEventType.replacementCardsDealt:
        return 'received new cards (legacy)';
      case GameEventType.revealOccurred:
        return 'everyone held out — all hands revealed together';
      case GameEventType.smallestDetermined:
        return 'had the smallest hand(s)';
      case GameEventType.fullCupPenalty:
        return 'took shots (smallest hand)';
      case GameEventType.extraCupPenalty:
        return 'took an extra shot (held out with the smallest hand)';
      case GameEventType.playerEliminated:
        return 'was eliminated (reached the drinking threshold)';
      case GameEventType.cupSizeAdvanced:
        return 'the cup grew to ${event.cupSize?.label ?? 'a larger size'}';
      case GameEventType.roundResult:
        return 'round ${event.round} result recorded';
      case GameEventType.roundCompleted:
        return 'completed round ${event.round}';
      case GameEventType.gameCompleted:
        return 'the game ended';
      case GameEventType.challengeStarted:
        return 'refused to drink — challenge started';
      case GameEventType.challengerSelected:
        return 'was selected as challenger';
      case GameEventType.challengeTypeChosen:
        return 'chose the challenge type';
      case GameEventType.challengeResolved:
        return 'challenge resolved — penalty applied';
      case GameEventType.challengePenalty:
        return 'drank from challenge penalty';
      case GameEventType.refusalDrink:
        return 'drank from refusal (too few for challenge)';
      case GameEventType.dareSelected:
        return 'a Dare card was drawn';
      case GameEventType.dareCompleted:
        return 'completed the Dare';
      case GameEventType.dareRefused:
        return 'refused the Dare';
    }
  }

  IconData _iconFor(GameEventType type) {
    switch (type) {
      case GameEventType.gameStarted:
      case GameEventType.gameCompleted:
        return Icons.flag_outlined;
      case GameEventType.roundStarted:
      case GameEventType.roundCompleted:
      case GameEventType.roundResult:
        return Icons.radio_button_checked_outlined;
      case GameEventType.cardsDealt:
      case GameEventType.replacementCardsDealt:
        return Icons.style_outlined;
      case GameEventType.playerViewed:
        return Icons.visibility_outlined;
      case GameEventType.handoff:
        return Icons.phone_iphone;
      case GameEventType.pouringStarted:
        return Icons.water_drop_outlined;
      case GameEventType.playerHeldOut:
        return Icons.handshake_outlined;
      case GameEventType.playerCalledYamada:
        return Icons.campaign_outlined;
      case GameEventType.yamadaDrink:
      case GameEventType.fullCupPenalty:
      case GameEventType.extraCupPenalty:
        return Icons.local_drink_outlined;
      case GameEventType.revealOccurred:
      case GameEventType.smallestDetermined:
        return Icons.style_outlined;
      case GameEventType.playerEliminated:
        return Icons.person_off_outlined;
      case GameEventType.cupSizeAdvanced:
        return Icons.trending_up;
      case GameEventType.challengeStarted:
      case GameEventType.challengerSelected:
      case GameEventType.challengeTypeChosen:
        return Icons.gavel_outlined;
      case GameEventType.challengeResolved:
      case GameEventType.challengePenalty:
        return Icons.local_drink_outlined;
      case GameEventType.refusalDrink:
        return Icons.block_outlined;
      case GameEventType.dareSelected:
      case GameEventType.dareCompleted:
      case GameEventType.dareRefused:
        return Icons.style_outlined;
    }
  }
}
