import 'dart:math';

import 'card.dart';
import 'deck.dart';
import 'player.dart';

/// Thrown when a YAMADA round action is attempted illegally.
///
/// A rejected action never mutates the game state.
class YamadaRoundException implements Exception {
  const YamadaRoundException(this.message);

  /// Why the action was rejected.
  final String message;

  @override
  String toString() => 'YamadaRoundException: $message';
}

/// The outcome of a YAMADA call.
///
/// A call either captures the current center card or, when the center card's
/// value is not strictly between the caller's two cards, is a wrong call that
/// captures nothing and applies a penalty to the caller's cup.
class YamadaResult {
  const YamadaResult._({required this.card, required this.penalized});

  /// A successful call that captured [card].
  const YamadaResult.capture(Card card) : this._(card: card, penalized: false);

  /// A wrong call: nothing was captured and a penalty was applied.
  const YamadaResult.penalty() : this._(card: null, penalized: true);

  /// The captured center card, or null when the call was penalized.
  final Card? card;

  /// Whether the call was wrong and added a penalty to the caller's cup.
  final bool penalized;
}

/// Deterministic scoring result of a completed YAMADA round.
///
/// [scores] holds each player's capture count in player order. No winner or
/// Turtle King rule is declared — the real game's rule is not specified — so
/// ties are exposed explicitly via [highestScorers] and [lowestScorers]
/// rather than through a hidden tie-breaker.
class RoundResult {
  const RoundResult({
    required this.scores,
    required this.highestScorers,
    required this.lowestScorers,
  });

  /// Capture counts per player, in player order.
  final Map<Player, int> scores;

  /// The players tied for the most captures (never empty).
  final List<Player> highestScorers;

  /// The players tied for the fewest captures (never empty).
  final List<Player> lowestScorers;
}

/// The pass-and-play state of a Turtle King game.
///
/// Created when the game starts: a fresh deck is shuffled and exactly two
/// cards are dealt to each player, keyed by player id. Players view their own
/// two cards one at a time, in player order, before passing the phone on.
///
/// The undealt cards stay in the game's deck and are the only source for the
/// center pile: [dealToCenter] moves cards from the deck to [centerPile], so
/// a center card can never also be in a player's hand.
///
/// Once every player has viewed their cards, [startYamadaRound] begins the
/// YAMADA round: the top card of the remaining deck becomes the first center
/// card, and players act in order. On a turn, a player either draws the top
/// card of the deck onto the center pile ([drawToCenter]) or calls YAMADA
/// ([callYamada]) to capture the current center card into their own captured
/// pile. Every action advances the turn exactly once; the round is complete
/// after every player has acted once.
///
/// Calling YAMADA when the center card's value is not strictly between the
/// caller's two cards is a wrong call: nothing is captured and a penalty
/// point is added to the caller's cup instead. Each cup holds [cupCapacity]
/// penalty points before it overflows. Capture counts feed the scoring API
/// ([captureCountOf], [totalCapturedCards], [roundResult]).
class GameState {
  GameState({
    required List<Player> players,
    Random? random,
    int cupCapacity = 3,
  }) : _players = List.unmodifiable(players),
       _deck = Deck(random: random),
       _captured = {for (final player in players) player.id: <Card>[]},
       _penalties = {for (final player in players) player.id: 0},
       _cupCapacity = cupCapacity {
    if (_players.length < 2) {
      throw ArgumentError.value(players, 'players', 'need at least 2 players');
    }
    if (_cupCapacity < 1) {
      throw ArgumentError.value(
        cupCapacity,
        'cupCapacity',
        'must be at least 1',
      );
    }
    _deck.shuffle();
    _hands = {for (final player in _players) player.id: _deck.deal(2)};
  }

  final List<Player> _players;
  final Deck _deck;
  late final Map<String, List<Card>> _hands;
  final List<Card> _centerPile = [];
  final Map<String, List<Card>> _captured;
  final Map<String, int> _penalties;
  final int _cupCapacity;

  int _currentPlayerIndex = 0;
  bool _revealed = false;

  bool _roundStarted = false;
  int _roundPlayerIndex = 0;
  bool _roundPlayerActed = false;

  /// The players in setup order.
  List<Player> get players => _players;

