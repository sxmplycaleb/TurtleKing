import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/game_save.dart';
import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/home_screen.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';
import 'package:turtle_king/player_setup_screen.dart';

void main() {
  List<Player> twoPlayers() => [
    Player(id: 'player-1', name: 'Caleb', color: PlayerColors.palette[0]),
    Player(id: 'player-2', name: 'Mina', color: PlayerColors.palette[1]),
  ];

  Future<GameSaveStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return GameSaveStore(prefs);
  }

  /// Views every card so pouring has started (a resumable mid-game state).
  void startPouring(GameState game) {
    while (!game.allPlayersViewed) {
      game.revealCurrentPlayer();
      game.passToNextPlayer();
    }
  }

  Future<void> pumpHome(WidgetTester tester, GameSaveStore store) async {
    await tester.pumpWidget(MaterialApp(home: HomeScreen(saveStore: store)));
  }

  group('HomeScreen resume', () {
    testWidgets('shows no resume card when there is no save', (tester) async {
      final store = await makeStore();
      await pumpHome(tester, store);

      expect(find.text('Resume Game'), findsNothing);
      expect(find.text('Game in progress'), findsNothing);
      expect(find.text('New Game'), findsOneWidget);
    });

    testWidgets('shows Resume Game with safe summary when a save exists', (
      tester,
    ) async {
      final store = await makeStore();
      final game = GameState(players: twoPlayers(), random: Random(1));
      startPouring(game);
      await store.save(game);

      await pumpHome(tester, store);

      expect(find.text('Game in progress'), findsOneWidget);
      expect(find.text('Resume Game'), findsOneWidget);
      // Safe summary only: round, players, cup, current player. No cards.
      expect(find.textContaining('Round 1'), findsOneWidget);
      expect(find.textContaining('2 players'), findsOneWidget);
      expect(find.textContaining('normal cup'), findsOneWidget);
      expect(find.textContaining('to play'), findsOneWidget);
      expect(find.byType(CardFace), findsNothing);
    });

    testWidgets('resuming opens the game at the exact saved stage', (
      tester,
    ) async {
      final store = await makeStore();
      final game = GameState(players: twoPlayers(), random: Random(1));
      startPouring(game);
      await store.save(game);

      await pumpHome(tester, store);
      await tester.tap(find.text('Resume Game'));
      await tester.pumpAndSettle();

      expect(find.byType(GameStartScreen), findsOneWidget);
      // Pouring has started; the first pourer's turn is showing.
      expect(find.textContaining('Water is being poured'), findsOneWidget);
      expect(find.text('YAMADA!'), findsOneWidget);
    });

    testWidgets('New Game clears an existing save', (tester) async {
      final store = await makeStore();
      await store.save(GameState(players: twoPlayers()));
      expect(store.hasSave, isTrue);

      await pumpHome(tester, store);
      await tester.tap(find.text('New Game'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerSetupScreen), findsOneWidget);
      expect(store.hasSave, isFalse);
    });

    testWidgets('a corrupt save offers Discard and recovers', (tester) async {
      final store = await makeStore();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(GameSaveStore.saveKey, 'not-json{{');
      expect(store.hasSave, isTrue);

      await pumpHome(tester, store);

      expect(find.text('Saved game cannot be resumed'), findsOneWidget);
      expect(find.text('Resume Game'), findsNothing);

      await tester.tap(find.text('Discard Save'));
      await tester.pumpAndSettle();

      expect(store.hasSave, isFalse);
      expect(find.text('Saved game cannot be resumed'), findsNothing);
      expect(find.text('New Game'), findsOneWidget);
    });

    testWidgets('a saved-but-completed game is not offered for resume', (
      tester,
    ) async {
      final store = await makeStore();
      final game = GameState(players: twoPlayers(), eliminationThreshold: 2);
      startPouring(game);
      game.callYamada(game.pourCurrentPlayer);
      game.callYamada(game.pourCurrentPlayer);
      expect(game.gameComplete, isTrue);
      await store.save(game);

      await pumpHome(tester, store);

      expect(find.text('Resume Game'), findsNothing);
      expect(store.hasSave, isFalse);
    });
  });

  group('game screen save lifecycle', () {
    Future<GameSaveStore> pumpGame(WidgetTester tester, GameState game) async {
      final store = await makeStore();
      await tester.pumpWidget(
        MaterialApp(
          home: GameStartScreen(game: game, saveStore: store),
        ),
      );
      return store;
    }

    testWidgets('a fresh game is saved as soon as it appears', (tester) async {
      final game = GameState(players: twoPlayers(), random: Random(1));
      final store = await pumpGame(tester, game);
      expect(store.hasSave, isTrue);
    });

    testWidgets('every action keeps the save up to date', (tester) async {
      final game = GameState(players: twoPlayers(), random: Random(1));
      final store = await pumpGame(tester, game);

      await tester.tap(find.text('Reveal My Card'));
      await tester.pump();
      final saved = store.load()!;
      expect(saved.currentPlayerRevealed, isTrue);
    });

    testWidgets('Save & Exit persists the game', (tester) async {
      final game = GameState(players: twoPlayers(), random: Random(1));
      final store = await pumpGame(tester, game);

      await tester.tap(find.byTooltip('Save & Exit'));
      await tester.pumpAndSettle();

      expect(store.hasSave, isTrue);
      final saved = store.load()!;
      expect(saved.roundNumber, game.roundNumber);
    });

    testWidgets('a completed game clears the save', (tester) async {
      final game = GameState(
        players: twoPlayers(),
        random: Random(1),
        eliminationThreshold: 2,
      );
      while (!game.allPlayersViewed) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      // First YAMADA drinks once (1 drink); the caller's turn repeats.
      game.callYamada(game.pourCurrentPlayer);
      final store = await pumpGame(tester, game);
      expect(store.hasSave, isTrue);

      // The second YAMADA reaches the threshold, eliminating the caller and
      // completing the game.
      await tester.ensureVisible(find.text('YAMADA!'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('YAMADA!'));
      await tester.pump();

      expect(game.gameComplete, isTrue);
      expect(store.hasSave, isFalse);
    });

    testWidgets('the game screen never exposes hidden card identities', (
      tester,
    ) async {
      final game = GameState(players: twoPlayers(), random: Random(1));
      final store = await pumpGame(tester, game);

      await tester.tap(find.text('Reveal My Card'));
      await tester.pump();

      // Only the current player's one visible card is face-up; the other is
      // a card back, and the save round-trip changes nothing.
      expect(find.byType(CardFace), findsOneWidget);
      final saved = store.load()!;
      expect(
        saved.visibleCardOf(saved.players[0]).displayName,
        game.visibleCardOf(game.players[0]).displayName,
      );
    });
  });
}
