/// Categories for dare cards in the TurtleKing Dare Deck.
enum DareCategory {
  risk('RISK', 'Bold and risky'),
  social('SOCIAL', 'Social and interactive'),
  truth('TRUTH', 'Truth or confession'),
  group('GROUP', 'Everyone participates'),
  chaos('CHAOS', 'Wild and unpredictable'),
  wild('WILD', 'Anything goes');

  const DareCategory(this.label, this.description);

  /// Human-readable category name shown in the UI.
  final String label;

  /// Short description of what this category entails.
  final String description;
}

/// Difficulty level for a dare card.
enum DareDifficulty {
  easy(1),
  medium(2),
  hard(3);

  const DareDifficulty(this.value);

  /// Numeric value for sorting/comparison.
  final int value;
}

/// A single dare card in the TurtleKing Dare Deck.
///
/// Each card has a unique [id], a [category], a [title] (short prompt),
/// a [description] (detailed instructions), and a [difficulty] level.
/// Cards are immutable — the deck handles shuffling and selection.
class DareCard {
  const DareCard({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    this.difficulty = DareDifficulty.medium,
  });

  /// Unique identifier for this card.
  final String id;

  /// The category this dare belongs to.
  final DareCategory category;

  /// Short prompt displayed as the dare title.
  final String title;

  /// Detailed instructions for the dare.
  final String description;

  /// Difficulty level.
  final DareDifficulty difficulty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DareCard && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DareCard($id: $title)';
}
