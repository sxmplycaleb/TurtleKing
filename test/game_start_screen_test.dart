import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

void main() {
  List<Player> twoPlayers() => [
    Player(id: 'player-1', name: 'Caleb', color: PlayerColors.palette[0]),
    Player(id: 'player-2', name: 'Bob', color: PlayerColors.palette[1]),
  ];

  GameState gameForTwo() =>
      GameState(players: twoPlayers(), random: Random(42));

  /// Seed 1: neither player can capture the initial center card (3 of
  /// Spades), so YAMADA calls are wrong and incur penalties.
  GameState gameForPenalty() =>
      GameState(players: twoPlayers(), random: Random(1));

  Future<void> pumpGame(WidgetTester tester, GameState game) async {
    await tester.pumpWidget(MaterialApp(home: GameStartScreen(game: game)));
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
    testWidgets('the first player starts the viewing flow with cards hidden', (
      tester,
    ) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      expect(find.text('Player 1 of 2'), findsOneWidget);
      expect(find.text('Caleb'), findsOneWidget);
      expect(find.text('Reveal My Cards'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });

    testWidgets('tells the player to view their cards privately', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());

      expect(find.textContaining('privately'), findsOneWidget);
    });

    testWidgets('reveals exactly the current player\'s two cards', (
      tester,
    ) async {
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

    testWidgets('passing moves to a neutral handoff screen with no cards', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());

      await completeTurn(tester);

      expect(find.text('Pass the phone'), findsOneWidget);
      expect(find.text('Hand the phone to Bob.'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
      expect(find.text('Reveal My Cards'), findsNothing);
    });

    testWidgets(
      'the next player\'s cards stay hidden until they explicitly reveal '
      'them',
      (tester) async {
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
      },
    );

    testWidgets(
      'the final player reaching the end sees the completion screen',
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
      },
    );

    testWidgets('Back to setup returns to the previous screen', (tester) async {
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

  group('GameStartScreen YAMADA round', () {
    /// Completes the M04 viewing phase for both players.
    Future<void> completeViewing(WidgetTester tester) async {
      await completeTurn(tester); // Caleb views and passes.
      await tester.tap(find.text('Continue')); // Bob takes the phone.
      await tester.pump();
      await completeTurn(tester); // Bob views and passes.
      expect(find.text('All players ready'), findsOneWidget);
    }

    /// Runs the full viewing phase, then starts the YAMADA round.
    Future<void> startRound(WidgetTester tester) async {
      await completeViewing(tester);
      await tester.tap(find.text('Start YAMADA Round'));
      await tester.pump();
    }

    /// Scrolls [label] into view (the round screen can overflow the test
    /// viewport) and taps it.
    Future<void> tapAction(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pump();
    }

    testWidgets('the done screen offers to start the YAMADA round', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());
      await completeViewing(tester);

      expect(find.text('Start YAMADA Round'), findsOneWidget);
    });

    testWidgets(
      'starting the round shows the first player, their cards, and the '
      'center card',
      (tester) async {
        final game = gameForTwo();
        await pumpGame(tester, game);
        await startRound(tester);

        expect(find.text('Player 1 of 2'), findsOneWidget);
        expect(find.text('Caleb'), findsOneWidget);
        final expected = [
          game.currentCenterCard!.displayName,
          ...game.handOf(game.players[0]).map((card) => card.displayName),
        ];
        expect(revealedLabels(tester), hasLength(3));
        expect(revealedLabels(tester), expected);
        expect(find.text('YAMADA!'), findsOneWidget);
        expect(find.text('Draw to center'), findsOneWidget);
      },
    );

    testWidgets('YAMADA is always available during a turn', (tester) async {
      final game = gameForTwo(); // seed 42: 3/6 vs center 5, so it captures.
      await pumpGame(tester, game);
      await startRound(tester);

      final yamada = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'YAMADA!'),
      );
      expect(yamada.onPressed, isNotNull);
      expect(game.canCallYamada, isTrue);
      expect(find.textContaining('YAMADA will capture it'), findsOneWidget);

      final draw = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Draw to center'),
      );
      expect(draw.onPressed != null, game.remainingCards > 0);
    });

    testWidgets(
      'the YAMADA hint warns about the penalty when the center card is '
      "not between the player's cards",
      (tester) async {
        final game = gameForPenalty();
        await pumpGame(tester, game);
        await startRound(tester);

        expect(game.canCallYamada, isFalse);
        expect(
          find.textContaining('YAMADA would cost you a penalty'),
          findsOneWidget,
        );
        final yamada = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'YAMADA!'),
        );
        expect(yamada.onPressed, isNotNull);
      },
    );

    testWidgets('a wrong YAMADA call shows the penalty screen, then hands '
        'the phone over', (tester) async {
      await pumpGame(tester, gameForPenalty());
      await startRound(tester);

      await tapAction(tester, 'YAMADA!');

      expect(find.text('Wrong YAMADA call'), findsOneWidget);
      expect(find.textContaining('Caleb called YAMADA'), findsOneWidget);
      expect(find.textContaining('Nothing was captured'), findsOneWidget);
      expect(find.textContaining('cup: 1/3'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);

      await tester.tap(find.text('Pass the phone'));
      await tester.pump();
      expect(find.text('Pass the phone'), findsOneWidget); // handoff header
      expect(find.text('Hand the phone to Bob.'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });

    testWidgets('the completion screen shows captures and penalties', (
      tester,
    ) async {
      await pumpGame(tester, gameForPenalty());
      await startRound(tester);

      // Caleb makes a wrong call, then the phone moves to Bob who draws.
      await tapAction(tester, 'YAMADA!');
      await tester.tap(find.text('Pass the phone'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tapAction(tester, 'Draw to center');

      expect(find.text('YAMADA round complete'), findsOneWidget);
      expect(find.text('Caleb: 0 captured · 1 penalty'), findsOneWidget);
      expect(find.text('Bob: 0 captured · 0 penalty'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });

    testWidgets('acting moves to a neutral handoff screen with no cards', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());
      await startRound(tester);

      await tapAction(tester, 'Draw to center');

      expect(find.text('Pass the phone'), findsOneWidget);
      expect(find.text('Hand the phone to Bob.'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });

    testWidgets("the next player's cards only appear after they continue", (
      tester,
    ) async {
      final game = gameForTwo();
      await pumpGame(tester, game);
      await startRound(tester);

      final calebCards = game
          .handOf(game.players[0])
          .map((card) => card.displayName)
          .toSet();

      await tapAction(tester, 'Draw to center');
      // The neutral handoff shows no one's cards.
      expect(find.byType(CardFace), findsNothing);

      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(find.text('Player 2 of 2'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      final visible = revealedLabels(tester);
      expect(visible, hasLength(3));
      expect(visible.toSet().intersection(calebCards), isEmpty);
      final expected = [
        game.currentCenterCard!.displayName,
        ...game.handOf(game.players[1]).map((card) => card.displayName),
      ];
      expect(visible, expected);
    });

    testWidgets('the round completes after every player acts once', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());
      await startRound(tester);

      await tapAction(tester, 'Draw to center');
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tapAction(tester, 'Draw to center');

      expect(find.text('YAMADA round complete'), findsOneWidget);
      expect(find.text('Caleb: 0 captured · 0 penalty'), findsOneWidget);
      expect(find.text('Bob: 0 captured · 0 penalty'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });
  });
}
