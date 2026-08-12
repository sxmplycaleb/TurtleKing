import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/driver.dart';
import 'package:turtle_king/multiplayer/public_state.dart';

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

    test('callYamada forwards the drink and redeal', () {
      final game = testGame(2);
      viewThrough(game);
      final driver = LocalDriver(game);
      final caller = game.pourCurrentPlayer;
      final drinksBefore = game.drinksOf(caller);
      final deckBefore = game.remainingCards;
      driver.callYamada(caller);
      expect(game.drinksOf(caller), drinksBefore + 1);
      expect(game.remainingCards, deckBefore - 2); // two new cards dealt
      expect(game.calledYamadaThisRound(caller), isTrue);
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
      // Three players so elimination does not end the whole game (with two
      // players the game completes first and the action is rejected as
      // "already complete", not "eliminated").
      final game = testGame(3);
      viewThrough(game);
      final p0 = game.players[0];
      // Drive p0 to elimination with six YAMADA calls.
      for (var i = 0; i < 6; i++) {
        game.callYamada(p0);
      }
      expect(game.isEliminated(p0), isTrue);
      expect(game.gameComplete, isFalse);
      final driver = LocalDriver(game);
      expect(
        () => driver.holdOut(p0),
        throwsA(
          isA<YamadaRoundException>().having(
            (e) => e.message,
            'message',
            contains('eliminated'),
          ),
        ),
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
          for (var i = 0; i < 3; i++) {
            d.revealCurrentPlayer();
            d.passToNextPlayer();
          }
          // YAMADA repeats the caller's turn, so the round completes with
          // three consecutive holds: p0, p1, p2.
          d.callYamada(d.state.players[0]);
          d.holdOut(d.state.players[0]);
          d.holdOut(d.state.players[1]);
          d.holdOut(d.state.players[2]);
          if (d.state.canStartNextRound) {
            d.startNextRound();
          }
        }

        void scriptDirect(GameState g) {
          for (var i = 0; i < 3; i++) {
            g.revealCurrentPlayer();
            g.passToNextPlayer();
          }
          g.callYamada(g.players[0]);
          g.holdOut(g.players[0]);
          g.holdOut(g.players[1]);
          g.holdOut(g.players[2]);
          if (g.canStartNextRound) {
            g.startNextRound();
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
