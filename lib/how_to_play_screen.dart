import 'package:flutter/material.dart';

/// How to play the game as implemented through Milestone 09.
///
/// Pure documentation/UI: the screen is stateless, takes no [GameState], and
/// never mutates gameplay state. Every statement here describes behavior that
/// is actually implemented — and the rules the repository does not specify
/// authoritatively are clearly labeled as current project rules/assumptions
/// in the "Current Project Rules" section.
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
                    'Turtle King is a pass-and-play card game for one phone. '
                    'Players take turns looking at their own two cards and '
                    'trying to capture cards from the center pile. At the end '
                    'of the game, the player with the fewest captured cards '
                    'becomes the Turtle King. (The winning rule is a current '
                    'project rule — see "Current Project Rules" below.)',
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
                    'Each player receives two private cards. Your cards are '
                    'only for you — never show them to anyone else. The app '
                    'reveals your cards only when it is your turn to look at '
                    'them, and hides them again before the phone changes '
                    'hands.',
              ),
              _Section(
                title: 'Pass the Phone',
                body:
                    'On your turn: reveal your two cards, look at them, then '
                    'take your action. When you are done, the app shows a '
                    'neutral "pass the phone" screen with no cards on it. '
                    'Hand the phone to the next player. Nothing appears '
                    'automatically — they must tap Continue before their own '
                    'cards are revealed.',
              ),
              _Section(
                title: 'The Center Pile',
                body:
                    'The game has a face-up center pile in the middle of the '
                    'screen. Cards drawn during the round are added to the top '
                    'of the pile. The top card is the current center card — '
                    'the one players compare against. When a player captures '
                    'the current center card, it leaves the pile.',
              ),
              _Section(
                title: 'YAMADA',
                body:
                    'On your turn you may call YAMADA to capture the current '
                    'center card — but only when its value is strictly between '
                    'the values of your two cards.',
                bullets: [
                  'Card values: Ace = 1, number cards = their number, '
                      'Jack = 11, Queen = 12, King = 13.',
                  '"Strictly between" means the center card must be greater '
                      'than one of your cards and less than the other. It can '
                      'never equal either of them.',
                ],
                example:
                    'Example: with cards valued 3 and 9, the center values 4, '
                    '6, and 8 qualify — but 3, 9, and 10 do not.',
              ),
              _Section(
                title: 'Draw to the Center',
                body:
                    'Instead of calling YAMADA, you may draw the next card '
                    'from the remaining deck and place it on top of the center '
                    'pile. Your turn then ends and the next player takes '
                    'over.',
              ),
              _Section(
                title: 'Wrong YAMADA Calls',
                body:
                    'Calling YAMADA when the center card is not strictly '
                    'between your cards is allowed, but it is penalized: the '
                    'center card is not captured and stays on the pile, and '
                    'you receive one penalty point. Your turn still ends and '
                    'play moves on.',
              ),
              _Section(
                title: 'Penalty Cups',
                body:
                    'Penalty points fill your cup. The cup holds 3 penalty '
                    'points by default; when it fills up, one full cup is '
                    'counted and the cup empties. Penalties add up over the '
                    'whole game, and the number of full cups you have '
                    'collected never resets between rounds. The cup is an '
                    'abstract penalty counter — it is not connected to '
                    'alcohol.',
              ),
              _Section(
                title: 'Multiple Rounds',
                body:
                    'A game can last several rounds. Each new round deals '
                    'fresh two-card hands to the players still in the game. '
                    'The same deck is used for the whole game and is not '
                    'reshuffled between rounds. Penalty cups and lifetime '
                    'capture totals carry over. The game ends when the '
                    'configured number of rounds is reached, when the deck '
                    'can no longer support another round, or when fewer than '
                    'two active players remain.',
              ),
              _Section(
                title: 'Elimination',
                body:
                    'Players can be eliminated from the game. Current project '
                    'rule: a player is eliminated when the number of full '
                    'cups they have collected reaches the elimination '
                    'threshold (2 full cups by default). Eliminated players '
                    'no longer receive hands, do not take turns, and cannot '
                    'act. Their captures and penalties still count in the '
                    'final results. If fewer than two active players remain, '
                    'the game ends.',
              ),
              _Section(
                title: 'Turtle King',
                body:
                    'At the end of the game, the Turtle King is the player '
                    'with the fewest total captures. Multiple players can '
                    'share the title when they tie — there is no hidden '
                    'tie-breaker. This is the current project rule, not an '
                    'official Turtle King rule.',
              ),
              _Section(
                title: 'Current Project Rules',
                body:
                    'The repository does not include an official Turtle King '
                    'ruleset, so the game currently implements the following '
                    'rules. They are project assumptions, not official '
                    'rules, and may change in future versions.',
                bullets: [
                  'A wrong YAMADA call costs 1 penalty point.',
                  'The default cup capacity is 3 penalty points.',
                  'The default elimination threshold is 2 full cups.',
                  'The Turtle King is the player(s) with the fewest '
                      'cumulative captures.',
                  'Ties share the title; there is no tie-breaker.',
                  'The deck is not reshuffled between rounds.',
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
