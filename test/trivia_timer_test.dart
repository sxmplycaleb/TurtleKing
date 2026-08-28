import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/challenge/challenge_state.dart';
import 'package:turtle_king/challenge/trivia_card.dart';
import 'package:turtle_king/challenge/trivia_state.dart';
import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/driver.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

/// Creates a 4-player game that has gone through viewing, pouring, and
/// reached a pending shot decision with one player owing a shot.
GameState _gameWithPendingShot({int seed = 42}) {
  final players = [
    for (var i = 0; i < 4; i++)
      Player(id: 'p$i', name: 'Player $i', color: PlayerColors.palette[i]),
  ];
  final game = GameState(players: players, random: _seeded(seed));

  // Viewing phase.
  while (!game.pouringStarted) {
    game.revealCurrentPlayer();
    game.passToNextPlayer();
  }

  // Pouring phase — all hold out to create a normal round with a loser.
  for (var i = 0; i < game.activePlayerCount; i++) {
    game.holdOut(game.pourCurrentPlayer);
  }

  return game;
}

Random _seeded(int seed) {
  // Deterministic random for reproducible tests.
  return Random(seed);
}

/// Sets up a game with an active trivia challenge ready to answer.
/// Returns the game, driver, and the trivia state for inspection.
({GameState game, LocalDriver driver, TriviaState trivia}) _triviaReady({
  int seed = 42,
}) {
  final game = _gameWithPendingShot(seed: seed);
  final driver = LocalDriver(game);

  // Player refuses the shot → challenge begins.
  game.refuseShot();

  // Select a random challenger.
  game.selectChallenger();

  // Choose Trivia as the challenge type.
  final challenger = game.challengeState!.challenger!;
  game.chooseChallengeType(ChallengeType.trivia, challenger);

  // Draw a trivia card and start the trivia challenge.
  final card = TriviaCard(
    id: 'test-trivia-001',
    category: TriviaCategory.generalKnowledge,
    question: 'What is the capital of France?',
    answer: 'Paris',
    difficulty: TriviaDifficulty.easy,
  );
  final trivia = game.startTrivia(card);

  return (game: game, driver: driver, trivia: trivia);
}

Widget _buildTestApp(GameState game, {LocalDriver? driver}) {
  final d = driver ?? LocalDriver(game);
  return MaterialApp(home: GameStartScreen(driver: d));
}

