import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/card_widgets.dart';
import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/game_table.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

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
    await tester.pumpWidget(MaterialApp(home: GameStartScreen(game: game)));
  }

  Future<void> tapVisible(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pump();
  }

  /// The private-viewing turn for the current viewer: reveal, then pass.
  Future<void> completeViewingTurn(WidgetTester tester) async {
    await tapVisible(tester, 'Reveal My Card');
    await tapVisible(tester, 'Pass to Next Player');
  }

  /// Both players view their one card, then pouring begins.
  Future<void> finishViewing(WidgetTester tester) async {
    await completeViewingTurn(tester);
    await tapVisible(tester, 'Continue');
    await completeViewingTurn(tester);
  }

  /// Plays through a no-YAMADA round so the group reveal is showing.
  Future<void> playToReveal(WidgetTester tester) async {
    await finishViewing(tester);
    await tapVisible(tester, 'Continue');
    await tapVisible(tester, 'Hold out');
    await tapVisible(tester, 'Continue');
    await tapVisible(tester, 'Hold out');
  }

  group('card table presentation', () {
    testWidgets('the game screen sits on the felt table background', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());

      expect(find.byType(GameTableBackground), findsOneWidget);
    });

    testWidgets('ready view shows two hidden card backs and no face cards', (
      tester,
    ) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      expect(find.byType(CardBack), findsNWidgets(2));
      expect(find.byType(CardFace), findsNothing);
    });

    testWidgets('hidden cards expose no identity in semantics', (tester) async {
      final game = gameForTwo();
      final semantics = tester.ensureSemantics();
      await pumpGame(tester, game);

      expect(find.bySemanticsLabel('Card back'), findsNWidgets(2));
      for (final player in game.players) {
        for (final card in game.handOf(player)) {
          expect(find.bySemanticsLabel(card.displayName), findsNothing);
        }
      }

      semantics.dispose();
    });

    testWidgets('revealed view pairs the face-up card with a hidden back', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());

      await tapVisible(tester, 'Reveal My Card');

      expect(find.byType(CardFace), findsOneWidget);
      expect(find.byType(CardBack), findsOneWidget);
    });

    testWidgets('the neutral handoff shows no cards at all', (tester) async {
      await pumpGame(tester, gameForTwo());

      await completeViewingTurn(tester);

      expect(find.byType(CardFace), findsNothing);
      expect(find.byType(CardBack), findsNothing);
    });

    testWidgets(
      'pour turn shows the cup, drinks chip, and a prominent YAMADA action',
      (tester) async {
        await pumpGame(tester, gameForTwo());

        await finishViewing(tester);
        await tapVisible(tester, 'Continue');

        expect(find.byType(TurtleKingCup), findsOneWidget);
        expect(find.text('YAMADA!'), findsOneWidget);
        expect(find.text('Admit defeat — drink the cup'), findsOneWidget);
        expect(find.text('Hold out'), findsOneWidget);
        expect(find.text('Your turn'), findsOneWidget);
        expect(find.textContaining('drinks eliminate'), findsOneWidget);
        // The pourer sees their one card face-up and the hidden back.
        expect(find.byType(CardFace), findsOneWidget);
        expect(find.byType(CardBack), findsOneWidget);
      },
    );

    testWidgets('YAMADA is only offered during the pouring phase', (
      tester,
    ) async {
      await pumpGame(tester, gameForTwo());

      // Before pouring starts there is no YAMADA action anywhere.
      expect(find.text('YAMADA!'), findsNothing);
    });
  });

  group('reveal and results presentation', () {
    testWidgets('the reveal highlights exactly the smallest hand', (
      tester,
    ) async {
      final game = gameForTwo();
      await pumpGame(tester, game);

      await playToReveal(tester);

      // Both hands (2 cards each) are face-up.
      final faces = tester.widgetList<CardFace>(find.byType(CardFace)).toList();
      expect(faces.length, 4);

      // The smallest hand's cards carry the gold highlight.
      final expected = <bool>[];
      for (final player in game.revealedPlayers) {
        for (var i = 0; i < 2; i++) {
          expected.add(game.smallestHands.contains(player));
        }
      }
      expect(faces.map((face) => face.highlighted).toList(), expected);
      expect(expected.any((h) => h), isTrue);
    });

    testWidgets('the final screen shows the crown and the Turtle King', (
      tester,
    ) async {
      final game = gameForTwo(threshold: 2);
      await pumpGame(tester, game);

      await finishViewing(tester);
      await tapVisible(tester, 'Continue');
      await tapVisible(tester, 'YAMADA!');
      await tapVisible(tester, 'Continue');
      await tapVisible(tester, 'YAMADA!');
      await tapVisible(tester, 'Continue');

      expect(find.byType(TurtleKingCrown), findsOneWidget);
      expect(find.text('Game complete'), findsOneWidget);
      expect(find.text('Turtle King: Bob'), findsOneWidget);
      expect(find.text('Round History'), findsOneWidget);
    });

    testWidgets('eliminated players are visually de-emphasized', (
      tester,
    ) async {
      final game = gameForTwo(threshold: 2);
      await pumpGame(tester, game);

      await finishViewing(tester);
      await tapVisible(tester, 'Continue');
      await tapVisible(tester, 'YAMADA!');
      await tapVisible(tester, 'Continue');
      await tapVisible(tester, 'YAMADA!');
      await tapVisible(tester, 'Continue');

      // Caleb was eliminated (2 drinks); his result line is struck through.
      final eliminatedLine = tester.widget<Text>(
        find.text('Caleb: 2 drink(s)'),
      );
      expect(eliminatedLine.style?.decoration, TextDecoration.lineThrough);
    });
  });

  group('responsive layout', () {
    testWidgets('the game flow renders without overflow on a small phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final game = gameForTwo();
      await pumpGame(tester, game);
      expect(tester.takeException(), isNull);

      await tapVisible(tester, 'Reveal My Card');
      expect(tester.takeException(), isNull);
      await tapVisible(tester, 'Pass to Next Player');
      expect(tester.takeException(), isNull);
      await tapVisible(tester, 'Continue');
      expect(tester.takeException(), isNull);
      await tapVisible(tester, 'Reveal My Card');
      expect(tester.takeException(), isNull);
      await tapVisible(tester, 'Pass to Next Player');
      expect(tester.takeException(), isNull);

      // Pouring begins (neutral handoff), then the pour turn with the cup.
      await tapVisible(tester, 'Continue');
      expect(tester.takeException(), isNull);
      expect(find.byType(TurtleKingCup), findsOneWidget);

      // A full reveal round still fits (cards wrap, no overflow).
      await tapVisible(tester, 'Hold out');
      expect(tester.takeException(), isNull);
      await tapVisible(tester, 'Continue');
      expect(tester.takeException(), isNull);
      await tapVisible(tester, 'Hold out');
      expect(tester.takeException(), isNull);
      expect(find.byType(CardFace), findsNWidgets(4));
    });
  });
}