  /// Cards remaining in the deck after the initial deal and any center draws.
  int get remainingCards => _deck.remainingCards;

  /// Index into [players] of the player whose turn it is to view their cards.
  int get currentPlayerIndex => _currentPlayerIndex;

  /// The player whose turn it is to view their cards.
  Player get currentPlayer => _players[_currentPlayerIndex];

  /// Whether the current player has revealed their two cards.
  bool get currentPlayerRevealed => _revealed;

  /// Whether every player has completed their viewing turn.
  bool get allPlayersViewed => _currentPlayerIndex >= _players.length;

  /// The two cards dealt to [player], in deal order.
  List<Card> handOf(Player player) => _hands[player.id]!;

  /// The cards drawn to the center pile so far, in deal order.
  ///
  /// Starts empty on a new game. Cards only enter the pile via
  /// [dealToCenter], which takes them from the remaining deck, so the pile
  /// can never contain a card that is also in a player's hand.
  List<Card> get centerPile => List.unmodifiable(_centerPile);

  /// Draws the top card of the remaining deck onto the center pile.
  ///
  /// The drawn card leaves the deck, so [remainingCards] decreases by one and
  /// the card cannot appear anywhere else in the game.
  ///
  /// Throws [EmptyDeckException] when the deck has no cards left.
  Card dealToCenter() {
    final card = _deck.dealOne();
    _centerPile.add(card);
    return card;
  }

  /// Reveals the current player's cards.
  ///
  /// A no-op once every player has already viewed their cards.
  void revealCurrentPlayer() {
    if (!allPlayersViewed) {
      _revealed = true;
    }
  }

  /// Moves the turn to the next player, hiding their cards.
  ///
  /// After the final player passes, [allPlayersViewed] becomes true.
  void passToNextPlayer() {
    _currentPlayerIndex++;
    _revealed = false;
  }

  /// Whether the YAMADA round has started.
  bool get roundStarted => _roundStarted;

  /// Whether the YAMADA round has finished: every player has acted once.
  bool get roundComplete =>
      _roundStarted && _roundPlayerIndex >= _players.length;

  /// Index into [players] of the player whose YAMADA turn it is.
  int get roundPlayerIndex => _roundPlayerIndex;

  /// The player whose YAMADA turn it is.
  ///
  /// Only valid while the round is in progress; once [roundComplete] is true
  /// there is no current player.
  Player get roundCurrentPlayer => _players[_roundPlayerIndex];

  /// Whether the current round player has already completed their action.
  ///
  /// An action advances the turn immediately, so this is always false between
  /// turns; it guards against acting twice within a turn.
  bool get currentPlayerActed => _roundPlayerActed;

  /// The top card of the center pile, which players compare against.
  ///
  /// Null before the round starts or while the center pile is empty.
  Card? get currentCenterCard => _centerPile.isEmpty ? null : _centerPile.last;

  /// Whether the current round player's YAMADA call would capture the center
  /// card: the center card exists and its value is strictly between their
  /// two cards.
  ///
  /// Calling YAMADA is always a legal turn action; when this is false the
  /// call is wrong and applies a penalty instead of capturing.
  bool get canCallYamada =>
      _roundStarted &&
      !roundComplete &&
      !_roundPlayerActed &&
      currentCenterCard != null &&
      _isStrictlyBetween(currentCenterCard!, handOf(roundCurrentPlayer));

  /// The cards [player] has captured with YAMADA, in capture order.
  List<Card> capturedCardsOf(Player player) =>
      List.unmodifiable(_captured[player.id]!);

  /// The number of cards [player] has captured this round.
  int captureCountOf(Player player) => _captured[player.id]!.length;

  /// The total number of captured cards across all players.
  int get totalCapturedCards =>
      _captured.values.fold(0, (sum, cards) => sum + cards.length);

  /// How many penalty points a player's cup holds before it overflows.
  int get cupCapacity => _cupCapacity;

  /// The total number of penalties awarded to [player] (never decreases).
  int penaltyCountOf(Player player) => _penalties[player.id]!;

  /// The current cup fill for [player]: how many of the cup's slots are
  /// occupied. Resets to zero each time the cup overflows.
  int cupFillOf(Player player) => penaltyCountOf(player) % _cupCapacity;

