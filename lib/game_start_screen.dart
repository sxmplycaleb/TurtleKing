import 'package:flutter/material.dart' hide Card;

import 'card.dart';
import 'game_state.dart';
import 'how_to_play_screen.dart';
import 'player.dart';
import 'round_history_screen.dart';

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

/// The pass-and-play game flow, implementing the authoritative rules:
///
/// 1. Each player privately looks at exactly one of their two cards.
/// 2. Pouring begins: in turn, each player holds out or shouts YAMADA
///    (admit defeat: drink the cup, get new cards, continue).
/// 3. If everyone holds out, all hands are revealed together; the smallest
///    hand drinks a full cup plus an extra cup.
/// 4. Rounds repeat with a growing cup until one player remains — the
///    Turtle King.
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
  pourTurn,
  yamadaResult,
  roundComplete,
  gameOver,
}

class _GameStartScreenState extends State<GameStartScreen> {
  /// Whether the neutral handoff screen is showing for the next player.
  bool _showingHandoff = false;

  /// Whether the YAMADA drink result is being shown to the caller.
  bool _showingYamadaResult = false;

  /// The player who just called YAMADA (drinking the cup).
  Player? _yamadaPlayer;

  GameState get _game => widget.game;

  _Stage get _stage {
    // A YAMADA drink result (including one that eliminates the caller and
    // ends the game) is always shown before the game-over screen, so the
    // caller learns why the game ended.
    if (_showingYamadaResult) return _Stage.yamadaResult;
    if (_game.gameComplete) return _Stage.gameOver;
    if (_game.roundComplete) return _Stage.roundComplete;
    if (_showingHandoff) return _Stage.handoff;
    if (_game.pouringStarted) return _Stage.pourTurn;
    if (_game.allPlayersViewed) return _Stage.handoff;
    if (_game.currentPlayerRevealed) return _Stage.revealed;
    return _Stage.ready;
  }

  void _reveal() {
    setState(() => _game.revealCurrentPlayer());
  }

  void _pass() {
    setState(() {
      _game.passToNextPlayer();
      // After the final viewer, pouring begins: hand the phone to player 1.
      _showingHandoff = true;
    });
  }

  void _continue() {
    setState(() => _showingHandoff = false);
  }

  void _yamada() {
    setState(() {
      final player = _game.pourCurrentPlayer;
      _game.callYamada(player);
      _yamadaPlayer = player;
      _showingYamadaResult = true;
      _showingHandoff = false;
    });
  }

  void _holdOut() {
    setState(() {
      _game.holdOut(_game.pourCurrentPlayer);
      _showingYamadaResult = false;
      _showingHandoff = !_game.roundComplete && !_game.gameComplete;
    });
  }

  void _yamadaContinue() {
    setState(() {
      final player = _yamadaPlayer;
      _showingYamadaResult = false;
      // If the caller was eliminated, the phone passes to the next player;
      // their card must stay hidden until they continue.
      if (player != null && _game.isEliminated(player) && !_game.gameComplete) {
        _showingHandoff = true;
      }
    });
  }

  void _startNextRound() {
    setState(() {
      _game.startNextRound();
      _showingHandoff = false;
      _showingYamadaResult = false;
    });
  }

