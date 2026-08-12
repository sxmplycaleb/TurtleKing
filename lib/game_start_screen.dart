import 'package:flutter/material.dart' hide Card;

import 'card_widgets.dart';
import 'feedback.dart';
import 'game_history_screen.dart';
import 'game_save.dart';
import 'game_state.dart';
import 'game_table.dart';
import 'how_to_play_screen.dart';
import 'multiplayer/driver.dart';
import 'player.dart';
import 'round_history_screen.dart';
import 'theme.dart';

export 'card_widgets.dart' show CardFace;

/// The pass-and-play game flow, implementing the authoritative rules:
///
/// 1. Each player privately looks at exactly one of their two cards.
/// 2. Pouring begins: in turn, each player holds out or shouts YAMADA
///    (admit defeat: drink the cup, get new cards, continue).
/// 3. If everyone holds out, all hands are revealed together; the smallest
///    hand drinks a full cup plus an extra cup.
/// 4. Rounds repeat with a growing cup until one player remains — the
///    Turtle King.
///
/// All game logic lives in [GameState]; this screen is presentation only.
class GameStartScreen extends StatefulWidget {
  const GameStartScreen({super.key, required this.driver, this.saveStore});

  /// The gameplay driver: gameplay actions are routed through this
  /// abstraction rather than touching a transport directly. Pass-and-play
  /// uses [LocalDriver] wrapping the dealt game state; a future networked
  /// driver sends action requests and renders broadcast state.
  final GameDriver driver;

  /// Optional save store. When present the game is persisted automatically
  /// after every action and cleared when the game completes, so the player
  /// can always resume from the last safe boundary. Null disables
  /// persistence (tests, previews).
  final GameSaveStore? saveStore;

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

  /// The authoritative state behind the driver (read-only from the UI's
  /// perspective; actions go through the driver).
  GameState get _game => widget.driver.state;

  @override
  void initState() {
    super.initState();
    // Persist as soon as the game exists so a freshly started game is always
    // resumable, even before the first action.
    _persistGame();
    // Preload every bundled sound before the first gameplay action can fire
    // feedback, so the first sound has no load latency.
    _preloadFeedback();
  }

  /// Preloads audio before gameplay can trigger feedback. Guarded: a missing
  /// scope or failing audio must never prevent the game from starting.
  void _preloadFeedback() {
    try {
      GameFeedbackScope.of(context).preload();
    } catch (_) {
      // Audio preloading is an optional UX enhancement: never interrupt.
    }
  }

  /// Plays feedback for [event], guarding gameplay from any feedback failure.
  void _playFeedback(FeedbackEvent event) {
    try {
      GameFeedbackScope.of(context).play(event);
    } catch (_) {
      // Feedback is an optional UX enhancement: never interrupt gameplay.
    }
  }

  /// Persists the game after every action; clears the save once the game
  /// completes so a finished game is never offered as resumable.
  void _persistGame() {
    final store = widget.saveStore;
    if (store == null) return;
    if (_game.gameComplete) {
      store.clear();
    } else {
      store.save(_game);
    }
  }

  /// Saves the in-progress game (if any) and returns to the home screen.
  void _saveAndExit() {
    _persistGame();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

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
    setState(() => widget.driver.revealCurrentPlayer());
    _persistGame();
    _playFeedback(FeedbackEvent.cardReveal);
  }

  void _pass() {
    setState(() {
      widget.driver.passToNextPlayer();
      // After the final viewer, pouring begins: hand the phone to player 1.
      _showingHandoff = true;
    });
    _persistGame();
    _playFeedback(FeedbackEvent.handoffPass);
  }

  void _continue() {
    setState(() => _showingHandoff = false);
  }

  void _yamada() {
    final eliminationsBefore = _game.eliminationHistory.length;
    setState(() {
      final player = _game.pourCurrentPlayer;
      widget.driver.callYamada(player);
      _yamadaPlayer = player;
      _showingYamadaResult = true;
      _showingHandoff = false;
    });
    _persistGame();
    _playFeedback(FeedbackEvent.yamada);
    if (_game.eliminationHistory.length > eliminationsBefore) {
      _playFeedback(FeedbackEvent.elimination);
    }
    if (_game.gameComplete) {
      _playFeedback(FeedbackEvent.victory);
    }
  }

