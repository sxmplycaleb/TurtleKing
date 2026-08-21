/// Status of a game in the catalog.
enum GameStatus {
  /// The game is fully playable.
  available,

  /// The game is planned but not yet implemented.
  comingSoon,
}

/// A game entry in the TurtleKing catalog.
///
/// Data-driven so adding or promoting a game requires only a catalog change,
/// not widget restructuring.
class GameEntry {
  const GameEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.artworkAsset,
    required this.status,
    this.detailedDescription,
  });

  /// Stable identifier used for play-count persistence.
  final String id;

  /// Display name.
  final String name;

  /// Short description shown on the card.
  final String description;

  /// Asset path for the game's artwork/icon.
  final String artworkAsset;

  /// Current availability status.
  final GameStatus status;

  /// Longer description shown on the preview/detail screen.
  final String? detailedDescription;

  /// Whether the game can be played.
  bool get isAvailable => status == GameStatus.available;
}

/// The complete TurtleKing game catalog.
///
/// TurtleKing is the primary game. The other games are Coming Soon.
const List<GameEntry> gameCatalog = [
  // --- Primary game (available) ---
  // TurtleKing is handled separately on the home screen — not listed here.

  // --- Coming Soon games ---
  GameEntry(
    id: 'choose_a_topic',
    name: 'Choose a Topic',
    description:
        'Everyone puts a finger on the screen and chooses a topic. '
        'The app randomly selects a player and a letter. '
        'Name something from the chosen topic starting with that letter.',
    artworkAsset: 'assets/branding/turtle_king_emblem.png',
    status: GameStatus.comingSoon,
    detailedDescription:
        'All players place a finger on the screen. The app randomly '
        'selects one player. A topic is selected. The app randomly '
        'selects a letter from A–Z. The selected player must name '
        'something belonging to the topic that starts with that letter. '
        'They have 5 seconds. If they fail before the timer expires, '
        'they take a shot.',
  ),
  GameEntry(
    id: 'shots_and_ladders',
    name: 'Shots & Ladders',
    description: 'Classic ladders-style gameplay with a drinking-game twist.',
    artworkAsset: 'assets/branding/turtle_king_emblem.png',
    status: GameStatus.comingSoon,
  ),
  GameEntry(
    id: 'guess_the_word_or_take_a_shot',
    name: 'Guess the Word or Take a Shot',
    description:
        'Guess the word from the emojis before time runs out — or take a shot.',
    artworkAsset: 'assets/branding/turtle_king_emblem.png',
    status: GameStatus.comingSoon,
    detailedDescription:
        'The game will use emoji combinations as clues. '
        'For example: 🍎 + 👨‍⚕️ — the player must guess the intended '
        'word or phrase. Keep the actual word bank and gameplay '
        'implementation for a future milestone.',
  ),
  GameEntry(
    id: 'spell_or_take_a_shot',
    name: 'Spell or Take a Shot',
    description:
        'How good is your spelling? Start easy and work your way up. '
        'Spell the word before the timer runs out.',
    artworkAsset: 'assets/branding/turtle_king_emblem.png',
    status: GameStatus.comingSoon,
    detailedDescription:
        'Words start easy. Difficulty progressively increases. '
        'A timer is displayed. Player must spell the displayed/announced '
        'word before time expires. Failure results in the drinking-game '
        'consequence.',
  ),
  GameEntry(
    id: 'dont_say_the_same_word',
    name: "Don't Say the Same Word",
    description:
        'Take turns naming something from the category. Don\'t repeat an answer.',
    artworkAsset: 'assets/branding/turtle_king_emblem.png',
    status: GameStatus.comingSoon,
    detailedDescription:
        'Players take turns giving an answer belonging to the selected category. '
        'A player loses the round if they repeat an answer already given or '
        'fail to provide an answer within the time limit.\n\n'
        'Initial categories: Animals, Colors, Food, Artists, Cars, Weather, Fruit.',
  ),
  GameEntry(
    id: 'ludo',
    name: 'Ludo',
    description: 'Classic Ludo with the TurtleKing treatment.',
    artworkAsset: 'assets/branding/turtle_king_emblem.png',
    status: GameStatus.comingSoon,
  ),
];
