import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';
import 'package:turtle_king/round_history_screen.dart';

void main() {
  List<Player> makePlayers(int count) => [
    for (var i = 0; i < count; i++)
      Player(
        id: 'player-$i',
        name: 'Player $i',
        color: PlayerColors.palette[i],
      ),
  ];

  /// Every active player views their one visible card.
  void viewAll(GameState game) {
    while (!game.allPlayersViewed) {
      game.revealCurrentPlayer();
      game.passToNextPlayer();
    }
  }

  /// Every active player holds out until the round completes.
  void everyoneHoldsOut(GameState game) {
    while (!game.roundComplete) {
      game.holdOut(game.pourCurrentPlayer);
    }
  }

  Future<void> pumpHistory(WidgetTester tester, GameState game) async {
    await tester.pumpWidget(MaterialApp(home: RoundHistoryScreen(game: game)));
  }

  group('RoundHistoryScreen', () {
    testWidgets('shows a defensive message when no rounds have completed', (
      tester,
    ) async {
      final game = GameState(players: makePlayers(2), random: Random(1));
      await pumpHistory(tester, game);

      expect(find.text('Round History'), findsOneWidget);
      expect(find.text('No completed rounds yet.'), findsOneWidget);
    });

    testWidgets(
      'shows one completed round with cup size and per-player drinks',
      (tester) async {
        final game = GameState(
          players: makePlayers(2),
          random: Random(1),
          eliminationThreshold: 100,
        );
        viewAll(game);
        everyoneHoldsOut(game);
        expect(game.roundComplete, isTrue);

        await pumpHistory(tester, game);

        expect(find.text('Round 1 — normal cup'), findsOneWidget);
        // Every player is represented, including the zero-drink player.
        expect(find.textContaining('Player 0: '), findsOneWidget);
        expect(find.textContaining('Player 1: '), findsOneWidget);
        expect(find.textContaining('0 drink(s)'), findsWidgets);
        // The smallest hand is marked.
        expect(find.textContaining('smallest hand'), findsOneWidget);
      },
    );

    testWidgets('shows multiple rounds in chronological order', (tester) async {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      game.startNextRound();
      viewAll(game);
      everyoneHoldsOut(game);

      await pumpHistory(tester, game);

      expect(find.text('Round 1 — normal cup'), findsOneWidget);
      expect(find.text('Round 2 — large cup'), findsOneWidget);
      // Round 1 appears before Round 2 in the list.
      final round1Y = tester.getTopLeft(find.text('Round 1 — normal cup')).dy;
      final round2Y = tester.getTopLeft(find.text('Round 2 — large cup')).dy;
      expect(round1Y, lessThan(round2Y));
    });

    testWidgets('marks YAMADA calls and omits the smallest-hand tag', (
      tester,
    ) async {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      final first = game.pourCurrentPlayer;
      game.callYamada(first);
      game.holdOut(first);
      game.holdOut(game.pourCurrentPlayer);
      expect(game.roundComplete, isTrue);

      await pumpHistory(tester, game);

      expect(find.text('Round 1 — normal cup'), findsOneWidget);
      expect(find.textContaining('· YAMADA'), findsOneWidget);
      expect(find.textContaining('smallest hand'), findsNothing);
    });

    testWidgets('shows eliminations associated with the correct round', (
      tester,
    ) async {
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      final players = game.activePlayers;
      game.callYamada(players[0]);
      game.callYamada(players[0]);
      expect(game.isEliminated(players[0]), isTrue);
      game.holdOut(players[1]);
      game.holdOut(players[2]);
      expect(game.roundComplete, isTrue);

      await pumpHistory(tester, game);

      expect(find.text('Round 1 — normal cup'), findsOneWidget);
      expect(find.text('Eliminated: Player 0'), findsOneWidget);
      expect(
        find.textContaining('Player 0: 2 drink(s) · YAMADA'),
        findsOneWidget,
      );
    });

    testWidgets('never reveals card identities', (tester) async {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);

      await pumpHistory(tester, game);

      expect(find.byType(CardFace), findsNothing);
    });
  });
}
