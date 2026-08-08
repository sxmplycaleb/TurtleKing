import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/player_colors.dart';
import 'package:turtle_king/player_setup_screen.dart';

void main() {
  Future<void> pumpSetupScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlayerSetupScreen()));
  }

  Future<void> addPlayer(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.text('Add'));
    await tester.pump();
  }

  FilledButton startButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Game'));

  group('PlayerSetupScreen', () {
    testWidgets('shows branding, player count, and limits', (tester) async {
      await pumpSetupScreen(tester);

      expect(find.text('Turtle King'), findsOneWidget);
      expect(find.text('Player Setup'), findsOneWidget);
      expect(find.text('0 / 10'), findsOneWidget);
      expect(
        find.text('Add between 2 and 10 players, then start the game.'),
        findsOneWidget,
      );
    });

    testWidgets('adds a valid player to the list and updates the count',
        (tester) async {
      await pumpSetupScreen(tester);

      await addPlayer(tester, 'Caleb');

      expect(find.text('Caleb'), findsOneWidget);
      expect(find.text('1 / 10'), findsOneWidget);
      expect(find.text('Enter a name to add a player.'), findsNothing);

      // The name field is cleared after a successful add.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('trims whitespace from player names', (tester) async {
      await pumpSetupScreen(tester);

      await addPlayer(tester, '  Caleb  ');

      expect(find.text('Caleb'), findsOneWidget);
      expect(find.text('  Caleb  '), findsNothing);
    });

    testWidgets('rejects empty and whitespace-only names with feedback',
        (tester) async {
      await pumpSetupScreen(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(find.text('Enter a name to add a player.'), findsOneWidget);
      expect(find.text('0 / 10'), findsOneWidget);
    });

    testWidgets('rejects duplicate names with feedback', (tester) async {
      await pumpSetupScreen(tester);

      await addPlayer(tester, 'Caleb');
      await addPlayer(tester, 'caleb');

      expect(find.text('"caleb" is already in the game.'), findsOneWidget);
      expect(find.text('1 / 10'), findsOneWidget);
    });

    testWidgets('removes a player and updates count and start availability',
        (tester) async {
      await pumpSetupScreen(tester);

      await addPlayer(tester, 'Caleb');
      await addPlayer(tester, 'Bob');
      expect(startButton(tester).onPressed, isNotNull);

      await tester.tap(find.byTooltip('Remove Caleb'));
      await tester.pump();

      expect(find.text('Caleb'), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('1 / 10'), findsOneWidget);
      expect(startButton(tester).onPressed, isNull);
    });

    testWidgets('Start Game is disabled with fewer than two players',
        (tester) async {
      await pumpSetupScreen(tester);

      expect(startButton(tester).onPressed, isNull);
      expect(
        find.text('Add at least 2 players to start the game.'),
        findsOneWidget,
      );

      await addPlayer(tester, 'Caleb');
      expect(startButton(tester).onPressed, isNull);
      expect(
        find.text('Add at least 2 players to start the game.'),
        findsOneWidget,
      );
    });

    testWidgets('stops adding players at ten', (tester) async {
      await pumpSetupScreen(tester);

      for (var i = 1; i <= 10; i++) {
        await addPlayer(tester, 'Player $i');
      }

      expect(find.text('10 / 10'), findsOneWidget);
      expect(find.text('Maximum of 10 players reached.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('assigns a distinct color to each player', (tester) async {
      await pumpSetupScreen(tester);

      await addPlayer(tester, 'Caleb');
      await addPlayer(tester, 'Bob');
      await addPlayer(tester, 'Carol');

      final colors = tester
          .widgetList<CircleAvatar>(find.byType(CircleAvatar))
          .map((avatar) => avatar.backgroundColor)
          .toList();

      expect(colors, hasLength(3));
      expect(colors.toSet(), hasLength(3));
      expect(colors.first, PlayerColors.palette[0]);
    });

    testWidgets('reuses a freed color when a player is removed',
        (tester) async {
      await pumpSetupScreen(tester);

      await addPlayer(tester, 'Caleb');
      await addPlayer(tester, 'Bob');
      await tester.tap(find.byTooltip('Remove Caleb'));
      await tester.pump();

      await addPlayer(tester, 'Carol');

      final avatars =
          tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
      expect(avatars, hasLength(2));
      expect(avatars.map((a) => a.backgroundColor).toSet(), hasLength(2));
      // Carol takes Caleb's freed color, the first palette color.
      expect(avatars.last.backgroundColor, PlayerColors.palette[0]);
    });

    testWidgets('Start Game navigates to the game screen with the players',
        (tester) async {
      await pumpSetupScreen(tester);

      await addPlayer(tester, 'Caleb');
      await addPlayer(tester, 'Bob');
      await tester.tap(find.text('Start Game'));
      await tester.pumpAndSettle();

      expect(find.byType(GameStartScreen), findsOneWidget);
      // The game starts with the first player ready to view their cards.
      expect(find.text('Player 1 of 2'), findsOneWidget);
      expect(find.text('Caleb'), findsOneWidget);
      expect(find.text('Reveal My Cards'), findsOneWidget);
    });

    testWidgets('Back to setup returns with the players preserved',
        (tester) async {
      await pumpSetupScreen(tester);

      await addPlayer(tester, 'Caleb');
      await addPlayer(tester, 'Bob');
      await tester.tap(find.text('Start Game'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to setup'));
      await tester.pumpAndSettle();

      expect(find.text('Player Setup'), findsOneWidget);
      expect(find.text('Caleb'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('2 / 10'), findsOneWidget);
    });
  });
}
