/// The four suits of a standard 52-card deck.
enum Suit {
  hearts('Hearts'),
  diamonds('Diamonds'),
  clubs('Clubs'),
  spades('Spades');

  const Suit(this.label);

  /// Human-readable name, e.g. "Hearts".
  final String label;
}

/// The thirteen ranks of a standard 52-card deck, lowest to highest.
///
/// [value] is the Turtle King rank value: Ace is lowest (1), King is highest
/// (13). Tie-breaking rules are not part of this milestone.
enum Rank {
  ace('Ace', 1),
  two('2', 2),
  three('3', 3),
  four('4', 4),
  five('5', 5),
  six('6', 6),
  seven('7', 7),
  eight('8', 8),
  nine('9', 9),
  ten('10', 10),
  jack('Jack', 11),
  queen('Queen', 12),
  king('King', 13);

  const Rank(this.label, this.value);

  /// Human-readable name, e.g. "Ace" or "7".
  final String label;

  /// Numeric value for Turtle King scoring.
  final int value;
}

/// A single card from a standard 52-card deck.
///
/// Immutable and independent of any Flutter UI.
class Card {
  const Card({required this.suit, required this.rank});

  final Suit suit;
  final Rank rank;

  /// Numeric value, derived from the rank (Ace = 1 ... King = 13).
  int get value => rank.value;

  /// Human-readable display name, e.g. "Ace of Hearts".
  String get displayName => '${rank.label} of ${suit.label}';

  @override
  bool operator ==(Object other) =>
      other is Card && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => Object.hash(suit, rank);

  @override
  String toString() => displayName;
}
