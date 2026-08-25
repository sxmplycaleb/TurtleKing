/// Categories for trivia questions in the TurtleKing Trivia Deck.
enum TriviaCategory {
  generalKnowledge('General Knowledge', 'Wide range of topics'),
  geography('Geography', 'Countries, capitals, and landmarks'),
  history('History', 'Historical events and figures'),
  science('Science', 'Physics, chemistry, biology'),
  technology('Technology', 'Computers, internet, gadgets'),
  sports('Sports', 'Athletes, teams, and records'),
  music('Music', 'Artists, songs, and albums'),
  moviesAndTv('Movies & TV', 'Films, shows, and celebrities'),
  food('Food', 'Cuisines, dishes, and ingredients'),
  kenyaAfrica('Kenya/Africa', 'Kenyan and African culture'),
  personal('Personal', 'Group-specific questions'),
  aToZ('A-Z', 'Category-based letter challenge'),
  rapidFire('Rapid Fire', 'Timed sequence of questions');

  const TriviaCategory(this.label, this.description);

  /// Human-readable category name shown in the UI.
  final String label;

  /// Short description of what this category entails.
  final String description;
}

/// Difficulty level for a trivia question.
enum TriviaDifficulty {
  easy(1),
  medium(2),
  hard(3);

  const TriviaDifficulty(this.value);

  /// Numeric value for sorting/comparison.
  final int value;
}

/// A single trivia question in the TurtleKing Trivia Deck.
///
/// Each card has a unique [id], a [category], a [question], an [answer],
/// optional [options] for multiple choice, a [difficulty] level,
/// and flags for [isPersonal] and [isGroupQuestion] questions.
/// Cards are immutable — the deck handles shuffling and selection.
class TriviaCard {
  const TriviaCard({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    this.options = const [],
    this.difficulty = TriviaDifficulty.medium,
    this.isPersonal = false,
    this.isGroupQuestion = false,
    this.aToZLetter,
    this.aToZCategory,
  });

  /// Unique identifier for this card.
  final String id;

  /// The category this question belongs to.
  final TriviaCategory category;

  /// The trivia question text.
  final String question;

  /// The correct answer.
  final String answer;

  /// Optional multiple-choice options (empty for open-ended questions).
  final List<String> options;

  /// Difficulty level.
  final TriviaDifficulty difficulty;

  /// Whether this is a personal question about a specific player.
  final bool isPersonal;

  /// Whether this is a group question about the group dynamic.
  final bool isGroupQuestion;

  /// For A-Z questions: the current letter.
  final String? aToZLetter;

  /// For A-Z questions: the sub-category (e.g., "Countries", "Foods").
  final String? aToZCategory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TriviaCard && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'TriviaCard($id: $question)';
}
