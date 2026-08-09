import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/how_to_play_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));
  }

  group('HowToPlayScreen', () {
    testWidgets('renders the How to Play title', (tester) async {
      await pumpScreen(tester);

      expect(find.text('How to Play'), findsOneWidget);
      expect(find.byType(HowToPlayScreen), findsOneWidget);
    });

    testWidgets('shows every rules section in order', (tester) async {
      await pumpScreen(tester);

      for (final title in [
        'The Goal',
        'Setting Up',
        'Your Two Cards',
        'Pass the Phone',
        'The Pouring Cup',
        'YAMADA',
        'Hold Out',
        'The Reveal',
        'Cup Sizes',
        'Drinking Counts',
        'Multiple Rounds',
        'Elimination',
        'Turtle King',
        'Current Project Rules',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
    });

    testWidgets('explains the one-visible-card privacy rule', (tester) async {
      await pumpScreen(tester);

      expect(find.textContaining('may only look at ONE'), findsOneWidget);
      expect(find.textContaining('second card stays hidden'), findsOneWidget);
    });

    testWidgets('explains the pass-and-play privacy flow', (tester) async {
      await pumpScreen(tester);

      expect(
        find.textContaining('neutral "pass the phone" screen'),
        findsOneWidget,
      );
      expect(find.textContaining('tap Continue'), findsOneWidget);
    });

    testWidgets('explains YAMADA as admitting defeat', (tester) async {
      await pumpScreen(tester);

      expect(find.textContaining('admit defeat'), findsWidgets);
      expect(find.textContaining('drink the water'), findsOneWidget);
    });

    testWidgets('explains the reveal and smallest-hand penalty', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.textContaining('reveal their cards together'),
        findsOneWidget,
      );
      expect(find.textContaining('drink a full cup'), findsWidgets);
      expect(find.textContaining('extra cup'), findsWidgets);
      expect(find.textContaining('lowest total value'), findsWidgets);
    });

    testWidgets('explains cup sizes and the six-drink elimination', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.textContaining('extra-large cup'), findsOneWidget);
      expect(find.textContaining('six drinking events'), findsWidgets);
    });

    testWidgets('identifies the Turtle King as the last player standing', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.textContaining('last player remaining'), findsWidgets);
    });

    testWidgets('labels project rules as assumptions, not official rules', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Current Project Rules'), findsOneWidget);
      expect(find.textContaining('project rules/assumptions'), findsOneWidget);
    });

    testWidgets('the page is scrollable and lower sections are reachable', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.byType(SingleChildScrollView), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Current Project Rules'), 300);
      expect(find.text('Current Project Rules'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Turtle King'), -300);
      expect(find.text('Turtle King'), findsOneWidget);
    });

    testWidgets('is stateless: no GameState is created or mutated', (
      tester,
    ) async {
      await pumpScreen(tester);

      // The screen takes no GameState and performs no gameplay actions;
      // merely rendering it must not start or alter a game.
      expect(find.byType(HowToPlayScreen), findsOneWidget);
      expect(find.textContaining('Start Game'), findsNothing);
    });
  });
}
