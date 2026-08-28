import 'dart:math';

import 'challenge/challenge_engine.dart';
import 'challenge/challenge_state.dart';
import 'challenge/dare_card.dart';
import 'challenge/dare_deck.dart';
import 'challenge/rps_state.dart';
import 'challenge/trivia_card.dart';
import 'challenge/trivia_deck.dart';
import 'challenge/trivia_state.dart';
import 'card.dart';
import 'deck.dart';
import 'player.dart';

// The restore factory deliberately maps public named parameters onto private
// fields (so the save layer passes readable names like `viewIndex`), which
// the initializing-formal lint cannot express. The lint is not applicable
// to that constructor.
// ignore_for_file: prefer_initializing_formals

/// Thrown when a Turtle King game action is attempted illegally.
///
/// A rejected action never mutates the game state.
class YamadaRoundException implements Exception {
  const YamadaRoundException(this.message);

  /// Why the action was rejected.
  final String message;

  @override
  String toString() => 'YamadaRoundException: $message';
}

/// The size of the water cup used in a round.
///
/// The cup starts [normal] and grows one step after every round in which no
/// player calls YAMADA (normal → large → extra-large, capped). A round in
/// which someone calls YAMADA keeps the current size.
enum CupSize {
  normal('normal'),
  large('large'),
  extraLarge('extra-large');

  const CupSize(this.label);

  /// Human-readable name, e.g. "extra-large".
  final String label;
}

/// Deterministic result of one completed round.
///
/// Holds aggregate, non-card data only: who drank and how much, who called
/// YAMADA, whose hand was smallest (the penalty drinkers), and the cup size
/// used. No card identities are recorded, so round history can never leak
/// private cards.
class RoundResult {
  const RoundResult({
    required this.drinks,
    required this.calledYamada,
    required this.smallestHands,
    required this.cupSize,
  });

  /// Drinking events per player during this round, in player order.
  final Map<Player, int> drinks;

  /// Whether each player called YAMADA at least once this round.
  final Map<Player, bool> calledYamada;

  /// The players whose hands were the smallest when the round revealed;
  /// each owed exactly one shot. Ties share the penalty. Empty
  /// when the round ended via a YAMADA call, because no reveal happened.
  final List<Player> smallestHands;

  /// The cup size the round was played with.
  final CupSize cupSize;
}

/// Why a player was eliminated from the game.
enum EliminationReason {
  /// The player accumulated six (threshold) drinking events.
  sixDrinks,
}

/// A record of a single elimination: who, in which round, and at what
/// lifetime drink count.
class EliminationRecord {
  const EliminationRecord({
    required this.player,
    required this.round,
    required this.drinks,
    required this.reason,
  });

  /// The eliminated player.
  final Player player;

  /// The 1-based round in which the elimination happened.
  final int round;

  /// The player's lifetime drinking-event count at elimination.
  final int drinks;

  /// Why the player was eliminated.
  final EliminationReason reason;
}

/// The final, deterministic result of a completed Turtle King game.
///
/// Per the authoritative rules, the Turtle King is the last player remaining
/// on the field. If every remaining player is eliminated by the same event
/// (no last player exists), [turtleKings] is empty and the title is
/// undetermined — the rules do not specify this edge case, so it is exposed
/// explicitly rather than hidden by a tie-breaker.
class GameResult {
  const GameResult({
    required this.drinks,
    required this.turtleKings,
    required this.finalists,
    required this.eliminated,
    required this.eliminations,
    required this.roundsPlayed,
  });

  /// Lifetime drinking events per player, in player order.
  final Map<Player, int> drinks;

  /// The Turtle King(s): the last player(s) remaining. Empty when no player
  /// remains.
  final List<Player> turtleKings;

  /// The players still active when the game ended, in setup order.
  final List<Player> finalists;

  /// Every eliminated player, in elimination order.
  final List<Player> eliminated;

  /// The full elimination history, in elimination order.
  final List<EliminationRecord> eliminations;

  /// The number of rounds actually played.
  final int roundsPlayed;
}

/// The kind of event recorded in the game replay log.
///
/// Events are pure facts about the game — who did what, in which round, and
/// with which cup size — and never carry card identities, so the log can
/// never leak a hidden hand.
enum GameEventType {
  /// The game was created with its starting roster.
  gameStarted,

  /// A new round began (round number in [GameEvent.round]).
  roundStarted,

  /// Fresh two-card hands were dealt to every active player.
  cardsDealt,

  /// A player looked at their one permitted (visible) card.
  playerViewed,

  /// The phone was passed to the next player (neutral handoff).
  handoff,

  /// The water-pouring phase began after everyone viewed their card.
  pouringStarted,

  /// A player held out during the pouring phase.
  playerHeldOut,

  /// A player called YAMADA, admitting defeat.
  playerCalledYamada,

  /// A YAMADA caller drank the water in the cup (legacy).
  yamadaDrink,

  /// A YAMADA caller was dealt two new cards and continues (legacy).
  replacementCardsDealt,

  /// The round completed.
  roundCompleted,

  /// Everyone held out and all hands were revealed together.
  revealOccurred,

  /// The smallest hand(s) were determined after the reveal.
  smallestDetermined,

  /// A smallest-hand player drank one full cup (legacy).
  fullCupPenalty,

  /// A smallest-hand player drank one extra cup for holding out (legacy).
  extraCupPenalty,

  /// A player was eliminated (reached the drinking threshold).
  playerEliminated,

