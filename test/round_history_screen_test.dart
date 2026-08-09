import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_start_screen.dart' show CardFace;
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';
import 'package:turtle_king/round_history_screen.dart';

void main() {
  List<Player> makePlayers(int count) => [
    for (var i = 1; i <= count; i++)
      Player(
        id: 'player-$i',
        name: 'Player $i',
        color: PlayerColors.palette[i - 1],
      ),
  ];

  void viewAll(GameState game) {
    for (var i = 0; i < game.activePlayers.length; i++) {
      game.revealCurrentPlayer();
      game.passToNextPlayer();
    }
  }

  Future<void> pumpHistory(WidgetTester tester, GameState game) async {
    await tester.pumpWidget(MaterialApp(home: RoundHistoryScreen(game: game)));
  }

  group('RoundHistoryScreen', () {
    testWidgets('shows a defensive message when no round has completed', (
      tester,
    ) async {
      final game = GameState(players: makePlayers(2), random: Random(1));
      await pumpHistory(tester, game);

      expect(find.text('Round History'), findsOneWidget);
      expect(find.text('No completed rounds yet.'), findsOneWidget);
    });

    testWidgets('lists completed rounds in chronological order with the '
        'players\' capture and penalty counts', (tester) async {
      // Seed 22: player 1 captures in both rounds; player 2 never does.
      final game = GameState(
        players: makePlayers(2),
        random: Random(22),
        maxRounds: 2,
      );
      for (var round = 0; round < 2; round++) {
        viewAll(game);
        game.startYamadaRound();
        game.callYamada(game.players[0]);
        game.drawToCenter(game.players[1]);
        if (!game.gameComplete) {
          game.startNextRound();
        }
      }
      expect(game.gameComplete, isTrue);
      expect(game.roundResults, hasLength(2));

      await pumpHistory(tester, game);

      expect(find.text('Round 1'), findsOneWidget);
      expect(find.text('Round 2'), findsOneWidget);
      expect(find.text('Player 1: 1 captured · 0 penalty'), findsNWidgets(2));
      expect(find.text('Player 2: 0 captured · 0 penalty'), findsNWidgets(2));
      // The rounds appear in order: Round 1 above Round 2.
      final roundOneY = tester.getTopLeft(find.text('Round 1')).dy;
      final roundTwoY = tester.getTopLeft(find.text('Round 2')).dy;
      expect(roundOneY, lessThan(roundTwoY));
    });

    testWidgets('shows eliminations on the round in which they happened', (
      tester,
    ) async {
      // Seed 1, 1-slot cups, threshold 2: player 1 is eliminated mid-round 2
      // while the game continues to round 3 with the two active players.
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        cupCapacity: 1,
        eliminationThreshold: 2,
      );
      for (var round = 0; round < 3 && !game.gameComplete; round++) {
        viewAll(game);
        game.startYamadaRound();
        if (game.activePlayers.contains(game.players[0])) {
          game.callYamada(game.players[0]); // wrong call while active
        }
        for (final player in game.activePlayers) {
          if (player != game.players[0]) {
            game.drawToCenter(player);
          }
        }
        if (!game.gameComplete) {
          game.startNextRound();
        }
      }
      expect(game.gameComplete, isTrue);
      expect(
        game.eliminationHistory.single.round,
        2,
        reason: 'player 1 is eliminated in round 2',
      );

      await pumpHistory(tester, game);

      expect(find.text('Round 1'), findsOneWidget);
      expect(find.text('Round 2'), findsOneWidget);
      expect(find.text('Round 3'), findsOneWidget);
      expect(find.text('Eliminated: Player 1'), findsOneWidget);
      // The elimination text sits inside the round-2 card, below its header.
      final roundTwoY = tester.getTopLeft(find.text('Round 2')).dy;
      final eliminatedY = tester
          .getTopLeft(find.text('Eliminated: Player 1'))
          .dy;
      expect(roundTwoY, lessThan(eliminatedY));
      // The eliminated player's historical counts are still listed: one
      // penalty in round 1 and one in round 2 (a delta, not the lifetime
      // total), and zero in round 3.
      expect(find.text('Player 1: 0 captured · 1 penalty'), findsNWidgets(2));
      expect(find.text('Player 1: 0 captured · 0 penalty'), findsOneWidget);
    });

    testWidgets('represents zero-capture players and tied scores', (
      tester,
    ) async {
      // Seed 13: player 1 captures round 1, player 2 captures round 2 — the
      // final scores tie, but each round's own captures are what history
      // shows.
      final game = GameState(
        players: makePlayers(2),
        random: Random(13),
        maxRounds: 2,
      );
      for (var round = 0; round < 2; round++) {
        viewAll(game);
        game.startYamadaRound();
        if (round == 0) {
          game.callYamada(game.players[0]);
          game.drawToCenter(game.players[1]);
        } else {
          game.drawToCenter(game.players[0]);
          game.callYamada(game.players[1]);
        }
        if (!game.gameComplete) {
          game.startNextRound();
        }
      }
      expect(game.gameComplete, isTrue);

      await pumpHistory(tester, game);

      // Round 1: Player 1 captured, Player 2 did not. Round 2: the reverse.
      expect(find.text('Player 1: 1 captured · 0 penalty'), findsOneWidget);
      expect(find.text('Player 2: 1 captured · 0 penalty'), findsOneWidget);
      expect(find.text('Player 1: 0 captured · 0 penalty'), findsOneWidget);
      expect(find.text('Player 2: 0 captured · 0 penalty'), findsOneWidget);
    });

    testWidgets('history never shows card widgets or card identities', (
      tester,
    ) async {
      final game = GameState(
        players: makePlayers(2),
        random: Random(22),
        maxRounds: 2,
      );
      for (var round = 0; round < 2; round++) {
        viewAll(game);
        game.startYamadaRound();
        game.callYamada(game.players[0]);
        game.drawToCenter(game.players[1]);
        if (!game.gameComplete) {
          game.startNextRound();
        }
      }
      await pumpHistory(tester, game);

      expect(find.byType(CardFace), findsNothing);
      expect(
        find.textContaining(' of '),
        findsNothing,
        reason: 'card display names look like "Rank of Suit"',
      );
    });

    testWidgets('content scrolls on a small viewport without clipping', (
      tester,
    ) async {
      // Three rounds of three players produce a long, scrollable list.
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        maxRounds: 3,
      );
      for (var round = 0; round < 3; round++) {
        viewAll(game);
        game.startYamadaRound();
        game.drawToCenter(game.players[0]);
        game.drawToCenter(game.players[1]);
        game.drawToCenter(game.players[2]);
        if (!game.gameComplete) {
          game.startNextRound();
        }
      }
      expect(game.gameComplete, isTrue);

      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpHistory(tester, game);
      expect(tester.takeException(), isNull);

      // The last round starts below the fold on a small screen.
      await tester.scrollUntilVisible(
        find.text('Round 3'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Round 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('back navigation returns to the previous screen', (
      tester,
    ) async {
      final game = GameState(players: makePlayers(2), random: Random(22));
      viewAll(game);
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RoundHistoryScreen(game: game),
                    ),
                  ),
                  child: const Text('open history'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open history'));
      await tester.pumpAndSettle();
      expect(find.byType(RoundHistoryScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(RoundHistoryScreen), findsNothing);
      expect(find.text('open history'), findsOneWidget);
    });
  });
}
