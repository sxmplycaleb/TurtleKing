import 'dart:math';

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

  /// Drinking events per player during this round (YAMADA drinks plus the
  /// smallest-hand penalty: a full cup and an extra cup), in player order.
  final Map<Player, int> drinks;

  /// Whether each player called YAMADA at least once this round.
  final Map<Player, bool> calledYamada;

  /// The players whose hands were the smallest when the round revealed;
  /// each drank a full cup and an extra cup. Ties share the penalty. Empty
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

  /// A YAMADA caller drank the water in the cup.
  yamadaDrink,

  /// A YAMADA caller was dealt two new cards and continues.
  replacementCardsDealt,

  /// The round completed.
  roundCompleted,

  /// Everyone held out and all hands were revealed together.
  revealOccurred,

  /// The smallest hand(s) were determined after the reveal.
  smallestDetermined,

  /// A smallest-hand player drank one full cup.
  fullCupPenalty,

  /// A smallest-hand player drank one extra cup for holding out.
  extraCupPenalty,

  /// A player was eliminated (reached the drinking threshold).
  playerEliminated,

  /// The cup grew one step (normal → large → extra-large).
  cupSizeAdvanced,

  /// The game completed and a final result was produced.
  gameCompleted,

  /// The deterministic result of a completed round was recorded.
  roundResult,
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

