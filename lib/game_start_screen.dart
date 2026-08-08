import 'package:flutter/material.dart' hide Card;

import 'card.dart';
import 'game_state.dart';

/// A face-up view of a single [Card], sized for a phone screen.
class CardFace extends StatelessWidget {
  const CardFace({super.key, required this.card});

  final Card card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRed = card.suit == Suit.hearts || card.suit == Suit.diamonds;

    return Container(
      width: 116,
      height: 162,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Center(
        child: Text(
          card.displayName,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: isRed
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The pass-and-play game flow for the initial dealing phase.
///
/// For each player in turn: their cards are hidden until they tap
/// "Reveal My Cards", then "Pass to Next Player" hands the phone over via a
/// neutral handoff screen. The next player's cards stay hidden until they
/// explicitly reveal them. After the final player passes, a completion
/// screen confirms the phase is over.
class GameStartScreen extends StatefulWidget {
  const GameStartScreen({super.key, required this.game});

  /// The dealt game state; owns the players, hands, and turn order.
  final GameState game;

  @override
  State<GameStartScreen> createState() => _GameStartScreenState();
}

/// One stage of the pass-and-play flow shown on the game screen.
enum _Stage { ready, revealed, handoff, done }

class _GameStartScreenState extends State<GameStartScreen> {
  /// Whether the neutral handoff screen is showing for the next player.
  bool _showingHandoff = false;

  GameState get _game => widget.game;

  _Stage get _stage {
    if (_game.allPlayersViewed) return _Stage.done;
    if (_showingHandoff) return _Stage.handoff;
    if (_game.currentPlayerRevealed) return _Stage.revealed;
    return _Stage.ready;
  }

  void _reveal() {
    setState(() => _game.revealCurrentPlayer());
  }

  void _pass() {
    setState(() {
      _game.passToNextPlayer();
      _showingHandoff = !_game.allPlayersViewed;
    });
  }

  void _continue() {
    setState(() => _showingHandoff = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turtle King')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: switch (_stage) {
              _Stage.ready => _readyView(context),
              _Stage.revealed => _revealedView(context),
              _Stage.handoff => _handoffView(context),
              _Stage.done => _doneView(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _playerHeader(BuildContext context) {
    final theme = Theme.of(context);
    final player = _game.currentPlayer;
    return Column(
      children: [
        Text(
          'Player ${_game.currentPlayerIndex + 1} of ${_game.players.length}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(radius: 12, backgroundColor: player.color),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                player.name,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _readyView(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _playerHeader(context),
        const SizedBox(height: 24),
        Text(
          'It is your turn to view your two cards. View them privately — '
          'do not show anyone else.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _reveal,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Reveal My Cards'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to setup'),
        ),
      ],
    );
  }

  Widget _revealedView(BuildContext context) {
    final theme = Theme.of(context);
    final cards = _game.handOf(_game.currentPlayer);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _playerHeader(context),
        const SizedBox(height: 16),
        Text(
          'Memorize your two cards, then pass the phone to the next player.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              CardFace(card: cards[i]),
            ],
          ],
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _pass,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          child: const Text('Pass to Next Player'),
        ),
      ],
    );
  }

  Widget _handoffView(BuildContext context) {
    final theme = Theme.of(context);
    final next = _game.currentPlayer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pass the phone',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          'Hand the phone to ${next.name}.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Their cards stay hidden until they choose to reveal them.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _continue,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _doneView(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'All players ready',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          'The initial dealing phase is complete. Everyone has viewed '
          'their two cards.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Back to setup'),
        ),
      ],
    );
  }
}
