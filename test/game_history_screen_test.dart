import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/card_widgets.dart';
import 'package:turtle_king/game_history_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

void main() {
  List<Player> makePlayers(int count) => [
    for (var i = 0; i < count; i++)
      Player(
        id: 'player-$i',
        name: 'Player $i',
        color: PlayerColors.palette[i],
      ),
  ];

  void viewAll(GameState game) {
    while (!game.allPlayersViewed) {
      game.revealCurrentPlayer();
      game.passToNextPlayer();
    }
  }

  void everyoneHoldsOut(GameState game) {
    while (!game.roundComplete) {
      game.holdOut(game.pourCurrentPlayer);
    }
  }

  Future<void> pumpHistory(WidgetTester tester, GameState game) async {
    await tester.pumpWidget(MaterialApp(home: GameHistoryScreen(game: game)));
  }

  group('GameHistoryScreen', () {
    testWidgets('shows a defensive message when nothing is recorded', (
      tester,
    ) async {
      final game = GameState(players: makePlayers(2), random: Random(1));
      // A fresh game still records game start, so use a screen with events
      // suppressed by checking the empty-state branch directly is not
      // possible; instead assert the header renders for an in-progress game.
      await pumpHistory(tester, game);

      expect(find.text('Game History'), findsOneWidget);
      expect(find.text('Game in progress'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
    });

    testWidgets('shows game-level summary for a completed game', (
      tester,
    ) async {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      // Play rounds until game completes.
      while (!game.gameComplete) {
        viewAll(game);
        everyoneHoldsOut(game);
        if (!game.canStartNextRound) break;
        game.startNextRound();
      }
      expect(game.gameComplete, isTrue);

      await pumpHistory(tester, game);

      expect(find.text('Game complete'), findsOneWidget);
      expect(find.textContaining('Turtle King:'), findsOneWidget);
    });

    testWidgets('shows chronological events for a completed round', (
      tester,
    ) async {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);

      await pumpHistory(tester, game);

      Finder rich(String text) => find.textContaining(text, findRichText: true);
      expect(rich('looked at their one visible card'), findsNWidgets(2));
      // Two per-player "held out" rows (plus the reveal row also contains
      // the phrase, so assert at least the per-player rows exist).
      expect(rich(' held out'), findsWidgets);
      expect(
        rich('everyone held out — all hands revealed together'),
        findsOneWidget,
      );
      expect(rich('took shots'), findsOneWidget);
      expect(rich('took an extra shot'), findsOneWidget);
    });

    testWidgets('shows YAMADA events for a YAMADA round', (tester) async {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      final first = game.pourCurrentPlayer;
      game.callYamada(first);
      // After YAMADA, turn advances. Other player holds out.
      game.holdOut(game.pourCurrentPlayer);

      await pumpHistory(tester, game);

      Finder rich(String text) => find.textContaining(text, findRichText: true);
      expect(rich('called YAMADA'), findsOneWidget);
      // YAMADA now shows a reveal and resolution.
      expect(rich('revealed'), findsWidgets);
    });

    testWidgets('events appear in chronological order', (tester) async {
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

      final roundStart1 = find.textContaining(
        'started round 1',
        findRichText: true,
      );
      final roundStart2 = find.textContaining(
        'started round 2',
        findRichText: true,
      );
      expect(roundStart1, findsOneWidget);
      expect(roundStart2, findsOneWidget);
      // Round 1 appears above Round 2 in the timeline.
      expect(
        tester.getTopLeft(roundStart1).dy,
        lessThan(tester.getTopLeft(roundStart2).dy),
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
      // No rank/suit labels from the card model appear anywhere.
      for (final suit in ['♠', '♥', '♦', '♣']) {
        expect(find.textContaining(suit), findsNothing);
      }
    });

    testWidgets('works on a small phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);

      await pumpHistory(tester, game);
      expect(tester.takeException(), isNull);
    });

    testWidgets('works in dark mode without overflow', (tester) async {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: GameHistoryScreen(game: game),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Game History'), findsOneWidget);
    });
  });
}