/// The pass-and-play state of a Turtle King game, implementing the
/// authoritative rules:
///
/// 1. Each player is dealt two cards but may only look at one of them.
/// 2. After everyone has looked, the water cup is placed and "pouring"
///    begins: players act in turn, each holding out or calling YAMADA.
/// 3. YAMADA means admitting defeat: the caller drinks the water in the cup,
///    is dealt new cards, and continues.
/// 4. If everyone holds out, all hands are revealed together and the player
///    with the smallest hand drinks a full cup plus an extra cup for holding
///    out.
/// 5. The cup grows (normal → large → extra-large) after every round with no
///    YAMADA.
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
  ///
  /// Reconstructs the game exactly as it was — hands, turn, pouring state,
  /// drinks, eliminations, history, and the remaining deck order — without
  /// re-dealing, re-shuffling, or recording new events. The public gameplay
  /// API is identical to a freshly constructed game, so a restored game can
  /// be played, saved again, and completed exactly as if it had never left
  /// memory.
  ///
  /// [remainingDeck] is the ordered list of cards still in the deck, so the
  /// next deal matches what the original game would have dealt.
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
       _finalResult = finalResult {
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

  /// The players who participated in the group reveal (active players at the
  /// moment everyone held out, before penalty drinks). Used so the reveal UI
  /// shows exactly the hands that were revealed together.
  List<Player> _revealedPlayers = const [];
  bool _gameComplete = false;
  GameResult? _finalResult;

  // ---------------------------------------------------------------------
  // Identity / roster
  // ---------------------------------------------------------------------

  /// The players in setup order.
  List<Player> get players => _players;

  /// Whether [player] has been eliminated from the game.
  bool isEliminated(Player player) => _eliminatedIds.contains(player.id);

  /// The players still in the game, in setup order.
  List<Player> get activePlayers => [
    for (final player in _players)
      if (!isEliminated(player)) player,
  ];

  /// The players eliminated so far, in elimination order.
  List<Player> get eliminatedPlayers => [
    for (final record in _eliminations) record.player,
  ];

  /// The number of players still in the game.
  int get activePlayerCount => activePlayers.length;

  /// The number of drinking events required for elimination (6 by default).
  int get eliminationThreshold => _eliminationThreshold;

  /// The full elimination history, in elimination order.
  List<EliminationRecord> get eliminationHistory =>
      List.unmodifiable(_eliminations);

  /// Every recorded game event, in chronological order. Immutable; events
  /// never carry card identities.
  List<GameEvent> get events => List.unmodifiable(_events);

  /// The events recorded for [round] (1-based), in chronological order.
  /// Game-level events (game start / completion) are excluded.
  List<GameEvent> eventsForRound(int round) => [
    for (final event in _events)
      if (event.round == round) event,
  ];

  /// Appends one immutable event to the replay log.
  void _record(GameEvent event) => _events.add(event);

  // ---------------------------------------------------------------------
  // Deck / hands
  // ---------------------------------------------------------------------

  /// Cards remaining in the deck before the next deal.
  int get remainingCards => _deck.remainingCards;

  /// The remaining deck cards in deal order, read-only. Exposed for the
  /// save/resume layer so a restored game deals exactly the cards the
  /// original would have dealt next; never shown in the UI.
  List<Card> get remainingDeck => _deck.remainingCardsInOrder;

  /// The viewing index within the round's viewing list. Save-layer support.
  int get viewIndex => _viewIndex;

  /// The pouring index within the active players. Save-layer support.
  int get pourIndex => _pourIndex;

  /// Consecutive holds without a YAMADA so far this round. Save-layer
  /// support.
  int get consecutiveHolds => _consecutiveHolds;

  /// The two cards dealt to [player] this round, in deal order.
  ///
  /// The first card is the player's visible card — the only one they may
  /// look at until the group reveal. Callers must show [visibleCardOf]
  /// during private phases and only [handOf] at the reveal.
  List<Card> handOf(Player player) => List.unmodifiable(_hands[player.id]!);

  /// The single card [player] may look at this round.
  Card visibleCardOf(Player player) => _hands[player.id]!.first;

  /// Whether [player] has a hand this round (false once eliminated).
  bool hasHand(Player player) => _hands.containsKey(player.id);

  /// Deals a fresh two-card hand to every active player, resetting the deck
  /// (and shuffling) first when it cannot cover the deal.
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
  // Viewing phase: each player looks at their ONE visible card
  // ---------------------------------------------------------------------

  /// Whether the pouring phase has started (viewing is over).
  bool get pouringStarted => _pouring;

  /// Whether every active player has viewed their visible card.
  bool get allPlayersViewed => _viewIndex >= _viewingPlayers.length;

  /// The player whose turn it is: the current viewer, or the current pourer
  /// once pouring has started.
  Player get currentPlayer =>
      _pouring ? activePlayers[_pourIndex] : _viewingPlayers[_viewIndex];

  /// Index of [currentPlayer] within the active players.
  int get currentPlayerIndex => _pouring ? _pourIndex : _viewIndex;

  /// The number of players taking part in the current round.
  int get currentPlayerCount => activePlayers.length;

  /// Whether the current viewer has revealed their visible card.
  bool get currentPlayerRevealed => _revealed;

  /// Reveals the current viewer's visible card.
  ///
  /// Throws [YamadaRoundException] once all players have viewed their cards.
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

  /// Passes the phone to the next viewer; after the final viewer, pouring
  /// begins with the first active player.
  ///
  /// Throws [YamadaRoundException] if called outside the viewing phase or
  /// after every player has already viewed.
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
      _consecutiveHolds = 0;
      _record(
        GameEvent(type: GameEventType.pouringStarted, round: _roundNumber),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Pouring phase: hold out or call YAMADA
  // ---------------------------------------------------------------------

  /// Whether the current round has finished (the reveal resolved and the
  /// result was recorded).
  bool get roundComplete => _roundFinalized;

  /// The player whose pouring turn it is (always an active player).
  Player get pourCurrentPlayer => activePlayers[_pourIndex];

  /// The players tied for the smallest hand after the reveal.
  ///
  /// Empty until the round completes.
  List<Player> get smallestHands => List.unmodifiable(_smallestHands);

  /// The players who revealed their hands together this round.
  ///
  /// Empty until the round completes. Only populated when the round ended
  /// in a reveal (nobody called YAMADA). Excludes anyone eliminated before
  /// the reveal (e.g. by a YAMADA drink); includes players eliminated by
  /// the reveal penalty itself, since they held out.
  List<Player> get revealedPlayers => List.unmodifiable(_revealedPlayers);

  /// Whether the current round is the first round.
  bool get isFirstRound => _roundNumber == 1;

  /// The current round's cup size.
  CupSize get cupSize => _cupSize;

  /// The current round's number (1-based).
  int get roundNumber => _roundNumber;

  /// The number of fully completed rounds.
  int get completedRounds => _roundResults.length;

  /// The deterministic result of the completed round, or null until the
  /// round completes.
  RoundResult? get roundResult => _roundFinalized ? _roundResults.last : null;

  /// Every completed round result, in round order.
  List<RoundResult> get roundResults => List.unmodifiable(_roundResults);

  /// [player]'s lifetime drinking events (never decreases).
  int drinksOf(Player player) => _lifetimeDrinks[player.id]!;

  /// [player]'s drinking events during the current round.
  int roundDrinksOf(Player player) => _roundDrinks[player.id] ?? 0;

  /// Whether [player] has called YAMADA during the current round.
  bool calledYamadaThisRound(Player player) =>
      _calledYamada[player.id] ?? false;

  /// [player]'s pouring-turn action: holds out (does not shout YAMADA).
  ///
  /// When every active player has held out in a row, the round ends. If
  /// nobody called YAMADA, all hands are revealed together and the smallest
  /// hand(s) drink a full cup plus an extra cup for holding out; if YAMADA
  /// was called, the round ends without a reveal.
  ///
  /// Throws [YamadaRoundException] for invalid usage; the state is unchanged
  /// after a rejected call.
  void holdOut(Player player) {
    _validatePourAction(player);
    _consecutiveHolds++;
    _record(
      GameEvent(
        type: GameEventType.playerHeldOut,
        round: _roundNumber,
        player: player,
      ),
    );
    if (_consecutiveHolds >= activePlayerCount) {
      _completeRound();
      return;
    }
    _advancePour();
  }

  /// [player]'s pouring-turn action: shouts YAMADA, admitting defeat.
  ///
  /// The player drinks the water in the cup (one drinking event), is dealt
  /// two new cards (looking at one of them), and their pouring turn repeats
  /// so they can decide again with the new hand. If the drink reaches the
  /// elimination threshold the player is eliminated on the spot; when fewer
  /// than two active players remain the game completes immediately.
  ///
  /// Throws [YamadaRoundException] for invalid usage; the state is unchanged
  /// after a rejected call.
  void callYamada(Player player) {
    _validatePourAction(player);
    _calledYamada[player.id] = true;
    _record(
      GameEvent(
        type: GameEventType.playerCalledYamada,
        round: _roundNumber,
        player: player,
        cupSize: _cupSize,
      ),
    );
    _drink(player, GameEventType.yamadaDrink);
    _consecutiveHolds = 0;
    _maybeCompleteGame();
    if (_gameComplete) return;
    if (!isEliminated(player)) {
      _redealHand(player);
      _record(
        GameEvent(
          type: GameEventType.replacementCardsDealt,
          round: _roundNumber,
          player: player,
        ),
      );
      return; // the same player's turn repeats with the new cards
    }
    // The eliminated player is gone from [activePlayers], so the next active
    // player slides into this index (clamped when the eliminated player was
    // last). The phone then passes to them.
    _pourIndex = _pourIndex % activePlayers.length;
  }

  /// Validates a pouring action and rejects it without mutating anything.
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

  /// Moves the pouring turn to the next active player.
  void _advancePour() {
    _pourIndex = (_pourIndex + 1) % activePlayers.length;
  }

  /// Deals [player] a fresh two-card hand; they look at the first card.
  void _redealHand(Player player) {
    if (_deck.remainingCards < 2) {
      _deck.reset();
      _deck.shuffle();
    }
    _hands[player.id] = _deck.deal(2);
  }

  /// Records one drinking event for [player] and eliminates them on the spot
  /// if the event reaches the threshold. Game completion is evaluated by the
  /// caller, after the surrounding action fully resolves.
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

  /// Completes the pouring phase after every active player has held out in a
  /// row.
  ///
  /// When nobody called YAMADA this round, everyone held out: all hands are
  /// revealed together and the smallest hand(s) drink a full cup plus an
  /// extra cup for holding out. When YAMADA was called, the round ends
  /// without a reveal (the caller already drank the cup); only the YAMADA
  /// drinks are recorded, and the cup does not grow.
  void _completeRound() {
    final yamadaCalled = _calledYamada.values.any((called) => called);
    if (!yamadaCalled) {
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
      for (final player in smallest) {
        // Full cup for the smallest hand, plus the extra holding-out cup.
        _drink(player, GameEventType.fullCupPenalty);
        _drink(player, GameEventType.extraCupPenalty);
      }
    }
    _finalizeRound();
    _record(
      GameEvent(
        type: GameEventType.roundResult,
        round: _roundNumber,
        result: _roundResults.last,
      ),
    );
    _record(GameEvent(type: GameEventType.roundCompleted, round: _roundNumber));
    if (!yamadaCalled) {
      _advanceCupSize();
    }
    _maybeCompleteGame();
  }

  /// The players tied for the smallest total hand value (Ace = 1 ...
  /// King = 13). Ties all drink the penalty.
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

  /// Records the completed round's result exactly once.
  ///
  /// The maps are copied (not merely wrapped) so that resetting per-round
  /// state for the next round can never rewrite recorded history.
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
        cupSize: _cupSize,
      ),
    );
    _roundFinalized = true;
  }

  /// Grows the cup one step after a round with no YAMADA (normal → large →
  /// extra-large, capped).
  void _advanceCupSize() {
    _cupSize = switch (_cupSize) {
      CupSize.normal => CupSize.large,
      CupSize.large || CupSize.extraLarge => CupSize.extraLarge,
    };
    _record(
      GameEvent(
        type: GameEventType.cupSizeAdvanced,
        round: _roundNumber,
        cupSize: _cupSize,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Rounds
  // ---------------------------------------------------------------------

  /// Whether a completed round may be followed by [startNextRound].
  bool get canStartNextRound => _roundFinalized && !_gameComplete;

  /// Starts the next round after the current one has completed.
  ///
  /// Resets per-round state (hands, viewing, pouring, round drinks, YAMADA
  /// flags) and deals fresh two-card hands to every active player from the
  /// same deck, then returns to the private viewing flow. Lifetime drinks,
  /// eliminations, and the (already advanced) cup size persist.
  ///
  /// Throws [YamadaRoundException] if the current round has not completed or
  /// the game is already complete.
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
    _consecutiveHolds = 0;
    _roundFinalized = false;
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

  /// Marks [player] eliminated, recording the elimination exactly once.
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

  /// Whether the whole game is over: fewer than two active players remain.
  bool get gameComplete => _gameComplete;

  /// The deterministic final result, or null until the game completes.
  GameResult? get finalResult => _finalResult;

  /// Completes the game, once, when fewer than two active players remain.
  void _maybeCompleteGame() {
    if (_gameComplete) return;
    if (activePlayerCount >= 2) return;
    _gameComplete = true;
    _finalResult = _buildFinalResult();
    _record(GameEvent(type: GameEventType.gameCompleted, round: _roundNumber));
  }

  /// Builds the final result. Per the authoritative rules the Turtle King is
  /// the last player remaining; if none remain (all eliminated by the same
  /// event) the title is undetermined and [GameResult.turtleKings] is empty.
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