  /// The cup grew one step (normal → large → extra-large).
  cupSizeAdvanced,

  /// The game completed and a final result was produced.
  gameCompleted,

  /// The deterministic result of a completed round was recorded.
  roundResult,

  /// A player refused to drink and a challenge was started.
  challengeStarted,

  /// A random challenger was selected from eligible players.
  challengerSelected,

  /// The challenger chose the challenge type (Dare/RPS/Trivia).
  challengeTypeChosen,

  /// The challenge resolved and a penalty was applied.
  challengeResolved,

  /// A player drank as a result of a challenge penalty.
  challengePenalty,

  /// A player refused to drink (too few others for a challenge).
  refusalDrink,

  /// A Dare card was selected for a challenge.
  dareSelected,

  /// The challenged player completed the Dare.
  dareCompleted,

  /// The challenged player refused or failed the Dare.
  dareRefused,

  /// RPS was started for a challenge.
  rpsStarted,

  /// An RPS round result was recorded.
  rpsRoundRecorded,

  /// RPS resolved with a final penalty.
  rpsResolved,

  /// Trivia was started for a challenge.
  triviaStarted,

  /// The challenged player answered correctly.
  triviaCorrect,

  /// The challenged player answered incorrectly.
  triviaWrong,

  /// Trivia resolved with a final penalty.
  triviaResolved,

  /// A player confirmed they will take the shot (pending decision resolved).
  shotTaken,

  /// A player refused to take the shot (enters challenge flow).
  shotRefused,
}

/// One immutable entry in the game replay log.
///
/// [round] is 1-based for round-scoped events and 0 for game-level events
/// (game start / completion). Optional payloads: the affected [player], the
/// affected [players] (e.g. everyone tied for the smallest hand), the [cupSize]
/// in effect (or the new size after a [GameEventType.cupSizeAdvanced]), and the
/// [result] for a [GameEventType.roundResult] event.
class GameEvent {
  const GameEvent({
    required this.type,
    required this.round,
    this.player,
    this.players = const [],
    this.cupSize,
    this.result,
  });

  /// What happened.
  final GameEventType type;

  /// The 1-based round the event belongs to (0 for game-level events).
  final int round;

  /// The single player the event concerns, when applicable.
  final Player? player;

  /// The players the event concerns, when more than one (ties, deals).
  final List<Player> players;

  /// The cup size in effect, or the new size after a cup-size transition.
  final CupSize? cupSize;

  /// The recorded round result for a [GameEventType.roundResult] event.
  final RoundResult? result;
}

/// The pass-and-play state of a Turtle King game.
///
/// Implements the authoritative rules:
///
/// 1. Each player is dealt two cards but may only look at one of them.
/// 2. After everyone has looked, the water cup is placed and "pouring"
///    begins: players act in turn, each holding out or calling YAMADA.
/// 3. YAMADA is a strategic surrender: after all players act, the caller's
///    hand is revealed. Correct = 0 shots; wrong = pending 1-shot decision.
/// 4. If everyone holds out, all hands are revealed together and the player
///    with the smallest hand owes 1 shot (pending decision: take or refuse).
/// 5. The cup grows (normal → large → extra-large) after every round —
///    visual only, independent of shot count.
/// 6. A player who drinks six times is eliminated on the spot.
/// 7. The last player remaining wins the crown and becomes the Turtle King.
///
/// The deck is the single source of cards. When it cannot deal, it is reset
/// to a fresh 52-card deck (shuffled) so the game can continue indefinitely,
/// as the physical game must.
class GameState {
  GameState({
    required List<Player> players,
    Random? random,
    int eliminationThreshold = 6,
  }) : _players = List.unmodifiable(players),
       _deck = Deck(random: random),
       _eliminationThreshold = eliminationThreshold,
       _lifetimeDrinks = {for (final player in players) player.id: 0},
       _roundDrinks = {},
       _calledYamada = {},
       _roundResults = [],
       _events = [],
       _eliminatedIds = {},
       _eliminations = [] {
    if (_players.length < 2) {
      throw ArgumentError.value(players, 'players', 'need at least 2 players');
    }
    if (_eliminationThreshold < 1) {
      throw ArgumentError.value(
        eliminationThreshold,
        'eliminationThreshold',
        'must be at least 1',
      );
    }
    _deck.shuffle();
    _roundNumber = 1;
    _record(const GameEvent(type: GameEventType.gameStarted, round: 0));
    _record(GameEvent(type: GameEventType.roundStarted, round: _roundNumber));
    _dealHands();
    _record(
      GameEvent(
        type: GameEventType.cardsDealt,
        round: _roundNumber,
        players: List.of(activePlayers),
      ),
    );
    _viewingPlayers = activePlayers;
  }