  /// Opens the shared rules screen. Pure presentation: the game state is
  /// untouched and returning lands on the exact same stage.
  void _openHowToPlay() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen()));
  }

  /// Opens the read-only round history for the current game.
  void _openRoundHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RoundHistoryScreen(game: _game)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Turtle King'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'How to Play',
            onPressed: _openHowToPlay,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_game.roundNumber > 0 && !_game.gameComplete) ...[
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
                  _Stage.pourTurn => _pourTurnView(context),
                  _Stage.yamadaResult => _yamadaResultView(context),
                  _Stage.roundComplete => _roundCompleteView(context),
                  _Stage.gameOver => _gameOverView(context),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerHeader(BuildContext context, Player player) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Player ${_game.currentPlayerIndex + 1} of ${_game.currentPlayerCount}',
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

  Widget _backToSetup(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Back to setup'),
    );
  }

  Widget _readyView(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _playerHeader(context, _game.currentPlayer),
        const SizedBox(height: 24),
        Text(
          'You have two cards, but you may only look at ONE of them. View '
          'it privately — do not show anyone else.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _reveal,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Reveal My Card'),
        ),
        const SizedBox(height: 8),
        _backToSetup(context),
      ],
    );
  }

  Widget _revealedView(BuildContext context) {
    final theme = Theme.of(context);
    final card = _game.visibleCardOf(_game.currentPlayer);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _playerHeader(context, _game.currentPlayer),
        const SizedBox(height: 16),
        Text(
          'This is the only card you may look at. Memorize it, then pass '
          'the phone to the next player.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        CardFace(card: card),
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
    final next = _game.pouringStarted
        ? _game.pourCurrentPlayer
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
          _game.pouringStarted
              ? 'The cup is on the table and water is being poured. Their '
                    'turn begins when they continue.'
              : 'Their card stays hidden until they choose to reveal it.',
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

  Widget _pourTurnView(BuildContext context) {
    final theme = Theme.of(context);
    final player = _game.pourCurrentPlayer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _playerHeader(context, player),
        const SizedBox(height: 16),
        Text(
          'Water is being poured into the ${_game.cupSize.label} cup. If '
          'you feel your other card is too small, shout YAMADA — or hold '
          'out.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Your visible card (private):',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        CardFace(card: _game.visibleCardOf(player)),
        const SizedBox(height: 16),
        Text(
          'Drinks: ${_game.drinksOf(player)} '
          '(${_game.eliminationThreshold} drinks eliminate)',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _yamada,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          child: const Text('YAMADA!'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: _holdOut,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          child: const Text('Hold out'),
        ),
        const SizedBox(height: 8),
        _backToSetup(context),
      ],
    );
  }

  Widget _yamadaResultView(BuildContext context) {
    final theme = Theme.of(context);
    final player = _yamadaPlayer;
    if (player == null) {
      // Only reachable right after a YAMADA call.
      return const SizedBox.shrink();
    }
    final eliminated = _game.isEliminated(player);
    final gameOver = _game.gameComplete;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'YAMADA!',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${player.name} admitted defeat and drank the water in the cup.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Lifetime drinks: ${_game.drinksOf(player)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (eliminated) ...[
          const SizedBox(height: 12),
          Text(
            '${player.name} has been eliminated!',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Text(
            'New cards were dealt. Look at your new visible card, then '
            'continue.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (gameOver) ...[
          const SizedBox(height: 12),
          Text(
            'The game is over!',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _yamadaContinue,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _roundCompleteView(BuildContext context) {
    final theme = Theme.of(context);
    final result = _game.roundResult!;
    final yamadaCalled = result.calledYamada.values.any((called) => called);
    final eliminatedThisRound = _game.eliminationHistory
        .where((record) => record.round == _game.roundNumber)
        .toList();
    final summaryPlayers = yamadaCalled ? _game.players : _game.revealedPlayers;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Round ${_game.roundNumber} complete',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (yamadaCalled)
          Text(
            'YAMADA was called — the round ended without a reveal.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          )
        else
          Text(
            'Everyone held out — all cards are revealed together!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        const SizedBox(height: 16),
        if (!yamadaCalled) ...[
          for (final player in _game.revealedPlayers) ...[
            Text(
              player.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _game.handOf(player).length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  CardFace(card: _game.handOf(player)[i]),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text(
            result.smallestHands.length == 1
                ? 'Smallest hand: '
                      '${result.smallestHands.first.name} — drinks a full '
                      'cup and an extra cup for holding out.'
                : 'Smallest hands: '
                      '${result.smallestHands.map((p) => p.name).join(', ')} '
                      '— each drinks a full cup and an extra cup for holding '
                      'out.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (eliminatedThisRound.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Eliminated: '
            '${eliminatedThisRound.map((record) => record.player.name).join(', ')}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (final player in summaryPlayers) ...[
          Text(
            '${player.name}: ${_game.roundDrinksOf(player)} drink(s) this '
            'round · ${_game.drinksOf(player)} lifetime'
            '${_game.calledYamadaThisRound(player) ? ' · YAMADA' : ''}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
        ],
        if (_game.canStartNextRound) ...[
          const SizedBox(height: 16),
          Text(
            'Next round cup: ${_game.cupSize.label}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _startNextRound,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Start Next Round'),
          ),
        ],
        const SizedBox(height: 8),
        _backToSetup(context),
      ],
    );
  }

  Widget _gameOverView(BuildContext context) {
    final theme = Theme.of(context);
    final result = _game.finalResult!;
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
        if (result.turtleKings.length == 1)
          Text(
            'Turtle King: ${result.turtleKings.first.name}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          )
        else
          Text(
            'No Turtle King — every player was eliminated.',
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
        const SizedBox(height: 8),
        if (result.finalists.isNotEmpty) ...[
          Text(
            'Finalists: ${result.finalists.map((p) => p.name).join(', ')}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
        ],
        if (result.eliminated.isNotEmpty) ...[
          Text(
            'Eliminated: '
            '${result.eliminated.map((p) => p.name).join(', ')}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (final player in _game.players) ...[
          Text(
            '${player.name}: ${result.drinks[player]} drink(s)',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _openRoundHistory,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Round History'),
        ),
        const SizedBox(height: 8),
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
