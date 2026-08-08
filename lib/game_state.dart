import 'dart:math';

import 'card.dart';
import 'deck.dart';
import 'player.dart';

/// The pass-and-play state of a Turtle King game after the initial deal.
///
/// Created when the game starts: a fresh deck is shuffled and exactly two
/// cards are dealt to each player, keyed by player id. Players then view
/// their own two cards one at a time, in player order, before passing the
/// phone on.
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

  int _currentPlayerIndex = 0;
  bool _revealed = false;

  /// The players in setup order.
  List<Player> get players => _players;

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