  void _holdOut() {
    final eliminationsBefore = _game.eliminationHistory.length;
    setState(() {
      widget.driver.holdOut(_game.pourCurrentPlayer);
      _showingYamadaResult = false;
      _showingHandoff = !_game.roundComplete && !_game.gameComplete;
    });
    _persistGame();
    _playFeedback(FeedbackEvent.holdOut);
    if (_game.roundComplete && !_game.gameComplete) {
      // The round ended by a simultaneous reveal (everyone held out).
      final yamadaCalled = _game.roundResult!.calledYamada.values.any(
        (called) => called,
      );
      if (!yamadaCalled) {
        _playFeedback(FeedbackEvent.roundReveal);
      }
    }
    if (_game.eliminationHistory.length > eliminationsBefore) {
      _playFeedback(FeedbackEvent.elimination);
    }
    if (_game.gameComplete) {
      _playFeedback(FeedbackEvent.victory);
    }
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
      widget.driver.startNextRound();
      _showingHandoff = false;
      _showingYamadaResult = false;
    });
    _persistGame();
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

  /// Opens the read-only game history (chronological replay) for the current
  /// game. Pure presentation: the game state is untouched.
  void _openGameHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GameHistoryScreen(game: _game)),
    );
  }

  // ---------------------------------------------------------------------
  // Shared visual helpers
  // ---------------------------------------------------------------------

  /// Label style for the accent primary buttons (contrasting text on the
  /// accent).
  TextStyle _goldButtonLabelStyle(BuildContext context) {
    final style = GameTableStyle.of(context);
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: style.onAccent,
    );
  }

  ButtonStyle _goldButtonStyle(BuildContext context) {
    final style = GameTableStyle.of(context);
    return FilledButton.styleFrom(
      backgroundColor: style.accent,
      foregroundColor: style.onAccent,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    );
  }

  /// The current round as a branded pill (exact "Round N" text).
  Widget _roundBadge(BuildContext context) {
    final style = GameTableStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: style.chipBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.chipBorder),
      ),
      child: Text(
        'Round ${_game.roundNumber}',
        style: TextStyle(
          color: style.accentText,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  /// The active player's avatar: an accent ring around their color disc.
  Widget _turnAvatar(BuildContext context, Player player) {
    final style = GameTableStyle.of(context);
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [style.accentSoft, style.accent]),
      ),
      child: CircleAvatar(radius: 18, backgroundColor: player.color),
    );
  }

  /// "Player X of Y" pill plus the player's name and turn indicator.
  Widget _playerHeader(BuildContext context, Player player) {
    final theme = Theme.of(context);
    final style = GameTableStyle.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: style.chipBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Player ${_game.currentPlayerIndex + 1} of ${_game.currentPlayerCount}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: style.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _turnAvatar(context, player),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                player.name,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: style.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Current-turn indicator (a colored dot + label).
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF81C784),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Your turn',
              style: theme.textTheme.bodySmall?.copyWith(
                color: style.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _backToSetup(BuildContext context) {
    final style = GameTableStyle.of(context);
    return TextButton(
      onPressed: () => Navigator.of(context).pop(),
      style: TextButton.styleFrom(foregroundColor: style.textSecondary),
      child: const Text('Back to setup'),
    );
  }

  /// A small glass label pill, e.g. the drinks counter.
  Widget _infoChip(BuildContext context, Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: GameTableStyle.of(context).chipBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = GameTableStyle.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: style.feltBottom,
      appBar: AppBar(
        title: Text(
          'Turtle King',
          style: TextStyle(
            color: style.accentText,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: style.textPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'How to Play',
            onPressed: _openHowToPlay,
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save & Exit',
            onPressed: _saveAndExit,
          ),
        ],
      ),
      body: Stack(
        children: [
          const GameTableBackground(),
          SafeArea(
            minimum: const EdgeInsets.only(top: kToolbarHeight + 4),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_game.roundNumber > 0 && !_game.gameComplete) ...[
                      _roundBadge(context),
                      const SizedBox(height: 14),
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
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Stage views
  // ---------------------------------------------------------------------

  Widget _readyView(BuildContext context) {
    final theme = Theme.of(context);
    final style = GameTableStyle.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _playerHeader(context, _game.currentPlayer),
        const SizedBox(height: 24),
        // Both cards are dealt but hidden: card backs carry no identity.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [CardBack(), SizedBox(width: 14), CardBack()],
        ),
        const SizedBox(height: 20),
        Text(
          'You have two cards, but you may only look at ONE of them. View '
          'it privately — do not show anyone else.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: style.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _reveal,
          style: _goldButtonStyle(context),
          child: Text('Reveal My Card', style: _goldButtonLabelStyle(context)),
        ),
        const SizedBox(height: 8),
        _backToSetup(context),
      ],
    );
  }

  Widget _revealedView(BuildContext context) {
    final theme = Theme.of(context);
    final style = GameTableStyle.of(context);
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
          style: theme.textTheme.bodyMedium?.copyWith(
            color: style.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        // The one visible card face-up; the second card stays face-down.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CardFace(card: card),
            const SizedBox(width: 14),
            const CardBack(),
          ],
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _pass,
          style: _goldButtonStyle(context),
          child: Text(
            'Pass to Next Player',
            style: _goldButtonLabelStyle(context),
          ),
        ),
      ],
    );
  }

  Widget _handoffView(BuildContext context) {
    final theme = Theme.of(context);
    final style = GameTableStyle.of(context);
    final next = _game.pouringStarted
        ? _game.pourCurrentPlayer
        : _game.currentPlayer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: style.chipBg,
            border: Border.all(color: style.accent),
          ),
          child: Icon(Icons.phone_iphone, color: style.textPrimary, size: 34),
        ),
        const SizedBox(height: 16),
        Text(
          'Pass the phone',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: style.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Hand the phone to ${next.name}.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: style.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          _game.pouringStarted
              ? 'The cup is on the table and water is being poured. Their '
                    'turn begins when they continue.'
              : 'Their card stays hidden until they choose to reveal it.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: style.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _continue,
          style: _goldButtonStyle(context),
          child: Text('Continue', style: _goldButtonLabelStyle(context)),
        ),
      ],
    );
  }

  Widget _pourTurnView(BuildContext context) {
    final theme = Theme.of(context);
    final style = GameTableStyle.of(context);
    final player = _game.pourCurrentPlayer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _playerHeader(context, player),
        const SizedBox(height: 12),
        // The cup, drawn at its authoritative size (normal/large/extra).
        TurtleKingCup(size: _game.cupSize, diameter: 54),
        const SizedBox(height: 8),
        Text(
          'Water is being poured into the ${_game.cupSize.label} cup. If '
          'you feel your other card is too small, shout YAMADA — or hold '
          'out.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: style.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your visible card (private):',
          style: theme.textTheme.titleSmall?.copyWith(
            color: style.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CardFace(card: _game.visibleCardOf(player)),
            const SizedBox(width: 14),
            const CardBack(),
          ],
        ),
        const SizedBox(height: 14),
        _infoChip(
          context,
          Text(
            'Drinks: ${_game.drinksOf(player)} '
            '(${_game.eliminationThreshold} drinks eliminate)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: style.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        // YAMADA is the loud, prominent admit-defeat action.
        FilledButton(
          onPressed: _yamada,
          style: FilledButton.styleFrom(
            backgroundColor: style.danger,
            foregroundColor: style.onDanger,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'YAMADA!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: style.onDanger,
                ),
              ),
              Text(
                'Admit defeat — drink the cup',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: style.onDanger.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: _holdOut,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Hold out', style: TextStyle(fontSize: 16)),
              Text(
                'Keep your cards',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _backToSetup(context),
      ],
    );
  }

  Widget _yamadaResultView(BuildContext context) {
    final theme = Theme.of(context);
    final style = GameTableStyle.of(context);
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
        TurtleKingCup(size: _game.cupSize, diameter: 54),
        const SizedBox(height: 6),
        Text(
          'YAMADA!',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: style.accentText,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${player.name} admitted defeat and drank the water in the cup.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: style.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Lifetime drinks: ${_game.drinksOf(player)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: style.textPrimary),
        ),
        if (eliminated) ...[
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: style.danger,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'ELIMINATED',
                style: TextStyle(
                  color: style.onDanger,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${player.name} has been eliminated!',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: style.danger,
              fontWeight: FontWeight.bold,
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Text(
            'New cards were dealt. Look at your new visible card, then '
            'continue.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.textPrimary,
              height: 1.4,
            ),
          ),
        ],
        if (gameOver) ...[
          const SizedBox(height: 12),
          Text(
            'The game is over!',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: style.danger,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _yamadaContinue,
          style: _goldButtonStyle(context),
          child: Text('Continue', style: _goldButtonLabelStyle(context)),
        ),
      ],
    );
  }

  Widget _roundCompleteView(BuildContext context) {
    final theme = Theme.of(context);
    final style = GameTableStyle.of(context);
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
            color: style.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (yamadaCalled)
          Text(
            'YAMADA was called — the round ended without a reveal.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.textSecondary,
            ),
          )
        else
          Text(
            'Everyone held out — all cards are revealed together!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.textSecondary,
            ),
          ),
        if (!yamadaCalled) ...[
          const SizedBox(height: 16),
          // One-shot entrance for the group reveal (short, settles).
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
            ),
            child: Column(
              children: [
                for (final player in _game.revealedPlayers) ...[
                  Text(
                    player.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: style.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Wrap so many revealed hands never overflow the screen.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < _game.handOf(player).length; i++)
                        CardFace(
                          card: _game.handOf(player)[i],
                          highlighted: result.smallestHands.contains(player),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
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
              color: style.accentTextSoft,
              fontWeight: FontWeight.w600,
              height: 1.4,
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
              color: style.danger,
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (_game.canStartNextRound) ...[
          const SizedBox(height: 16),
          Text(
            'Next round cup: ${_game.cupSize.label}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.accentText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _startNextRound,
            style: _goldButtonStyle(context),
            child: Text(
              'Start Next Round',
              style: _goldButtonLabelStyle(context),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _backToSetup(context),
      ],
    );
  }

  Widget _gameOverView(BuildContext context) {
    final theme = Theme.of(context);
    final style = GameTableStyle.of(context);
    final result = _game.finalResult!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TurtleKingCrown(size: 84),
        const SizedBox(height: 8),
        Text(
          'Game complete',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: style.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (result.turtleKings.length == 1)
          Text(
            'Turtle King: ${result.turtleKings.first.name}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: style.accentText,
              fontWeight: FontWeight.bold,
            ),
          )
        else
          Text(
            'No Turtle King — every player was eliminated.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: style.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Rounds played: ${result.roundsPlayed}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: style.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (result.finalists.isNotEmpty) ...[
          Text(
            'Finalists: ${result.finalists.map((p) => p.name).join(', ')}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (result.eliminated.isNotEmpty) ...[
          Text(
            'Eliminated: '
            '${result.eliminated.map((p) => p.name).join(', ')}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: style.danger),
          ),
        ],
        const SizedBox(height: 16),
        for (final player in _game.players) ...[
          Text(
            '${player.name}: ${result.drinks[player]} drink(s)',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: _game.isEliminated(player)
                  ? style.textSecondary
                  : style.textPrimary,
              decoration: _game.isEliminated(player)
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _openRoundHistory,
          style: OutlinedButton.styleFrom(
            foregroundColor: style.accentText,
            side: BorderSide(color: style.accentText),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Round History'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _openGameHistory,
          style: OutlinedButton.styleFrom(
            foregroundColor: style.accentText,
            side: BorderSide(color: style.accentText),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Game History'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: _goldButtonStyle(context),
          child: Text('Back to setup', style: _goldButtonLabelStyle(context)),
        ),
      ],
    );
  }
}
