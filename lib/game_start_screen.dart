import 'package:flutter/material.dart' hide Card;

import 'card.dart';
import 'game_state.dart';
import 'player.dart';

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

/// The pass-and-play game flow.
///
/// First, each player views their two cards in turn: their cards are hidden
/// until they tap "Reveal My Cards", then "Pass to Next Player" hands the
/// phone over via a neutral handoff screen. After the final player passes,
/// the YAMADA round can begin: the current center card is public, each player
/// in turn either draws onto the center pile or calls YAMADA to capture the
/// center card when its value is between their two cards.
class GameStartScreen extends StatefulWidget {
  const GameStartScreen({super.key, required this.game});

  /// The dealt game state; owns the players, hands, and turn order.
  final GameState game;

  @override
  State<GameStartScreen> createState() => _GameStartScreenState();
}

/// One stage of the flow shown on the game screen.
enum _Stage {
  ready,
  revealed,
  handoff,
  done,
  roundTurn,
  roundPenalty,
  roundComplete,
}

class _GameStartScreenState extends State<GameStartScreen> {
  /// Whether the neutral handoff screen is showing for the next player.
  bool _showingHandoff = false;

  /// Whether a wrong YAMADA call is being shown to the penalized player.
  bool _showingPenalty = false;

  /// The player who made the wrong YAMADA call currently on screen.
  Player? _penalizedPlayer;

  GameState get _game => widget.game;

  _Stage get _stage {
    if (_game.roundStarted) {
      if (_game.roundComplete) return _Stage.roundComplete;
      if (_showingPenalty) return _Stage.roundPenalty;
      if (_showingHandoff) return _Stage.handoff;
      return _Stage.roundTurn;
    }
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

  void _startRound() {
    setState(() => _game.startYamadaRound());
  }

  void _roundYamada() {
    setState(() {
      final player = _game.roundCurrentPlayer;
      final result = _game.callYamada(player);
      _penalizedPlayer = result.penalized ? player : null;
      _showingPenalty = result.penalized && !_game.roundComplete;
      _showingHandoff = !_game.roundComplete && !_showingPenalty;
    });
  }

  void _penaltyPass() {
    setState(() {
      _showingPenalty = false;
      _showingHandoff = true;
    });
  }

  void _roundDraw() {
    setState(() {
      _game.drawToCenter(_game.roundCurrentPlayer);
      _showingHandoff = !_game.roundComplete;
    });
  }

  void _startNextRound() {
    setState(() {
      _game.startNextRound();
      _showingHandoff = false;
      _showingPenalty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turtle King')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_game.roundNumber > 0) ...[
                  Text(
                    'Round ${_game.roundNumber}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                switch (_stage) {
                  _Stage.ready => _readyView(context),
                  _Stage.revealed => _revealedView(context),
                  _Stage.handoff => _handoffView(context),
                  _Stage.done => _doneView(context),
                  _Stage.roundTurn => _roundTurnView(context),
                  _Stage.roundPenalty => _penaltyView(context),
                  _Stage.roundComplete => _roundCompleteView(context),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerHeader(BuildContext context, int index, Player player) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Player ${index + 1} of ${_game.players.length}',
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
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
        _playerHeader(context, _game.currentPlayerIndex, _game.currentPlayer),
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
        _playerHeader(context, _game.currentPlayerIndex, _game.currentPlayer),
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
    final next = _game.roundStarted
        ? _game.roundCurrentPlayer
        : _game.currentPlayer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pass the phone',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Hand the phone to ${next.name}.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          _game.roundStarted
              ? 'Their turn begins when they continue.'
              : 'Their cards stay hidden until they choose to reveal them.',
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
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
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
          onPressed: _startRound,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Start YAMADA Round'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to setup'),
        ),
      ],
    );
  }

  Widget _roundTurnView(BuildContext context) {
    final theme = Theme.of(context);
    final player = _game.roundCurrentPlayer;
    final center = _game.currentCenterCard;
    final cards = _game.handOf(player);
    final captureHint = _game.canCallYamada
        ? 'The center card is between your cards — YAMADA will capture it.'
        : 'The center card is not between your cards — YAMADA would cost '
              'you a penalty.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _playerHeader(context, _game.roundPlayerIndex, player),
        const SizedBox(height: 16),
        Text(
          'Compare the center card with your two cards.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (center != null) CardFace(card: center),
        const SizedBox(height: 24),
        Text(
          'Your two cards',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              CardFace(card: cards[i]),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Text(
          captureHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your cup: ${_game.cupFillOf(player)}/${_game.cupCapacity}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _roundYamada,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          child: const Text('YAMADA!'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: _game.remainingCards > 0 ? _roundDraw : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          child: const Text('Draw to center'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to setup'),
        ),
      ],
    );
  }

  Widget _penaltyView(BuildContext context) {
    final theme = Theme.of(context);
    final player = _penalizedPlayer;
    if (player == null) {
      // The penalty stage is only reachable right after a wrong call.
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Wrong YAMADA call',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${player.name} called YAMADA, but the center card is not between '
          'their two cards.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Nothing was captured. A penalty was added to ${player.name}\'s '
          'cup: ${_game.cupFillOf(player)}/${_game.cupCapacity}.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _penaltyPass,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Pass the phone'),
        ),
      ],
    );
  }

  Widget _roundCompleteView(BuildContext context) {
    if (_game.gameComplete) {
      return _gameOverView(context);
    }
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'YAMADA round complete',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Every player has taken their turn. Cards captured:',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final player in _game.players) ...[
          Text(
            '${player.name}: ${_game.captureCountOf(player)} captured · '
            '${_game.penaltyCountOf(player)} penalty',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _game.canStartNextRound ? _startNextRound : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Start Next Round'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to setup'),
        ),
      ],
    );
  }

  Widget _gameOverView(BuildContext context) {
    final theme = Theme.of(context);
    final result = _game.finalResult!;
    final kings = result.turtleKings.map((player) => player.name).join(', ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Game complete',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          result.turtleKings.length == 1
              ? 'Turtle King: $kings'
              : 'Turtle Kings: $kings',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Rounds played: ${result.roundsPlayed}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final player in _game.players) ...[
          Text(
            '${player.name}: ${result.scores[player]} captured · '
            '${_game.penaltyCountOf(player)} penalty',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 24),
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
