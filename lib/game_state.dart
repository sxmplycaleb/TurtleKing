import 'dart:math';

import 'card.dart';
import 'deck.dart';
import 'player.dart';

/// The pass-and-play state of a Turtle King game.
///
/// Created when the game starts: a fresh deck is shuffled and exactly two
/// cards are dealt to each player, keyed by player id. Players view their own
/// two cards one at a time, in player order, before passing the phone on.
///
/// The undealt cards stay in the game's deck and are the only source for the
/// center pile: [dealToCenter] moves cards from the deck to [centerPile], so
/// a center card can never also be in a player's hand.
class GameState {
  GameState({required List<Player> players, Random? random})
      : _players = List.unmodifiable(players),
        _deck = Deck(random: random) {
    if (_players.length < 2) {
      throw ArgumentError.value(players, 'players', 'need at least 2 players');
    }
    _deck.shuffle();
    _hands = {
      for (final player in _players) player.id: _deck.deal(2),
    };
  }

  final List<Player> _players;
  final Deck _deck;
  late final Map<String, List<Card>> _hands;
  final List<Card> _centerPile = [];

  int _currentPlayerIndex = 0;
  bool _revealed = false;

  /// The players in setup order.
  List<Player> get players => _players;

  /// Cards remaining in the deck after the initial deal and any center draws.
  /// Cards remaining in the deck after the initial deal.
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
}
