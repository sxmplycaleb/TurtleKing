import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_history_screen.dart';
import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/home_screen.dart';
import 'package:turtle_king/multiplayer/driver.dart';
import 'package:turtle_king/how_to_play_screen.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';
import 'package:turtle_king/player_setup_screen.dart';
import 'package:turtle_king/round_history_screen.dart';
import 'package:turtle_king/settings.dart';
import 'package:turtle_king/settings_screen.dart';
import 'package:turtle_king/theme.dart';

/// The viewport sizes the app must survive without overflow or clipping.
const List<Size> kAuditSizes = [
  Size(320, 568),
  Size(360, 640),
  Size(375, 667),
  Size(390, 844),
  Size(412, 915),
];

void main() {
  List<Player> makePlayers(int count) => [
    for (var i = 0; i < count; i++)
      Player(
        id: 'player-$i',
        name: 'Player $i',
        color: PlayerColors.palette[i],
      ),
  ];

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// A game with two completed rounds (reveals) for the history screens.
  GameState gameWithHistory() {
    final game = GameState(players: makePlayers(3), random: Random(1));
    for (var round = 0; round < 2; round++) {
      while (!game.allPlayersViewed) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      while (!game.roundComplete) {
        game.holdOut(game.pourCurrentPlayer);
      }
      if (game.canStartNextRound) game.startNextRound();
    }
    return game;
  }

  Future<void> expectNoLayoutException(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
  }

  group('static screens at small viewports', () {
    for (final size in kAuditSizes) {
      testWidgets('home renders at ${size.width}x${size.height}', (
        tester,
      ) async {
        setViewport(tester, size);
        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pump();
        await expectNoLayoutException(tester);
        expect(find.text('New Game'), findsOneWidget);
      });

      testWidgets('settings renders at ${size.width}x${size.height}', (
        tester,
      ) async {
        setViewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: SettingsScope(
              store: SettingsStore.inMemory(),
              child: const SettingsScreen(),
            ),
          ),
        );
        await tester.pump();
        await expectNoLayoutException(tester);
        expect(find.text('Appearance'), findsOneWidget);
      });

      testWidgets('how to play renders at ${size.width}x${size.height}', (
        tester,
      ) async {
        setViewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: const HowToPlayScreen()),
        );
        await tester.pump();
        await expectNoLayoutException(tester);
        expect(find.text('How to Play'), findsOneWidget);
      });

      testWidgets('player setup renders at ${size.width}x${size.height}', (
        tester,
      ) async {
        setViewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: const PlayerSetupScreen()),
        );
        await tester.pump();
        await expectNoLayoutException(tester);
      });

      testWidgets('round history renders at ${size.width}x${size.height}', (
        tester,
      ) async {
        setViewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: RoundHistoryScreen(game: gameWithHistory()),
          ),
        );
        await tester.pump();
        await expectNoLayoutException(tester);
        expect(find.textContaining('Round 1'), findsOneWidget);
      });

      testWidgets('game history renders at ${size.width}x${size.height}', (
        tester,
      ) async {
        setViewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: GameHistoryScreen(game: gameWithHistory()),
          ),
        );
        await tester.pump();
        await expectNoLayoutException(tester);
      });
    }
  });

  group('game screen at small viewports', () {
    testWidgets('a full game plays through without overflow at 320x568', (
      tester,
    ) async {
      setViewport(tester, const Size(320, 568));
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 2,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: GameStartScreen(driver: LocalDriver(game)),
        ),
      );
      await tester.pump();
      await expectNoLayoutException(tester);

      Future<void> tapVisible(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pump();
        await expectNoLayoutException(tester);
      }

      // Viewing phase for all three players.
      for (var i = 0; i < 3; i++) {
        await tapVisible('Reveal My Card');
        await tapVisible('Pass to Next Player');
        if (find.text('Continue').evaluate().isNotEmpty) {
          await tapVisible('Continue');
        }
      }

      // Pouring: hold out to complete rounds until the game ends.
      while (!game.gameComplete) {
        await tapVisible('Hold out');
        if (find.text('Continue').evaluate().isNotEmpty) {
          await tapVisible('Continue');
        }
        if (find.text('Pass the phone').evaluate().isNotEmpty) {
          await tapVisible('Continue');
        }
        if (find.text('Start Next Round').evaluate().isNotEmpty) {
          await tapVisible('Start Next Round');
          // Viewing phase for remaining players after round restart.
          while (!game.pouringStarted && !game.gameComplete) {
            if (find.text('Reveal My Card').evaluate().isNotEmpty) {
              await tapVisible('Reveal My Card');
            }
            if (find.text('Pass to Next Player').evaluate().isNotEmpty) {
              await tapVisible('Pass to Next Player');
            }
            if (find.text('Continue').evaluate().isNotEmpty) {
              await tapVisible('Continue');
            }
          }
        }
      }

      await expectNoLayoutException(tester);
      expect(find.text('Turtle King'), findsWidgets);
    });

    testWidgets('the game screen renders at every audit size', (tester) async {
      final game = GameState(players: makePlayers(3), random: Random(1));
      for (final size in kAuditSizes) {
        setViewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: GameStartScreen(driver: LocalDriver(game)),
          ),
        );
        await tester.pump();
        await expectNoLayoutException(tester);
        expect(find.text('Reveal My Card'), findsOneWidget);
      }
    });
  });
}
