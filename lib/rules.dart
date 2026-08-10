/// Single source of truth for the user-facing Turtle King rules text.
///
/// Every screen that shows the rules (the How to Play screen, the in-game
/// rules reference) renders this content. There is deliberately only one copy
/// of the rules text in the application; contract tests in
/// `test/rules_source_test.dart` verify that the authoritative concepts stay
/// present.
///
/// The text describes behavior that is actually implemented by [GameState].
/// Where the authoritative rules are silent, the implemented choice is
/// labeled as a project rule/assumption in the [RulesSection.highlighted]
/// section. This file is pure data and must never depend on Flutter widgets
/// or gameplay state.
library;

/// One titled section of the rules documentation.
class RulesSection {
  const RulesSection({
    required this.id,
    required this.title,
    required this.body,
    this.bullets = const [],
    this.example,
    this.highlighted = false,
  });

  /// Stable semantic identifier used by contract tests, e.g. `twoCards`.
  final String id;

  /// Section heading shown in the UI.
  final String title;

  /// Body text.
  final String body;

  /// Optional bullet points.
  final List<String> bullets;

  /// Optional highlighted example box.
  final String? example;

  /// Renders the section on a tinted background to mark project
  /// rules/assumptions that are not authoritative official rules.
  final bool highlighted;
}

/// The authoritative Turtle King rules as implemented by the game.
///
/// Sections are ordered as they appear on the How to Play screen.
class RulesContent {
  const RulesContent._();

  static const List<RulesSection> sections = [
    RulesSection(
      id: 'goal',
      title: 'The Goal',
      body:
          'Turtle King is a game that cannot be stopped: hold out '
          'until the end. Players take turns on a single phone, '
          'deciding whether to admit defeat or hold out while a '
          'water cup is being poured. The last player remaining on '
          'the field wins the crown and becomes the Turtle King.',
    ),
    RulesSection(
      id: 'settingUp',
      title: 'Setting Up',
      body:
          'Before the game starts, add 2 to 10 players on the setup '
          'screen. Everyone shares a single phone: the phone is '
          'passed around and players take turns on the same device. '
          'The order players are added is the order they play in.',
    ),
    RulesSection(
      id: 'twoCards',
      title: 'Your Two Cards',
      body:
          'Each player is dealt two cards — but you may only look '
          'at ONE of them. Your second card stays hidden from '
          'everyone, including you, until the group reveal. The '
          'app shows you only your one visible card, privately, and '
          'hides it again before the phone changes hands.',
    ),
    RulesSection(
      id: 'passThePhone',
      title: 'Pass the Phone',
      body:
          'On your turn: reveal your one visible card, look at it, '
          'then pass the phone. The app shows a neutral "pass the '
          'phone" screen with no cards on it. Hand the phone to the '
          'next player. Nothing appears automatically — they must '
          'tap Continue before their own card is revealed.',
    ),
    RulesSection(
      id: 'pouringCup',
      title: 'The Pouring Cup',
      body:
          'After everyone has looked at their card, a water cup is '
          'placed on the table and water begins to be poured. In '
          'turn, each player decides what to do while the water '
          'rises: hold out, or shout YAMADA.',
    ),
    RulesSection(
      id: 'yamada',
      title: 'YAMADA',
      body:
          'If you feel your other (hidden) card is too small, you '
          'can shout "Yamada!" — this means you admit defeat. You '
          'drink the water currently in the cup, you are dealt two '
          'new cards (and look at one of them), and the game '
          'continues.',
    ),
    RulesSection(
      id: 'holdOut',
      title: 'Hold Out',
      body:
          'If you do not shout YAMADA, you hold out. If every '
          'player holds out without shouting, the cup is filled and '
          'all players reveal their cards together.',
    ),
    RulesSection(
      id: 'reveal',
      title: 'The Reveal',
      body:
          'When everyone holds out, all hands are revealed at once. '
          'The player with the smallest cards must drink a full cup '
          'of water. Because they held out until the end with the '
          'smallest cards, they must also drink an extra cup of '
          'water.',
      bullets: [
        'Card values: Ace = 1, number cards = their number, '
            'Jack = 11, Queen = 12, King = 13.',
        '"Smallest" means the lowest total value of the two cards. '
            'If players tie for the smallest, all tied players '
            'drink.',
      ],
      example:
          'Example: a 3 and a 7 total 10 — smaller than a 4 and a '
          '9, which total 13.',
    ),
    RulesSection(
      id: 'cupSizes',
      title: 'Cup Sizes',
      body:
          'The cup grows as the game goes on. The first round uses '
          'a normal cup. Because no player admitted defeat in the '
          'first round, the second round switches to a large cup; '
          'if nobody admits defeat in the second round either, the '
          'third round switches to an extra-large cup.',
    ),
    RulesSection(
      id: 'drinkingCounts',
      title: 'Drinking Counts',
      body:
          'Every drink counts: a YAMADA drink, a full-cup penalty, '
          'and the extra holding-out cup are each one drinking '
          'event. A player who accumulates six drinking events is '
          'directly eliminated on the spot.',
    ),
    RulesSection(
      id: 'multipleRounds',
      title: 'Multiple Rounds',
      body:
          'After a round ends, the players still standing receive '
          'fresh two-card hands and a new round begins — the cup '
          'size carries over. When the deck runs low it is shuffled '
          'back to a full 52 cards so the game can continue.',
    ),
    RulesSection(
      id: 'elimination',
      title: 'Elimination',
      body:
          'A player who reaches six drinking events is eliminated '
          'immediately. Eliminated players no longer receive hands, '
          'do not take turns, and cannot act. Their history stays '
          'in the results. If fewer than two active players remain, '
          'the game ends.',
    ),
    RulesSection(
      id: 'turtleKing',
      title: 'Turtle King',
      body:
          'The last player remaining on the field wins the crown '
          'and becomes the Turtle King of the game. If every '
          'remaining player is eliminated by the same event, no '
          'Turtle King is declared.',
    ),
    RulesSection(
      id: 'projectRules',
      title: 'Current Project Rules',
      body:
          'The authoritative rules above are implemented as '
          'written. Where the rules are silent, the game currently '
          'uses these project rules/assumptions:',
      bullets: [
        '"Smallest cards" means the lowest total value of the two '
            'cards; tied players share the penalty.',
        'A YAMADA drink, a full-cup penalty, and the extra '
            'holding-out cup each count as one drinking event.',
        'The cup grows one step (normal → large → extra-large) '
            'after each round with no YAMADA, and stays the same '
            'after a round with YAMADA.',
        'The deck is reshuffled when it runs low, so the game can '
            'continue.',
        'Each new YAMADA hand shows the player one (the first) of '
            'their two new cards.',
        'A round ends once every active player has held out in a '
            'row; if YAMADA was called, no reveal happens and the '
            'round just completes.',
      ],
      highlighted: true,
    ),
  ];
}