  /// How many full cups [player] has drunk: one for every time their cup
  /// overflowed. Each full cup empties the cup while [penaltyCountOf] keeps
  /// counting every penalty ever awarded.
  int cupDrinksOf(Player player) => penaltyCountOf(player) ~/ _cupCapacity;

  /// The deterministic scoring result of the round, or null until the round
  /// completes. Never changes after completion.
  RoundResult? get roundResult {
    if (!roundComplete) return null;
    final scores = {
      for (final player in _players) player: _captured[player.id]!.length,
    };
    final counts = scores.values.toList();
    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    final minCount = counts.reduce((a, b) => a < b ? a : b);
    return RoundResult(
      scores: Map.unmodifiable(scores),
      highestScorers: [
        for (final player in _players)
          if (scores[player] == maxCount) player,
      ],
      lowestScorers: [
        for (final player in _players)
          if (scores[player] == minCount) player,
      ],
    );
  }

  /// Begins the YAMADA round after every player has viewed their cards.
  ///
  /// Deals the first center card from the remaining deck and gives the turn
  /// to the first player.
  ///
  /// Throws [YamadaRoundException] if the round has already started or if any
  /// player has not yet viewed their cards.
  void startYamadaRound() {
    if (!allPlayersViewed) {
      throw const YamadaRoundException(
        'all players must view their cards before the YAMADA round starts',
      );
    }
    if (_roundStarted) {
      throw const YamadaRoundException('the YAMADA round has already started');
    }
    _roundStarted = true;
    _roundPlayerIndex = 0;
    _roundPlayerActed = false;
    dealToCenter();
  }

  /// [player]'s turn action: draws the top card of the deck onto the center
  /// pile, then advances the turn.
  ///
  /// Throws [YamadaRoundException] if the round has not started, is complete,
  /// or it is not [player]'s turn. Throws [EmptyDeckException] when the deck
  /// has no cards left; the turn is not advanced in that case.
  Card drawToCenter(Player player) {
    _validateRoundAction(player);
    final card = dealToCenter();
    _advanceRoundTurn();
    return card;
  }

  /// [player]'s turn action: calls YAMADA, then advances the turn.
  ///
  /// When the current center card's value is strictly between [player]'s two
  /// hand cards the card is captured into their captured pile and the result
  /// reports no penalty. Otherwise the call is wrong: nothing is captured,
  /// the center card stays in place, and a penalty point is added to
  /// [player]'s cup. Player hands never change.
  ///
  /// Throws [YamadaRoundException] only for genuinely invalid API usage: the
  /// round has not started, is complete, it is not [player]'s turn, the
  /// current player already acted, or there is no center card. The state is
  /// unchanged after a rejected call.
  YamadaResult callYamada(Player player) {
    _validateRoundAction(player);
    final center = currentCenterCard;
    if (center == null) {
      throw const YamadaRoundException('there is no center card to capture');
    }
    if (!_isStrictlyBetween(center, handOf(player))) {
      _penalties[player.id] = _penalties[player.id]! + 1;
      _advanceRoundTurn();
      return const YamadaResult.penalty();
    }
    _centerPile.removeLast();
    _captured[player.id]!.add(center);
    _advanceRoundTurn();
    return YamadaResult.capture(center);
  }

  void _validateRoundAction(Player player) {
    if (!_roundStarted) {
      throw const YamadaRoundException('the YAMADA round has not started');
    }
    if (roundComplete) {
      throw const YamadaRoundException('the YAMADA round is already complete');
    }
    if (_roundPlayerActed) {
      throw const YamadaRoundException(
        'the current player has already acted this turn',
      );
    }
    if (player != roundCurrentPlayer) {
      throw YamadaRoundException("it is not ${player.name}'s turn");
    }
  }

  void _advanceRoundTurn() {
    _roundPlayerActed = false;
    _roundPlayerIndex++;
  }

  /// Whether [card]'s value is strictly between the values in [hand].
  static bool _isStrictlyBetween(Card card, List<Card> hand) {
    final values = hand.map((c) => c.value).toList()..sort();
    return card.value > values.first && card.value < values.last;
  }
}