  /// Restores a game from previously saved state (the save/resume layer).
  GameState.restore({
    required List<Player> players,
    required int eliminationThreshold,
    required Map<String, int> lifetimeDrinks,
    required Map<String, int> roundDrinks,
    required Map<String, bool> calledYamada,
    required List<RoundResult> roundResults,
    required List<GameEvent> events,
    required Set<String> eliminatedIds,
    required List<EliminationRecord> eliminations,
    required Map<String, List<Card>> hands,
    required int viewIndex,
    required bool revealed,
    required bool pouring,
    required int pourIndex,
    required int consecutiveHolds,
    required CupSize cupSize,
    required int roundNumber,
    required bool roundFinalized,
    required List<Player> smallestHands,
    required List<Player> revealedPlayers,
    required bool gameComplete,
    required GameResult? finalResult,
    required List<Card> remainingDeck,
    Player? yamadaCallerThisRound,
    Set<String> playersActedThisRound = const {},
    bool shotDecisionPending = false,
    List<Player> shotOwingPlayers = const [],
    Player? shotDecisionPlayer,
  }) : _players = List.unmodifiable(players),
       _deck = Deck.fromCards(remainingDeck),
       _eliminationThreshold = eliminationThreshold,
       _lifetimeDrinks = Map.of(lifetimeDrinks),
       _roundDrinks = Map.of(roundDrinks),
       _calledYamada = Map.of(calledYamada),
       _roundResults = List.of(roundResults),
       _events = List.of(events),
       _eliminatedIds = Set.of(eliminatedIds),
       _eliminations = List.of(eliminations),
       _hands = {
         for (final entry in hands.entries) entry.key: List.of(entry.value),
       },
       _viewIndex = viewIndex,
       _revealed = revealed,
       _pouring = pouring,
       _pourIndex = pourIndex,
       _consecutiveHolds = consecutiveHolds,
       _cupSize = cupSize,
       _roundNumber = roundNumber,
       _roundFinalized = roundFinalized,
       _smallestHands = List.of(smallestHands),
       _revealedPlayers = List.of(revealedPlayers),
       _gameComplete = gameComplete,
       _finalResult = finalResult,
       _yamadaCallerThisRound = yamadaCallerThisRound,
       _shotDecisionPending = shotDecisionPending,
       _shotOwingPlayers = List.of(shotOwingPlayers),
       _shotDecisionPlayer = shotDecisionPlayer {
    _playersActedThisRound.addAll(playersActedThisRound);
    if (_players.length < 2) {
      throw ArgumentError.value(players, 'players', 'need at least 2 players');
    }
    if (_eliminationThreshold < 1) {
      throw ArgumentError.value(
        eliminationThreshold,
        'eliminationThreshold',
        'must be at least 1',
      );
    }
    if (_roundNumber < 1) {
      throw ArgumentError.value(roundNumber, 'roundNumber', 'must be >= 1');
    }
    if (_gameComplete != (_finalResult != null)) {
      throw ArgumentError('gameComplete and finalResult must agree');
    }
    _viewingPlayers = activePlayers;
  }

  final List<Player> _players;
  final Deck _deck;
  final int _eliminationThreshold;
  final Map<String, int> _lifetimeDrinks;
  final Map<String, int> _roundDrinks;
  final Map<String, bool> _calledYamada;
  final List<RoundResult> _roundResults;
  final List<GameEvent> _events;
  final Set<String> _eliminatedIds;
  final List<EliminationRecord> _eliminations;

  /// The current round's hands, keyed by player id (2 cards each).
  Map<String, List<Card>> _hands = {};

  /// The players who still need to view their cards this round.
  late List<Player> _viewingPlayers;
  int _viewIndex = 0;
  bool _revealed = false;

  bool _pouring = false;
  int _pourIndex = 0;
  int _consecutiveHolds = 0;

  CupSize _cupSize = CupSize.normal;
  int _roundNumber = 1;
  bool _roundFinalized = false;
  List<Player> _smallestHands = const [];

  // YAMADA strategic surrender tracking.
  Player? _yamadaCallerThisRound;
  final Set<String> _playersActedThisRound = {};

  /// The IDs of players who have acted (held out or called YAMADA) this round.
  Set<String> get playersActedThisRound =>
      Set.unmodifiable(_playersActedThisRound);

  /// The players who participated in the group reveal.
  List<Player> _revealedPlayers = const [];
  bool _gameComplete = false;
  GameResult? _finalResult;

  // ---------------------------------------------------------------------
  // Pending shot decision state (M20)
  // ---------------------------------------------------------------------

  /// Whether a shot decision is currently pending after round completion.
  bool _shotDecisionPending = false;

  /// The players who still owe a shot (processed front-to-back).
  List<Player> _shotOwingPlayers = const [];

  /// The player currently being asked to decide (take or refuse).
  Player? _shotDecisionPlayer;

  /// Whether a shot decision is pending after round completion.
  bool get shotDecisionPending => _shotDecisionPending;

  /// The player currently being asked to decide (take or refuse).
  Player? get shotDecisionPlayer => _shotDecisionPlayer;

  /// The players who still owe a shot decision, in order.
  List<Player> get shotOwingPlayers => List.unmodifiable(_shotOwingPlayers);

  /// Whether the current player can refuse the shot (enough players for a challenge).
  ///
  /// Requires at least 4 active players (3 others + the refusing player).
  bool get canRefuseShot =>
      shotDecisionPending &&
      activePlayerCount >= challengeMinimumOtherPlayers + 1;

  // ---------------------------------------------------------------------
  // Refusal / Challenge system
  // ---------------------------------------------------------------------

  /// The challenge engine managing refusal/challenge state.
  final ChallengeEngine _challengeEngine = ChallengeEngine();

  /// The dare deck for drawing dare cards during challenges.
  DareDeck? _dareDeck;

  /// The trivia deck for drawing trivia cards during challenges.
  TriviaDeck? _triviaDeck;

  /// Sets the dare deck for this game session.
  void setDareDeck(DareDeck deck) {
    _dareDeck = deck;
  }

  /// Sets the trivia deck for this game session.
  void setTriviaDeck(TriviaDeck deck) {
    _triviaDeck = deck;
  }

