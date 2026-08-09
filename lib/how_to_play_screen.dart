import 'package:flutter/material.dart';

/// How to play Turtle King per the authoritative rules.
///
/// Pure documentation/UI: the screen is stateless, takes no [GameState], and
/// never mutates gameplay state. Every statement here describes behavior that
/// is actually implemented. Where the authoritative rules are silent, the
/// implemented choice is clearly labeled as a project rule/assumption in the
/// "Current Project Rules" section.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How to Play')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Section(
                title: 'The Goal',
                body:
                    'Turtle King is a game that cannot be stopped: hold out '
                    'until the end. Players take turns on a single phone, '
                    'deciding whether to admit defeat or hold out while a '
                    'water cup is being poured. The last player remaining on '
                    'the field wins the crown and becomes the Turtle King.',
              ),
              _Section(
                title: 'Setting Up',
                body:
                    'Before the game starts, add 2 to 10 players on the setup '
                    'screen. Everyone shares a single phone: the phone is '
                    'passed around and players take turns on the same device. '
                    'The order players are added is the order they play in.',
              ),
              _Section(
                title: 'Your Two Cards',
                body:
                    'Each player is dealt two cards — but you may only look '
                    'at ONE of them. Your second card stays hidden from '
                    'everyone, including you, until the group reveal. The '
                    'app shows you only your one visible card, privately, and '
                    'hides it again before the phone changes hands.',
              ),
              _Section(
                title: 'Pass the Phone',
                body:
                    'On your turn: reveal your one visible card, look at it, '
                    'then pass the phone. The app shows a neutral "pass the '
                    'phone" screen with no cards on it. Hand the phone to the '
                    'next player. Nothing appears automatically — they must '
                    'tap Continue before their own card is revealed.',
              ),
              _Section(
                title: 'The Pouring Cup',
                body:
                    'After everyone has looked at their card, a water cup is '
                    'placed on the table and water begins to be poured. In '
                    'turn, each player decides what to do while the water '
                    'rises: hold out, or shout YAMADA.',
              ),
              _Section(
                title: 'YAMADA',
                body:
                    'If you feel your other (hidden) card is too small, you '
                    'can shout "Yamada!" — this means you admit defeat. You '
                    'drink the water currently in the cup, you are dealt two '
                    'new cards (and look at one of them), and the game '
                    'continues.',
              ),
              _Section(
                title: 'Hold Out',
                body:
                    'If you do not shout YAMADA, you hold out. If every '
                    'player holds out without shouting, the cup is filled and '
                    'all players reveal their cards together.',
              ),
              _Section(
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
              _Section(
                title: 'Cup Sizes',
                body:
                    'The cup grows as the game goes on. The first round uses '
                    'a normal cup. Because no player admitted defeat in the '
                    'first round, the second round switches to a large cup; '
                    'if nobody admits defeat in the second round either, the '
                    'third round switches to an extra-large cup.',
              ),
              _Section(
                title: 'Drinking Counts',
                body:
                    'Every drink counts: a YAMADA drink, a full-cup penalty, '
                    'and the extra holding-out cup are each one drinking '
                    'event. A player who accumulates six drinking events is '
                    'directly eliminated on the spot.',
              ),
              _Section(
                title: 'Multiple Rounds',
                body:
                    'After a round ends, the players still standing receive '
                    'fresh two-card hands and a new round begins — the cup '
                    'size carries over. When the deck runs low it is shuffled '
                    'back to a full 52 cards so the game can continue.',
              ),
              _Section(
                title: 'Elimination',
                body:
                    'A player who reaches six drinking events is eliminated '
                    'immediately. Eliminated players no longer receive hands, '
                    'do not take turns, and cannot act. Their history stays '
                    'in the results. If fewer than two active players remain, '
                    'the game ends.',
              ),
              _Section(
                title: 'Turtle King',
                body:
                    'The last player remaining on the field wins the crown '
                    'and becomes the Turtle King of the game. If every '
                    'remaining player is eliminated by the same event, no '
                    'Turtle King is declared.',
              ),
              _Section(
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
            ],
          ),
        ),
      ),
    );
  }
}

/// One titled block of the How to Play screen: a heading, optional body
/// text, optional bullet list, and an optional highlighted example box.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    this.body,
    this.bullets,
    this.example,
    this.highlighted = false,
  });

  final String title;
  final String? body;
  final List<String>? bullets;
  final String? example;

  /// Renders the whole section on a tinted background so the project-rule
  /// assumptions stand out from the rest of the page.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
    final bodyText = body == null
        ? null
        : Text(body!, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4));
    final bulletText = bullets == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final bullet in bullets!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $bullet',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
            ],
          );
    final exampleBox = example == null
        ? null
        : Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              example!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        if (bodyText != null) ...[const SizedBox(height: 8), bodyText],
        if (bulletText != null) ...[const SizedBox(height: 8), bulletText],
        if (exampleBox != null) ...[const SizedBox(height: 12), exampleBox],
      ],
    );

    if (!highlighted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: content,
      ),
    );
  }
}
