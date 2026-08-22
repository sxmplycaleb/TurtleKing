import 'dart:math';

import 'dare_card.dart';

/// A shuffled deck of [DareCard]s that supports draw-without-immediate-repeat
/// and automatic reshuffling when exhausted.
///
/// The deck is designed for single-device pass-and-play and multiplayer
/// host-authoritative dare selection. For tests, a [Random] can be injected
/// for deterministic behavior.
class DareDeck {
  /// Creates a new deck from the given [cards].
  ///
  /// If [random] is not provided, a new unseeded [Random] is used.
  DareDeck(List<DareCard> cards, {Random? random})
    : _allCards = List.unmodifiable(cards),
      _random = random ?? Random() {
    _reshuffle();
  }

  final List<DareCard> _allCards;
  final Random _random;
  final List<DareCard> _drawPile = [];
  DareCard? _lastDrawn;

  /// Total number of cards in the full deck (including drawn ones).
  int get totalCards => _allCards.length;

  /// Number of cards remaining in the draw pile.
  int get remaining => _drawPile.length;

  /// Whether the deck has been exhausted (no cards left to draw).
  bool get isEmpty => _drawPile.isEmpty;

  /// The last card that was drawn, or null if no card has been drawn yet.
  DareCard? get lastDrawn => _lastDrawn;

  /// Draws the next card from the deck.
  ///
  /// When the deck is exhausted, it is automatically reshuffled.
  /// The same card is never returned twice in a row unless the deck
  /// has only one card.
  DareCard draw() {
    if (_allCards.isEmpty) {
      throw StateError('Cannot draw from an empty dare deck');
    }

    // If the draw pile is empty or only contains the last drawn card,
    // reshuffle (avoiding the last drawn card as the first item).
    if (_drawPile.isEmpty ||
        (_drawPile.length == 1 && _drawPile.first == _lastDrawn)) {
      _reshuffle();
    }

    // If only one card remains and it's the last drawn, reshuffle entirely.
    if (_drawPile.length == 1 && _drawPile.first == _lastDrawn) {
      _reshuffle();
    }

    final card = _drawPile.removeLast();
    _lastDrawn = card;
    return card;
  }

  /// Draws a random card from a specific category.
  ///
  /// Falls back to [draw] if no cards of the given category remain in the
  /// draw pile.
  DareCard drawFromCategory(DareCategory category) {
    final index = _drawPile.indexWhere((c) => c.category == category);
    if (index != -1) {
      final card = _drawPile.removeAt(index);
      _lastDrawn = card;
      return card;
    }
    // Fallback: draw from remaining pile.
    return draw();
  }

  /// Shuffles the full deck into a new draw pile.
  void _reshuffle() {
    _drawPile
      ..clear()
      ..addAll(_allCards)
      ..shuffle(_random);
  }

  /// Resets the deck to its initial state (all cards available, no history).
  void reset() {
    _lastDrawn = null;
    _reshuffle();
  }
}