  /// The current dare card if the active challenge is a Dare and a card has
  /// been drawn. Null otherwise.
  DareCard? get currentDare => _challengeEngine.state?.currentDare;

  /// Whether a challenge is currently active.
  bool get challengeActive => _challengeEngine.isActive;

  /// The current challenge state, or null when no challenge is active.
  ChallengeState? get challengeState => _challengeEngine.state;

  /// The players eligible to be selected as challenger.
  List<Player> get eligiblePlayersForChallenge =>
      _challengeEngine.state?.eligiblePlayers ?? [];

  // ---------------------------------------------------------------------
  // YAMADA strategic surrender getters
  // ---------------------------------------------------------------------

  Player? get yamadaCallerThisRound => _yamadaCallerThisRound;

  bool get yamadaCalledThisRound => _yamadaCallerThisRound != null;

  /// Whether the YAMADA caller had the smallest hand (correct call).
  bool get yamadaWasCorrect {
    if (_yamadaCallerThisRound == null) return false;
    final caller = _yamadaCallerThisRound!;
    if (!hasHand(caller)) return false;
    final callerTotal = _handTotal(caller);
    return activePlayers.every((p) => _handTotal(p) >= callerTotal);
  }

  // ---------------------------------------------------------------------
  // Identity / roster
  // ---------------------------------------------------------------------

  List<Player> get players => _players;

  bool isEliminated(Player player) => _eliminatedIds.contains(player.id);

  List<Player> get activePlayers => [
    for (final player in _players)
      if (!isEliminated(player)) player,
  ];

  List<Player> get eliminatedPlayers => [
    for (final record in _eliminations) record.player,
  ];

  int get activePlayerCount => activePlayers.length;

  int get eliminationThreshold => _eliminationThreshold;

  List<EliminationRecord> get eliminationHistory =>
      List.unmodifiable(_eliminations);

  List<GameEvent> get events => List.unmodifiable(_events);

  List<GameEvent> eventsForRound(int round) => [
    for (final event in _events)
      if (event.round == round) event,
  ];

  void _record(GameEvent event) => _events.add(event);

  // ---------------------------------------------------------------------
  // Deck / hands
  // ---------------------------------------------------------------------

  int get remainingCards => _deck.remainingCards;

  List<Card> get remainingDeck => _deck.remainingCardsInOrder;

  int get viewIndex => _viewIndex;

  int get pourIndex => _pourIndex;

  int get consecutiveHolds => _consecutiveHolds;

  List<Card> handOf(Player player) => List.unmodifiable(_hands[player.id]!);

  Card visibleCardOf(Player player) => _hands[player.id]!.first;

  bool hasHand(Player player) => _hands.containsKey(player.id);

  void _dealHands() {
    for (final player in activePlayers) {
      if (_deck.remainingCards < 2) {
        _deck.reset();
        _deck.shuffle();
      }
      _hands[player.id] = _deck.deal(2);
    }
  }

  // ---------------------------------------------------------------------
  // Viewing phase
  // ---------------------------------------------------------------------

  bool get pouringStarted => _pouring;

  bool get allPlayersViewed => _viewIndex >= _viewingPlayers.length;

  Player get currentPlayer =>
      _pouring ? activePlayers[_pourIndex] : _viewingPlayers[_viewIndex];

  int get currentPlayerIndex => _pouring ? _pourIndex : _viewIndex;

  int get currentPlayerCount => activePlayers.length;

  bool get currentPlayerRevealed => _revealed;

  void revealCurrentPlayer() {
    if (_pouring) {
      throw const YamadaRoundException('viewing is already over');
    }
    if (allPlayersViewed) {
      throw const YamadaRoundException('all players have already viewed');
    }
    _revealed = true;
    _record(
      GameEvent(
        type: GameEventType.playerViewed,
        round: _roundNumber,
        player: _viewingPlayers[_viewIndex],
      ),
    );
  }

