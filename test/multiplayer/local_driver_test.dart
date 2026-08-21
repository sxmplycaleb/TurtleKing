import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/driver.dart';
import 'package:turtle_king/multiplayer/public_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

import 'helpers.dart';

void main() {
  group('LocalDriver', () {
    test('exposes the same GameState instance it wraps', () {
      final game = testGame(2);
      final driver = LocalDriver(game);
      expect(driver.state, same(game));
    });

    test('revealCurrentPlayer forwards to the state', () {
      final driver = LocalDriver(testGame(2));
      expect(driver.state.currentPlayerRevealed, isFalse);
      driver.revealCurrentPlayer();
      expect(driver.state.currentPlayerRevealed, isTrue);
    });

    test('passToNextPlayer advances through viewing into pouring', () {
      final driver = LocalDriver(testGame(2));
      driver.revealCurrentPlayer();
      driver.passToNextPlayer();
      expect(driver.state.currentPlayerIndex, 1);
      driver.revealCurrentPlayer();
      driver.passToNextPlayer();
      expect(driver.state.pouringStarted, isTrue);
      expect(driver.state.pourCurrentPlayer, driver.state.players[0]);
    });

    test('holdOut forwards and advances the pouring turn', () {
      final game = testGame(3);
      viewThrough(game);
      final driver = LocalDriver(game);
      final first = game.pourCurrentPlayer;
      driver.holdOut(first);
      expect(game.pourCurrentPlayer, isNot(same(first)));
      expect(game.currentPlayerIndex, 1);
    });

    test('callYamada records the strategic surrender', () {
      final game = testGame(2);
      viewThrough(game);
      final driver = LocalDriver(game);
      final caller = game.pourCurrentPlayer;
      driver.callYamada(caller);
      // YAMADA is a strategic surrender: no immediate drink or redeal.
      expect(game.calledYamadaThisRound(caller), isTrue);
      expect(game.yamadaCallerThisRound?.id, caller.id);
    });

    test('startNextRound forwards after a completed round', () {
      final game = testGame(3);
      viewThrough(game);
      // Everyone holds out to complete the round.
      while (!game.roundComplete) {
        game.holdOut(game.players[game.pourIndex]);
      }
      final driver = LocalDriver(game);
      final roundBefore = game.roundNumber;
      driver.startNextRound();
      expect(game.roundNumber, roundBefore + 1);
      expect(game.pouringStarted, isFalse);
      expect(game.allPlayersViewed, isFalse);
    });

    test(
      'invalid actions throw the same YamadaRoundException as the state',
      () {
        final game = testGame(2);
        final driver = LocalDriver(game);
        // Pouring actions before pouring starts.
        expect(
          () => driver.holdOut(game.players[0]),
          throwsA(isA<YamadaRoundException>()),
        );
        expect(
          () => driver.callYamada(game.players[0]),
          throwsA(isA<YamadaRoundException>()),
        );
        // State unchanged after a rejected action.
        expect(game.roundComplete, isFalse);
        expect(game.drinksOf(game.players[0]), 0);
      },
    );

    test('turn ownership is enforced by the underlying state', () {
      final game = testGame(3);
      viewThrough(game);
      final driver = LocalDriver(game);
      final wrong = game.players[(game.pourIndex + 1) % game.players.length];
      expect(
        () => driver.holdOut(wrong),
        throwsA(
          isA<YamadaRoundException>().having(
            (e) => e.message,
            'message',
            contains('not ${wrong.name}\'s turn'),
          ),
        ),
      );
    });

    test('eliminated players cannot act through the driver', () {
      final game = GameState(
        players: [
          Player(id: 'p1', name: 'P1', color: PlayerColors.palette[0]),
          Player(id: 'p2', name: 'P2', color: PlayerColors.palette[1]),
          Player(id: 'p3', name: 'P3', color: PlayerColors.palette[2]),
        ],
        random: Random(1),
        eliminationThreshold: 2,
      );
      // Play rounds until someone is eliminated.
      while (!game.gameComplete) {
        viewThrough(game);
        while (!game.roundComplete) {
          game.holdOut(game.pourCurrentPlayer);
        }
        if (game.eliminatedPlayers.isNotEmpty) break;
        if (!game.canStartNextRound) break;
        game.startNextRound();
      }
      final eliminated = game.eliminatedPlayers;
      expect(
        eliminated,
        isNotEmpty,
        reason: 'expected at least one elimination',
      );
      final driver = LocalDriver(game);
      // The eliminated player cannot hold out (rejected at validation).
      expect(
        () => driver.holdOut(eliminated.first),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test(
      'is a thin wrapper: no duplicated rules (state remains authoritative)',
      () {
        // Two identical games (same seed); one is driven exclusively through
        // LocalDriver, the other directly through GameState. Their public
        // states must end up byte-identical, proving the driver is a rule-free
        // wrapper, not a second rules implementation.
        final seeded = testGame(3, seed: 23);
        final driver = LocalDriver(testGame(3, seed: 23));

        void script(GameDriver d) {
          // Two full rounds.
          for (var r = 0; r < 2; r++) {
            for (var i = 0; i < 3; i++) {
              d.revealCurrentPlayer();
              d.passToNextPlayer();
            }
            while (!d.state.roundComplete) {
              d.holdOut(d.state.pourCurrentPlayer);
            }
            if (d.state.canStartNextRound) {
              d.startNextRound();
            }
          }
        }

        void scriptDirect(GameState g) {
          for (var r = 0; r < 2; r++) {
            for (var i = 0; i < 3; i++) {
              g.revealCurrentPlayer();
              g.passToNextPlayer();
            }
            while (!g.roundComplete) {
              g.holdOut(g.pourCurrentPlayer);
            }
            if (g.canStartNextRound) {
              g.startNextRound();
            }
          }
        }

        script(driver);
        scriptDirect(seeded);

        expect(driver.state.roundNumber, seeded.roundNumber);
        expect(driver.state.events.length, seeded.events.length);
        // The strongest check: identical sanitized public state.
        final viaDriver = jsonEncode(
          PublicStateView.fromGame(driver.state).toJson(),
        );
        final viaDirect = jsonEncode(PublicStateView.fromGame(seeded).toJson());
        expect(viaDriver, viaDirect);
      },
    );
  });
}