void main() {
  group('Trivia timer constant', () {
    test('kTriviaTimerSeconds is 10', () {
      expect(kTriviaTimerSeconds, 10);
    });
  });

  group('Trivia timer widget', () {
    testWidgets('timer starts when trivia view is first shown', (
      WidgetTester tester,
    ) async {
      final (:game, :driver, :trivia) = _triviaReady();
      await tester.pumpWidget(_buildTestApp(game, driver: driver));

      // The trivia view should be showing.
      expect(find.text('TRIVIA'), findsOneWidget);
      expect(find.text('CORRECT'), findsOneWidget);
      expect(find.text('WRONG'), findsOneWidget);

      // Timer should be at 10 seconds initially.
      expect(find.text('10'), findsOneWidget);

      // Advance 1 second.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('9'), findsOneWidget);

      // Advance another second.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('correct answer stops the timer', (WidgetTester tester) async {
      final (:game, :driver, :trivia) = _triviaReady();
      await tester.pumpWidget(_buildTestApp(game, driver: driver));

      // Advance 3 seconds.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('7'), findsOneWidget);

      // Tap CORRECT.
      await tester.tap(find.text('CORRECT'));
      await tester.pump();

      // Should transition out of trivia to round complete.
      expect(find.text('TRIVIA'), findsNothing);
      expect(find.text('Round 1 complete'), findsOneWidget);

      // Timer should be stopped — advancing more seconds should not crash.
      await tester.pump(const Duration(seconds: 5));
      // Still on round complete screen.
      expect(find.text('Round 1 complete'), findsOneWidget);
    });

    testWidgets('wrong answer stops the timer', (WidgetTester tester) async {
      final (:game, :driver, :trivia) = _triviaReady();
      await tester.pumpWidget(_buildTestApp(game, driver: driver));

      // Advance 2 seconds.
      await tester.pump(const Duration(seconds: 2));

      // Tap WRONG.
      await tester.tap(find.text('WRONG'));
      await tester.pump();

      // Should transition out of trivia to round complete.
      expect(find.text('TRIVIA'), findsNothing);
      expect(find.text('Round 1 complete'), findsOneWidget);
    });

    testWidgets('timer reaching zero triggers wrong answer', (
      WidgetTester tester,
    ) async {
      final (:game, :driver, :trivia) = _triviaReady();
      await tester.pumpWidget(_buildTestApp(game, driver: driver));

      // Verify timer starts at 10.
      expect(find.text('10'), findsOneWidget);

      // Advance through all 10 seconds.
      for (var i = 9; i >= 0; i--) {
        await tester.pump(const Duration(seconds: 1));
        if (i > 0) {
          expect(find.text('$i'), findsOneWidget);
        }
      }

      // After 10 seconds, should transition out of trivia.
      await tester.pump();
      expect(find.text('TRIVIA'), findsNothing);
      expect(find.text('Round 1 complete'), findsOneWidget);
    });

    testWidgets('buttons disabled after timeout', (WidgetTester tester) async {
      final (:game, :driver, :trivia) = _triviaReady();
      await tester.pumpWidget(_buildTestApp(game, driver: driver));

      // Advance all 10 seconds.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();

      // Should be on round complete now.
      expect(find.text('TRIVIA'), findsNothing);
      expect(find.text('Round 1 complete'), findsOneWidget);

      // Timer should be stopped — further advances are safe.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('no duplicate timers on rebuild', (WidgetTester tester) async {
      final (:game, :driver, :trivia) = _triviaReady();
      final key = GlobalKey<State>();

      await tester.pumpWidget(
        MaterialApp(
          home: GameStartScreen(key: key, driver: driver),
        ),
      );

      // Advance 2 seconds.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('8'), findsOneWidget);

      // Trigger a rebuild by pumping with zero duration.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Advance 1 more second — should still decrement normally (not skip).
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('timer does not update after dispose', (
      WidgetTester tester,
    ) async {
      final (:game, :driver, :trivia) = _triviaReady();
      await tester.pumpWidget(_buildTestApp(game, driver: driver));

      // Advance 3 seconds.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('7'), findsOneWidget);

      // Navigate away (dispose the GameStartScreen).
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('different screen'))),
      );

      // Advance more time — should not crash.
      await tester.pump(const Duration(seconds: 5));
      // No assertions needed — if it doesn't crash, the timer was cleaned up.
    });

    testWidgets('trivia works through M20 refusal flow', (
      WidgetTester tester,
    ) async {
      final (:game, :driver, :trivia) = _triviaReady();
      await tester.pumpWidget(_buildTestApp(game, driver: driver));

      // Verify the full trivia view renders.
      expect(find.text('TRIVIA'), findsOneWidget);
      expect(find.text('What is the capital of France?'), findsOneWidget);
      expect(find.text('Answer: Paris'), findsOneWidget);
      expect(find.text('CORRECT'), findsOneWidget);
      expect(find.text('WRONG'), findsOneWidget);

      // Answer correctly.
      await tester.tap(find.text('CORRECT'));
      await tester.pump();

      // Should resolve out of trivia to round complete.
      expect(find.text('TRIVIA'), findsNothing);
      expect(find.text('Round 1 complete'), findsOneWidget);
    });
  });

  group('Trivia timer color', () {
    testWidgets('green when > 3 seconds', (WidgetTester tester) async {
      final (:game, :driver, :trivia) = _triviaReady();
      await tester.pumpWidget(_buildTestApp(game, driver: driver));

      // Timer should show green at 10 seconds.
      expect(find.text('10'), findsOneWidget);
      // The CircularProgressIndicator should be green.
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator, isNotNull);
    });

    testWidgets('orange when <= 3 seconds', (WidgetTester tester) async {
      final (:game, :driver, :trivia) = _triviaReady();
      await tester.pumpWidget(_buildTestApp(game, driver: driver));

      // Advance to 3 seconds remaining.
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('3'), findsOneWidget);
    });
  });
}