  void passToNextPlayer() {
    if (_pouring) {
      throw const YamadaRoundException('viewing is already over');
    }
    if (allPlayersViewed) {
      throw const YamadaRoundException('all players have already viewed');
    }
    _viewIndex++;
    _revealed = false;
    _record(GameEvent(type: GameEventType.handoff, round: _roundNumber));
    if (allPlayersViewed) {
      _pouring = true;
      _pourIndex = 0;
      _record(
        GameEvent(type: GameEventType.pouringStarted, round: _roundNumber),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Pouring phase: hold out or call YAMADA
  // ---------------------------------------------------------------------

  bool get roundComplete => _roundFinalized;

  Player get pourCurrentPlayer => activePlayers[_pourIndex];

  List<Player> get smallestHands => List.unmodifiable(_smallestHands);

  List<Player> get revealedPlayers => List.unmodifiable(_revealedPlayers);

  bool get isFirstRound => _roundNumber == 1;

  CupSize get cupSize => switch (_roundNumber) {
    1 => CupSize.normal,
    2 => CupSize.large,
    _ => CupSize.extraLarge,
  };

  int get roundNumber => _roundNumber;

  int get completedRounds => _roundResults.length;

  RoundResult? get roundResult => _roundFinalized ? _roundResults.last : null;

  List<RoundResult> get roundResults => List.unmodifiable(_roundResults);

  int drinksOf(Player player) => _lifetimeDrinks[player.id]!;

  int roundDrinksOf(Player player) => _roundDrinks[player.id] ?? 0;

  bool calledYamadaThisRound(Player player) =>
      _calledYamada[player.id] ?? false;

  void holdOut(Player player) {
    _validatePourAction(player);
    _playersActedThisRound.add(player.id);
    _record(
      GameEvent(
        type: GameEventType.playerHeldOut,
        round: _roundNumber,
        player: player,
      ),
    );
    if (_playersActedThisRound.length >= activePlayerCount) {
      _completeRound();
      return;
    }
    _advancePour();
  }

  void callYamada(Player player) {
    _validatePourAction(player);
    if (_yamadaCallerThisRound != null) {
      throw const YamadaRoundException(
        'YAMADA has already been called this round',
      );
    }
    _yamadaCallerThisRound = player;
    _calledYamada[player.id] = true;
    _record(
      GameEvent(
        type: GameEventType.playerCalledYamada,
        round: _roundNumber,
        player: player,
        cupSize: _cupSize,
      ),
    );
    _playersActedThisRound.add(player.id);
    if (_playersActedThisRound.length >= activePlayerCount) {
      _completeRound();
      return;
    }
    _advancePour();
  }

  // ---------------------------------------------------------------------
  // Pending shot decision (M20)
  // ---------------------------------------------------------------------

  /// The current player confirms they will take 1 shot.
  ///
  /// Applies exactly 1 shot, clears the pending decision for this player,
  /// and advances to the next owing player or finalizes the round.
  /// Repeated calls are rejected without mutating state.
  void takeShot() {
    if (!_shotDecisionPending) {
      throw const YamadaRoundException('No shot decision pending');
    }
    final player = _shotDecisionPlayer;
    if (player == null) {
      throw const YamadaRoundException('No player to take shot');
    }
    if (_roundFinalized) {
      throw const YamadaRoundException('Round already finalized');
    }

    _drink(player, GameEventType.shotTaken);

    // Remove this player from the owing list and advance.
    _shotOwingPlayers = _shotOwingPlayers
        .where((p) => p.id != player.id)
        .toList();
    _advanceShotDecision();
  }

  /// The current player refuses to take the shot and enters the challenge flow.
  ///
  /// Returns `true` if a challenge was initiated (3+ other active players),
  /// `false` if the player drinks directly (too few others).
  /// The original pending shot is NOT applied — the challenge replaces it.
  bool refuseShot() {
    if (!_shotDecisionPending) {
      throw const YamadaRoundException('No shot decision pending');
    }
    final player = _shotDecisionPlayer;
    if (player == null) {
      throw const YamadaRoundException('No player to refuse');
    }
    if (_roundFinalized) {
      throw const YamadaRoundException('Round already finalized');
    }
    // Reject refusal when insufficient players for a challenge.
    if (!canRefuseShot) {
      throw const YamadaRoundException(
        'Cannot refuse: requires at least 4 active players for a challenge',
      );
    }

    _record(
      GameEvent(
        type: GameEventType.shotRefused,
        round: _roundNumber,
        player: player,
      ),
    );

    // Remove from owing list — the challenge replaces the original penalty.
    _shotOwingPlayers = _shotOwingPlayers
        .where((p) => p.id != player.id)
        .toList();
    // Clear the current decision player since we're entering challenge flow.
    _shotDecisionPlayer = null;

    // Start challenge flow (canRefuseShot guard ensures enough players).
    final others = activePlayers.where((p) => p.id != player.id).toList();
    _challengeEngine.begin(challengedPlayer: player, eligiblePlayers: others);
    _record(
      GameEvent(
        type: GameEventType.challengeStarted,
        round: _roundNumber,
        player: player,
        players: others,
      ),
    );
    return true;
  }

  /// Advances to the next owing player or finalizes the round.
  void _advanceShotDecision() {
    if (_shotOwingPlayers.isEmpty) {
      _shotDecisionPending = false;
      _shotDecisionPlayer = null;
      // Finalize the round if not yet finalized.
      if (!_roundFinalized) {
        _finalizeRoundAndComplete();
      }
      return;
    }
    // Set next player.
    _shotDecisionPlayer = _shotOwingPlayers.first;
  }

  // ---------------------------------------------------------------------
  // Refusal / Challenge flow (legacy, kept for backward compat)
  // ---------------------------------------------------------------------

  /// Deprecated: refusal now happens after the round result via [refuseShot].
  ///
  /// This method always throws. It exists only for backward compatibility
  /// with the multiplayer protocol layer during migration.
  @Deprecated('Use takeShot() or refuseShot() after round completion')
  bool refuseDrink(Player player) {
    throw const YamadaRoundException(
      'refuseDrink is removed — use takeShot() or refuseShot() after round completion',
    );
  }

  /// Selects a random challenger from the eligible players.
  ChallengeState selectChallenger() {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge to select from');
    }
    final result = _challengeEngine.selectChallenger();
    _record(
      GameEvent(
        type: GameEventType.challengerSelected,
        round: _roundNumber,
        player: result.challenger,
        players: [result.challengedPlayer],
      ),
    );
    return result;
  }

  ChallengeState chooseChallengeType(ChallengeType type, Player player) {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final result = _challengeEngine.chooseChallengeType(type, player);
    _record(
      GameEvent(
        type: GameEventType.challengeTypeChosen,
        round: _roundNumber,
        player: player,
      ),
    );
    return result;
  }

  /// Resolves the active challenge and applies the penalty.
  ///
  /// After resolution, advances the pending shot decision if any remain.
  void resolveChallenge(ChallengeResult result) {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge to resolve');
    }
    final resolved = _challengeEngine.resolve(result);
    final penaltyRecipient = resolved.penaltyRecipient!;

    _drink(penaltyRecipient, GameEventType.challengePenalty);

    _record(
      GameEvent(
        type: GameEventType.challengeResolved,
        round: _roundNumber,
        player: penaltyRecipient,
      ),
    );

    _challengeEngine.reset();

    // After challenge resolves, continue processing pending shots.
    _advanceShotDecision();
  }

  // ---------------------------------------------------------------------
  // Dare system
  // ---------------------------------------------------------------------

  DareCard drawDare() {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.dare) {
      throw const YamadaRoundException('Challenge is not a Dare');
    }
    if (state.phase != ChallengePhase.inProgress) {
      throw const YamadaRoundException(
        'Dare can only be drawn during inProgress phase',
      );
    }
    if (state.currentDare != null) {
      throw const YamadaRoundException('A Dare has already been drawn');
    }
    if (_dareDeck == null) {
      throw StateError('No dare deck has been set on this game');
    }

    final card = _dareDeck!.draw();
    _challengeEngine.setDare(card);

    _record(
      GameEvent(
        type: GameEventType.dareSelected,
        round: _roundNumber,
        player: state.challenger,
      ),
    );

    return card;
  }

