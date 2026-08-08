import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

void main() {
  List<Player> twoPlayers() => [
        Player(
          id: 'player-1',
          name: 'Caleb',
          color: PlayerColors.palette[0],
        ),
        Player(
          id: 'player-2',
          name: 'Bob',
          color: PlayerColors.palette[1],
        ),
      ];

  GameState gameForTwo() => GameState(
        players: twoPlayers(),
        random: Random(42),
      );

  Future<void> pumpGame(WidgetTester tester, GameState game) async {
    await tester.pumpWidget(
      MaterialApp(home: GameStartScreen(game: game)),
    );
  }

  List<String> revealedLabels(WidgetTester tester) => tester
      .widgetList<CardFace>(find.byType(CardFace))
      .map((face) => face.card.displayName)
      .toList();

  /// The full private-viewing turn for the current player: reveal, then pass.
  Future<void> completeTurn(WidgetTester tester) async {
    await tester.tap(find.text('Reveal My Cards'));
    await tester.pump();
    await tester.tap(find.text('Pass to Next Player'));
    await tester.pump();
  }

  group('GameStartScreen', () {
    testWidgets('the first player starts the viewing flow with cards hidden',
        (tester) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      expect(find.text('Player 1 of 2'), findsOneWidget);
      expect(find.text('Caleb'), findsOneWidget);
      expect(find.text('Reveal My Cards'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });

    testWidgets('tells the player to view their cards privately',
        (tester) async {
      await pumpGame(tester, gameForTwo());

      expect(find.textContaining('privately'), findsOneWidget);
    });

    testWidgets('reveals exactly the current player\'s two cards',
        (tester) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      await tester.tap(find.text('Reveal My Cards'));
      await tester.pump();

      final expected = game
          .handOf(game.players[0])
          .map((card) => card.displayName)
          .toList();
      expect(revealedLabels(tester), hasLength(2));
      expect(revealedLabels(tester), expected);
      expect(find.text('Pass to Next Player'), findsOneWidget);
    });

    testWidgets('passing moves to a neutral handoff screen with no cards',
        (tester) async {
      await pumpGame(tester, gameForTwo());

      await completeTurn(tester);

      expect(find.text('Pass the phone'), findsOneWidget);
      expect(find.text('Hand the phone to Bob.'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
      expect(find.text('Reveal My Cards'), findsNothing);
    });

    testWidgets(
        'the next player\'s cards stay hidden until they explicitly reveal '
        'them', (tester) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      // Caleb views and passes; the phone is handed to Bob.
      await completeTurn(tester);
      expect(find.byType(CardFace), findsNothing);

      // Bob continues to his own ready screen — still hidden.
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Player 2 of 2'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);

      // Only after Bob explicitly reveals do his cards appear.
      await tester.tap(find.text('Reveal My Cards'));
      await tester.pump();
      final expected = game
          .handOf(game.players[1])
          .map((card) => card.displayName)
          .toList();
      expect(revealedLabels(tester), hasLength(2));
      expect(revealedLabels(tester), expected);
    });

    testWidgets('the final player reaching the end sees the completion screen',
        (tester) async {
      await pumpGame(tester, gameForTwo());

      await completeTurn(tester); // Caleb views and passes.
      await tester.tap(find.text('Continue')); // Bob takes the phone.
      await tester.pump();
      await completeTurn(tester); // Bob views and passes.

      expect(find.text('All players ready'), findsOneWidget);
      expect(
        find.textContaining('initial dealing phase is complete'),
        findsOneWidget,
      );
      expect(find.byType(CardFace), findsNothing);
    });

    testWidgets('Back to setup returns to the previous screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GameStartScreen(game: gameForTwo()),
                    ),
                  ),
                  child: const Text('Launch game'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch game'));
      await tester.pumpAndSettle();
      expect(find.byType(GameStartScreen), findsOneWidget);

      await tester.tap(find.text('Back to setup'));
      await tester.pumpAndSettle();
      expect(find.byType(GameStartScreen), findsNothing);
      expect(find.text('Launch game'), findsOneWidget);
    });
  });
}
