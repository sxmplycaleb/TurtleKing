import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_history_screen.dart';
import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/driver.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';
import 'package:turtle_king/round_history_screen.dart';

void main() {
  List<Player> twoPlayers() => [
    Player(id: 'player-1', name: 'Caleb', color: PlayerColors.palette[0]),
    Player(id: 'player-2', name: 'Bob', color: PlayerColors.palette[1]),
  ];

  GameState gameForTwo({int threshold = 100}) => GameState(
    players: twoPlayers(),
    random: Random(42),
    eliminationThreshold: threshold,
  );

  Future<void> pumpGame(WidgetTester tester, GameState game) async {
    await tester.pumpWidget(
      MaterialApp(home: GameStartScreen(driver: LocalDriver(game))),
    );
  }

  List<String> revealedLabels(WidgetTester tester) => tester
      .widgetList<CardFace>(find.byType(CardFace))
      .map((face) => face.card.displayName)
      .toList();

  /// The private-viewing turn for the current viewer: reveal, then pass.
  Future<void> completeViewingTurn(WidgetTester tester) async {
    await tester.tap(find.text('Reveal My Card'));
    await tester.pump();
    await tester.tap(find.text('Pass to Next Player'));
    await tester.pump();
  }

  /// Both players view their one card, then pouring begins.
  Future<void> finishViewing(WidgetTester tester) async {
    await completeViewingTurn(tester);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await completeViewingTurn(tester);
  }

  /// Scrolls [label] into view and taps it.
  Future<void> tapVisible(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pump();
  }

  /// The current pourer holds out; a neutral handoff follows.
  Future<void> holdOut(WidgetTester tester) async {
    await tapVisible(tester, 'Hold out');
  }

  group('viewing phase', () {
    testWidgets('the first player starts the flow with cards hidden', (
      tester,
    ) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      expect(find.text('Round 1'), findsOneWidget);
      expect(find.text('Player 1 of 2'), findsOneWidget);
      expect(find.text('Caleb'), findsOneWidget);
      expect(find.text('Reveal My Card'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });

    testWidgets('tells the player to view their card privately', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());

      expect(find.textContaining('privately'), findsOneWidget);
    });

    testWidgets("reveals exactly the current player's one visible card", (
      tester,
    ) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      await tester.tap(find.text('Reveal My Card'));
      await tester.pump();

      expect(revealedLabels(tester), [
        game.visibleCardOf(game.players[0]).displayName,
      ]);
      expect(find.text('Pass to Next Player'), findsOneWidget);
    });

    testWidgets('passing moves to a neutral handoff screen with no cards', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());

      await completeViewingTurn(tester);

      expect(find.text('Pass the phone'), findsOneWidget);
      expect(find.text('Hand the phone to Bob.'), findsOneWidget);
      expect(find.textContaining('card stays hidden'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
      expect(find.text('Reveal My Card'), findsNothing);
    });

    testWidgets(
      "the next player's card stays hidden until they explicitly continue",
      (tester) async {
        final game = gameForTwo();
        await pumpGame(tester, game);

        await completeViewingTurn(tester);
        expect(find.byType(CardFace), findsNothing);

        await tester.tap(find.text('Continue'));
        await tester.pump();
        expect(find.text('Player 2 of 2'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
        expect(find.byType(CardFace), findsNothing);
      },
    );
  });

  group('pouring phase', () {
    testWidgets('pouring begins after everyone has viewed their card', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());

      await finishViewing(tester);

      // The phone goes back to player 1 with the cup already pouring.
      expect(find.text('Pass the phone'), findsOneWidget);
      expect(find.text('Hand the phone to Caleb.'), findsOneWidget);
      expect(find.textContaining('cup is on the table'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);

      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.textContaining('Water is being poured'), findsOneWidget);
      expect(find.textContaining('round 1'), findsOneWidget);
      expect(find.text('YAMADA!'), findsOneWidget);
      expect(find.text('Hold out'), findsOneWidget);
    });

    testWidgets("the pour turn shows only the current player's visible card", (
      tester,
    ) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      await finishViewing(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();

      final current = game.pourCurrentPlayer;
      expect(find.text(current.name), findsOneWidget);
      expect(revealedLabels(tester), [game.visibleCardOf(current).displayName]);
    });

    testWidgets(
      'YAMADA is a strategic surrender that advances to the next turn',
      (tester) async {
        final game = gameForTwo();
        await pumpGame(tester, game);

        await finishViewing(tester);
        await tester.tap(find.text('Continue'));
        await tester.pump();

        final firstPlayer = game.pourCurrentPlayer;
        await tapVisible(tester, 'YAMADA!');

        // Turn advances to the other player.
        expect(find.textContaining(firstPlayer.name), findsNothing);
      },
    );

    testWidgets('holding out passes the turn through a neutral handoff', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());

      await finishViewing(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();

      await holdOut(tester);

      expect(find.text('Pass the phone'), findsOneWidget);
      expect(find.text('Hand the phone to Bob.'), findsOneWidget);
      expect(find.textContaining('cup is on the table'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });
  });

  group('round completion', () {
    testWidgets(
      'a no-YAMADA round reveals all cards and the smallest hand drinks',
      (tester) async {
        final game = gameForTwo();
        await pumpGame(tester, game);

        await finishViewing(tester);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await holdOut(tester);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await holdOut(tester);

        expect(find.text('Round 1 complete'), findsOneWidget);
        expect(
          find.textContaining('all cards are revealed together'),
          findsOneWidget,
        );
        // Both hands (2 cards each) are face-up at the reveal.
        expect(find.byType(CardFace), findsNWidgets(4));
        expect(find.textContaining('Smallest hand:'), findsOneWidget);
        expect(find.textContaining('Next round: 2 shot(s)'), findsOneWidget);
        expect(find.text('Start Next Round'), findsOneWidget);
      },
    );

    testWidgets('a round with YAMADA completes with a reveal', (tester) async {
      await pumpGame(tester, gameForTwo());

      await finishViewing(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      // Player 1 calls YAMADA.
      await tapVisible(tester, 'YAMADA!');
      // Handoff screen, advance to next player.
      await tester.tap(find.text('Continue'));
      await tester.pump();
      // Player 2 holds out.
      await holdOut(tester);

      expect(find.text('Round 1 complete'), findsOneWidget);
      expect(find.textContaining('YAMADA was called'), findsOneWidget);
      expect(find.textContaining('Next round: 2 shot(s)'), findsOneWidget);
      expect(find.text('Start Next Round'), findsOneWidget);
    });

    testWidgets('starting the next round deals fresh private hands', (
      tester,
    ) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      await finishViewing(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await holdOut(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await holdOut(tester);

      await tapVisible(tester, 'Start Next Round');

      expect(find.text('Round 2'), findsOneWidget);
      expect(find.text('Player 1 of 2'), findsOneWidget);
      expect(find.text('Reveal My Card'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });
  });

  group('elimination and game over', () {
    testWidgets(
      'a player eliminated by penalty is out; the last player is Turtle King',
      (tester) async {
        final game = gameForTwo(threshold: 2);
        await pumpGame(tester, game);

        // Play rounds until the game completes.
        while (!game.gameComplete) {
          await finishViewing(tester);
          await tester.tap(find.text('Continue'));
          await tester.pump();
          await holdOut(tester);
          await tester.tap(find.text('Continue'));
          await tester.pump();
          await holdOut(tester);
          await tester.pump();
          if (game.gameComplete) break;
          await tester.tap(find.text('Start Next Round'));
          await tester.pump();
        }

        expect(find.text('Game complete'), findsOneWidget);
      },
    );

    testWidgets('round history opens from the final screen', (tester) async {
      final game = gameForTwo(threshold: 2);
      await pumpGame(tester, game);

      while (!game.gameComplete) {
        await finishViewing(tester);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await holdOut(tester);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await holdOut(tester);
        await tester.pump();
        if (game.gameComplete) break;
        await tester.tap(find.text('Start Next Round'));
        await tester.pump();
      }

      await tapVisible(tester, 'Round History');
      await tester.pumpAndSettle();

      expect(find.byType(RoundHistoryScreen), findsOneWidget);
      expect(find.text('Round History'), findsOneWidget);
    });

    testWidgets('game history opens from the final screen', (tester) async {
      final game = gameForTwo(threshold: 2);
      await pumpGame(tester, game);

      while (!game.gameComplete) {
        await finishViewing(tester);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await holdOut(tester);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await holdOut(tester);
        await tester.pump();
        if (game.gameComplete) break;
        await tester.tap(find.text('Start Next Round'));
        await tester.pump();
      }

      await tapVisible(tester, 'Game History');
      await tester.pumpAndSettle();

      expect(find.byType(GameHistoryScreen), findsOneWidget);
      expect(find.text('Game History'), findsOneWidget);
    });
  });
}