  void completeDare() {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.dare) {
      throw const YamadaRoundException('Challenge is not a Dare');
    }
    if (state.currentDare == null) {
      throw const YamadaRoundException('No Dare has been drawn yet');
    }

    _record(
      GameEvent(
        type: GameEventType.dareCompleted,
        round: _roundNumber,
        player: state.challengedPlayer,
      ),
    );

    resolveChallenge(ChallengeResult.challengerPenalty);
  }

  void refuseDare() {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.dare) {
      throw const YamadaRoundException('Challenge is not a Dare');
    }
    if (state.currentDare == null) {
      throw const YamadaRoundException('No Dare has been drawn yet');
    }

    _record(
      GameEvent(
        type: GameEventType.dareRefused,
        round: _roundNumber,
        player: state.challengedPlayer,
      ),
    );

    resolveChallenge(ChallengeResult.challengedPenalty);
  }

  // ---------------------------------------------------------------------
  // RPS system
  // ---------------------------------------------------------------------

  RpsState startRps() {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.rockPaperScissors) {
      throw const YamadaRoundException('Challenge is not RPS');
    }
    if (state.phase != ChallengePhase.inProgress) {
      throw const YamadaRoundException(
        'RPS can only be started during inProgress phase',
      );
    }
    if (state.rpsState != null) {
      throw const YamadaRoundException('RPS has already been started');
    }
    final rps = _challengeEngine.startRps();
    _record(
      GameEvent(
        type: GameEventType.rpsStarted,
        round: _roundNumber,
        player: state.challenger,
      ),
    );
    return rps;
  }

  void recordRpsRound(int roundNumber, RpsRoundOutcome outcome) {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.rockPaperScissors) {
      throw const YamadaRoundException('Challenge is not RPS');
    }
    if (state.rpsState == null) {
      throw const YamadaRoundException('RPS has not been started');
    }
    _challengeEngine.recordRpsRound(roundNumber, outcome);
    _record(
      GameEvent(
        type: GameEventType.rpsRoundRecorded,
        round: _roundNumber,
        player: _challengeEngine.state!.challenger,
      ),
    );
  }

  void resolveRps(ChallengeResult result) {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.rockPaperScissors) {
      throw const YamadaRoundException('Challenge is not RPS');
    }
    if (state.rpsState == null) {
      throw const YamadaRoundException('RPS has not been started');
    }
    final rps = state.rpsState!;
    if (!rps.isMatchComplete) {
      throw const YamadaRoundException(
        'RPS match is not complete — must have a winner (2 rounds won)',
      );
    }
    final penaltyRecipient = result == ChallengeResult.challengerPenalty
        ? rps.challenger
        : rps.challengedPlayer;
    if (penaltyRecipient.id != rps.loser!.id) {
      throw const YamadaRoundException(
        'ChallengeResult does not match the RPS loser',
      );
    }
    _record(
      GameEvent(
        type: GameEventType.rpsResolved,
        round: _roundNumber,
        player: rps.loser,
      ),
    );
    _challengeEngine.resolveRps(result);
    final resolved = _challengeEngine.state!;
    final drinkRecipient = resolved.penaltyRecipient!;
    _drink(drinkRecipient, GameEventType.challengePenalty);
    _record(
      GameEvent(
        type: GameEventType.challengeResolved,
        round: _roundNumber,
        player: drinkRecipient,
      ),
    );
    _challengeEngine.reset();

    // After challenge resolves, continue processing pending shots.
    _advanceShotDecision();
  }

  RpsState? get rpsState => _challengeEngine.state?.rpsState;

  // ---------------------------------------------------------------------
  // Trivia system
  // ---------------------------------------------------------------------

  TriviaState startTrivia(TriviaCard card) {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.trivia) {
      throw const YamadaRoundException('Challenge is not Trivia');
    }
    if (state.phase != ChallengePhase.inProgress) {
      throw const YamadaRoundException(
        'Trivia can only be started during inProgress phase',
      );
    }
    if (state.triviaState != null) {
      throw const YamadaRoundException('Trivia has already been started');
    }
    final trivia = _challengeEngine.startTrivia(card);
    _record(
      GameEvent(
        type: GameEventType.triviaStarted,
        round: _roundNumber,
        player: state.challenger,
      ),
    );
    return trivia;
  }

  void recordTriviaAnswer(bool isCorrect) {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.trivia) {
      throw const YamadaRoundException('Challenge is not Trivia');
    }
    if (state.triviaState == null) {
      throw const YamadaRoundException('Trivia has not been started');
    }
    _challengeEngine.recordTriviaAnswer(isCorrect);
    _record(
      GameEvent(
        type: isCorrect
            ? GameEventType.triviaCorrect
            : GameEventType.triviaWrong,
        round: _roundNumber,
        player: state.challenger,
      ),
    );
  }

  void resolveTrivia(ChallengeResult result) {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.trivia) {
      throw const YamadaRoundException('Challenge is not Trivia');
    }
    if (state.triviaState == null) {
      throw const YamadaRoundException('Trivia has not been started');
    }
    final trivia = state.triviaState!;
    if (trivia.phase != TriviaPhase.answered) {
      throw const YamadaRoundException(
        'Trivia answer has not been recorded yet',
      );
    }
    final expectedResult = trivia.isCorrect!
        ? ChallengeResult.challengerPenalty
        : ChallengeResult.challengedPenalty;
    if (result != expectedResult) {
      throw const YamadaRoundException(
        'ChallengeResult does not match the Trivia answer',
      );
    }
    _record(
      GameEvent(
        type: GameEventType.triviaResolved,
        round: _roundNumber,
        player: trivia.isCorrect! ? state.challenger : state.challengedPlayer,
      ),
    );
    _challengeEngine.resolveTrivia(result);
    final resolved = _challengeEngine.state!;
    final drinkRecipient = resolved.penaltyRecipient!;
    _drink(drinkRecipient, GameEventType.challengePenalty);
    _record(
      GameEvent(
        type: GameEventType.challengeResolved,
        round: _roundNumber,
        player: drinkRecipient,
      ),
    );
    _challengeEngine.reset();

    // After challenge resolves, continue processing pending shots.
    _advanceShotDecision();
  }

  TriviaState? get triviaState => _challengeEngine.state?.triviaState;

  TriviaCard drawTrivia() {
    if (!challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    final state = _challengeEngine.state!;
    if (state.type != ChallengeType.trivia) {
      throw const YamadaRoundException('Challenge is not Trivia');
    }
    if (state.phase != ChallengePhase.inProgress) {
      throw const YamadaRoundException(
        'Trivia can only be drawn during inProgress phase',
      );
    }
    if (state.triviaState != null) {
      throw const YamadaRoundException('Trivia has already been started');
    }
    if (_triviaDeck == null) {
      throw StateError('No trivia deck has been set on this game');
    }

    final card = _triviaDeck!.draw();
    _challengeEngine.startTrivia(card);

    _record(
      GameEvent(
        type: GameEventType.triviaStarted,
        round: _roundNumber,
        player: state.challenger,
      ),
    );

    return card;
  }

  // ---------------------------------------------------------------------
  // Validation / internal helpers
  // ---------------------------------------------------------------------

  void _validatePourAction(Player player) {
    if (!_pouring) {
      throw const YamadaRoundException('the pouring phase has not started');
    }
    if (_roundFinalized) {
      throw const YamadaRoundException('the round is already complete');
    }
    if (_gameComplete) {
      throw const YamadaRoundException('the game is already complete');
    }
    if (isEliminated(player)) {
      throw YamadaRoundException('${player.name} has been eliminated');
    }
    if (player != pourCurrentPlayer) {
      throw YamadaRoundException("it is not ${player.name}'s turn");
    }
  }

  void _advancePour() {
    _pourIndex = (_pourIndex + 1) % activePlayers.length;
  }

  void _drink(Player player, GameEventType drinkType) {
    _lifetimeDrinks[player.id] = _lifetimeDrinks[player.id]! + 1;
    _roundDrinks[player.id] = (_roundDrinks[player.id] ?? 0) + 1;
    _record(
      GameEvent(
        type: drinkType,
        round: _roundNumber,
        player: player,
        cupSize: _cupSize,
      ),
    );
    if (_lifetimeDrinks[player.id]! >= _eliminationThreshold) {
      _eliminate(player);
    }
  }

  // ---------------------------------------------------------------------
  // Round completion
  // ---------------------------------------------------------------------

  /// Completes the pouring phase after every active player has acted.
  void _completeRound() {
    final yamadaCalled = _calledYamada.values.any((called) => called);
    if (yamadaCalled) {
      _resolveYamadaRound();
    } else {
      _resolveNormalRound();
    }

    // If no pending shots, finalize immediately.
    if (!_shotDecisionPending) {
      _finalizeRoundAndComplete();
    }
  }

  /// Finalizes the round, records the result, and checks game completion.
  void _finalizeRoundAndComplete() {
    _finalizeRound();
    _record(
      GameEvent(
        type: GameEventType.roundResult,
        round: _roundNumber,
        result: _roundResults.last,
      ),
    );
    _record(GameEvent(type: GameEventType.roundCompleted, round: _roundNumber));
    _maybeCompleteGame();
  }

  /// Resolves a round where nobody called YAMADA: all hands revealed,
  /// smallest hand owes exactly 1 shot (pending decision).
  void _resolveNormalRound() {
    _revealedPlayers = List.of(activePlayers);
    final smallest = _smallestHandsAmong(activePlayers);
    _smallestHands = smallest;
    _record(
      GameEvent(
        type: GameEventType.revealOccurred,
        round: _roundNumber,
        players: List.of(_revealedPlayers),
      ),
    );
    _record(
      GameEvent(
        type: GameEventType.smallestDetermined,
        round: _roundNumber,
        players: List.of(smallest),
      ),
    );
    // Set up pending shot decisions for the smallest-hand player(s).
    if (smallest.isNotEmpty) {
      // Preserve player order for deterministic processing.
      _shotOwingPlayers = [
        for (final p in _players)
          if (smallest.any((s) => s.id == p.id)) p,
      ];
      _shotDecisionPending = true;
      _shotDecisionPlayer = _shotOwingPlayers.first;
    }
  }

  /// Resolves a round where someone called YAMADA.
  ///
  /// Correct YAMADA (caller has smallest hand): 0 shots, finalize.
  /// Wrong YAMADA: pending 1-shot decision for the caller.
  void _resolveYamadaRound() {
    final caller = _yamadaCallerThisRound!;
    _revealedPlayers = [caller];
    _smallestHands = const [];
    _record(
      GameEvent(
        type: GameEventType.revealOccurred,
        round: _roundNumber,
        players: [caller],
      ),
    );
    final callerHandTotal = _handTotal(caller);
    final callerIsSmallest = activePlayers.every(
      (p) => _handTotal(p) >= callerHandTotal,
    );
    if (callerIsSmallest) {
      // Correct YAMADA: 0 shots.
      _record(
        GameEvent(
          type: GameEventType.smallestDetermined,
          round: _roundNumber,
          players: [caller],
        ),
      );
      _smallestHands = [caller];
      // No pending — correct YAMADA = 0 shots.
    } else {
      // Wrong YAMADA: pending 1-shot decision.
      _shotOwingPlayers = [caller];
      _shotDecisionPending = true;
      _shotDecisionPlayer = caller;
    }
  }

  List<Player> _smallestHandsAmong(List<Player> candidates) {
    var minValue = 1 << 30;
    for (final player in candidates) {
      final value = _handTotal(player);
      if (value < minValue) minValue = value;
    }
    return [
      for (final player in candidates)
        if (_handTotal(player) == minValue) player,
    ];
  }

  int _handTotal(Player player) =>
      _hands[player.id]!.fold(0, (sum, card) => sum + card.value);

  void _finalizeRound() {
    _roundResults.add(
      RoundResult(
        drinks: Map.unmodifiable({
          for (final player in _players) player: _roundDrinks[player.id] ?? 0,
        }),
        calledYamada: Map.unmodifiable({
          for (final player in _players)
            player: _calledYamada[player.id] ?? false,
        }),
        smallestHands: List.unmodifiable(_smallestHands),
        cupSize: cupSize,
      ),
    );
    _roundFinalized = true;
  }

  // ---------------------------------------------------------------------
  // Rounds
  // ---------------------------------------------------------------------

  bool get canStartNextRound => _roundFinalized && !_gameComplete;

  void startNextRound() {
    if (!_roundFinalized) {
      throw const YamadaRoundException('the current round is not complete');
    }
    if (_gameComplete) {
      throw const YamadaRoundException('the game is already complete');
    }
    _hands = {};
    _roundDrinks.clear();
    _calledYamada.clear();
    _smallestHands = const [];
    _revealedPlayers = const [];
    _viewIndex = 0;
    _revealed = false;
    _pouring = false;
    _pourIndex = 0;
    _roundFinalized = false;
    _yamadaCallerThisRound = null;
    _playersActedThisRound.clear();
    _shotDecisionPending = false;
    _shotOwingPlayers = const [];
    _shotDecisionPlayer = null;
    _roundNumber++;
    _record(GameEvent(type: GameEventType.roundStarted, round: _roundNumber));
    _dealHands();
    _record(
      GameEvent(
        type: GameEventType.cardsDealt,
        round: _roundNumber,
        players: List.of(activePlayers),
      ),
    );
    _viewingPlayers = activePlayers;
  }

  // ---------------------------------------------------------------------
  // Elimination / game completion
  // ---------------------------------------------------------------------

  void _eliminate(Player player) {
    if (isEliminated(player)) return;
    _eliminatedIds.add(player.id);
    _eliminations.add(
      EliminationRecord(
        player: player,
        round: _roundNumber,
        drinks: _lifetimeDrinks[player.id]!,
        reason: EliminationReason.sixDrinks,
      ),
    );
    _record(
      GameEvent(
        type: GameEventType.playerEliminated,
        round: _roundNumber,
        player: player,
      ),
    );
  }

  bool get gameComplete => _gameComplete;

  GameResult? get finalResult => _finalResult;

  void _maybeCompleteGame() {
    if (_gameComplete) return;
    if (activePlayerCount >= 2) return;
    _gameComplete = true;
    _finalResult = _buildFinalResult();
    _record(GameEvent(type: GameEventType.gameCompleted, round: _roundNumber));
  }

  GameResult _buildFinalResult() {
    return GameResult(
      drinks: Map.unmodifiable({
        for (final player in _players) player: _lifetimeDrinks[player.id]!,
      }),
      turtleKings: activePlayerCount == 1
          ? List.unmodifiable(activePlayers)
          : const [],
      finalists: List.unmodifiable(activePlayers),
      eliminated: List.unmodifiable(eliminatedPlayers),
      eliminations: List.unmodifiable(_eliminations),
      roundsPlayed: _roundResults.length,
    );
  }
}
