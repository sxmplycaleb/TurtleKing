import 'dart:math';

import 'card.dart';

/// Thrown when dealing more cards than the deck has available.
class EmptyDeckException implements Exception {
  const EmptyDeckException();

  @override
  String toString() => 'EmptyDeckException: not enough cards in the deck.';
}

/// A standard 52-card deck.
///
/// A fresh, unshuffled deck deals Ace of Hearts first, then proceeds through
/// every suit/rank combination. [shuffle] randomizes the order.
class Deck {
  Deck({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<Card> _cards = _newDeck();

  /// Number of cards remaining in the deck.
  int get remainingCards => _cards.length;

  static List<Card> _newDeck() => [
        for (final suit in Suit.values)
          for (final rank in Rank.values) Card(suit: suit, rank: rank),
      ];

  /// Randomly reorders the deck, preserving all 52 cards.
  void shuffle() {
    _cards.shuffle(_random);
  }

  /// Deals and removes one card from the top of the deck.
  ///
  /// Throws [EmptyDeckException] if the deck is empty.
  Card dealOne() {
    if (_cards.isEmpty) {
      throw const EmptyDeckException();
    }
    return _cards.removeAt(0);
  }

  /// Deals and removes [count] cards from the top of the deck.
  ///
  /// Throws [EmptyDeckException] if fewer than [count] cards remain.
  List<Card> deal(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    if (count > _cards.length) {
      throw const EmptyDeckException();
    }
    return [for (var i = 0; i < count; i++) dealOne()];
  }

  /// Restores a complete, fresh 52-card deck.
  void reset() {
    _cards
      ..clear()
      ..addAll(_newDeck());
  }
}
