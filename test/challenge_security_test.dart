import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/challenge/challenge_engine.dart';
import 'package:turtle_king/challenge/challenge_state.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';

/// Creates a test player.
Player _p(String id, String name) =>
    Player(id: id, name: name, color: const Color(0xFF000000));

void main() {
  // -------------------------------------------------------------------
  // Security: ChallengeEngine trust boundaries
  // -------------------------------------------------------------------
  group('ChallengeEngine security', () {
    test('challenged player cannot be in eligible list', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      expect(
        () => engine.begin(challengedPlayer: alice, eligiblePlayers: [alice]),
        throwsArgumentError,
      );
    });

    test('empty eligible list is rejected', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      expect(
        () => engine.begin(challengedPlayer: alice, eligiblePlayers: []),
        throwsArgumentError,
      );
    });

    test('only challenger can choose challenge type', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      final carol = _p('c', 'Carol');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();

      final challenger = engine.state!.challenger!;
      final wrongPlayer = challenger.id == bob.id ? carol : bob;
      expect(
        () => engine.chooseChallengeType(ChallengeType.dare, wrongPlayer),
        throwsArgumentError,
      );
    });

    test('concurrent challenges are rejected', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      expect(
        () => engine.begin(challengedPlayer: bob, eligiblePlayers: [alice]),
        throwsStateError,
      );
    });

    test('double resolution is rejected', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      engine.selectChallenger();
      engine.chooseChallengeType(ChallengeType.dare, engine.state!.challenger!);
      engine.resolve(ChallengeResult.challengerPenalty);

      expect(
        () => engine.resolve(ChallengeResult.challengedPenalty),
        throwsStateError,
      );
    });

    test('resolution outside active challenge is rejected', () {
      final engine = ChallengeEngine();
      expect(
        () => engine.resolve(ChallengeResult.challengerPenalty),
        throwsStateError,
      );
    });

    test('selectChallenger outside selection phase is rejected', () {
      final engine = ChallengeEngine();
      expect(() => engine.selectChallenger(), throwsStateError);
    });

    test('chooseChallengeType outside typeSelection phase is rejected', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      // Still in selection phase, not typeSelection
      expect(
        () => engine.chooseChallengeType(ChallengeType.dare, bob),
        throwsStateError,
      );
    });
  });

  // -------------------------------------------------------------------
  // Security: GameState challenge trust boundaries
  // -------------------------------------------------------------------
  group('GameState challenge security', () {
    late GameState game;
    late Player alice;
    late Player bob;
    late Player carol;
    late Player dave;

    setUp(() {
      alice = _p('a', 'Alice');
      bob = _p('b', 'Bob');
      carol = _p('c', 'Carol');
      dave = _p('d', 'Dave');
      game = GameState(players: [alice, bob, carol, dave], random: Random(42));
    });

    void completeRoundToPendingShot(GameState g) {
      for (final _ in g.activePlayers) {
        g.revealCurrentPlayer();
        g.passToNextPlayer();
      }
      final count = g.activePlayerCount;
      for (var i = 0; i < count; i++) {
        g.holdOut(g.pourCurrentPlayer);
      }
      expect(g.shotDecisionPending, isTrue);
    }

    test('wrong player cannot choose challenge type', () {
      completeRoundToPendingShot(game);
      game.refuseShot();
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;

      // Try to choose type with wrong player
      final wrongPlayer = challenger.id == alice.id ? bob : alice;
      expect(
        () => game.chooseChallengeType(ChallengeType.dare, wrongPlayer),
        throwsArgumentError,
      );
    });

    test('challenge cannot resolve twice', () {
      completeRoundToPendingShot(game);
      game.refuseShot();
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.resolveChallenge(ChallengeResult.challengerPenalty);

      expect(
        () => game.resolveChallenge(ChallengeResult.challengedPenalty),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('challenge actions rejected when no active challenge', () {
      expect(
        () => game.selectChallenger(),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.chooseChallengeType(ChallengeType.dare, alice),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.resolveChallenge(ChallengeResult.challengerPenalty),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('penalty applied exactly once', () {
      completeRoundToPendingShot(game);
      game.refuseShot();
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);

      final drinksBefore = game.drinksOf(challenger);
      game.resolveChallenge(ChallengeResult.challengerPenalty);
      final drinksAfter = game.drinksOf(challenger);

      expect(drinksAfter - drinksBefore, 1);
    });

    test('penalty does not trigger another challenge', () {
      completeRoundToPendingShot(game);
      game.refuseShot();
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.resolveChallenge(ChallengeResult.challengerPenalty);

      // After resolution, no challenge should be active
      expect(game.challengeActive, isFalse);
      expect(game.challengeState, isNull);
    });

    test('eligible players always exclude challenged player', () {
      completeRoundToPendingShot(game);
      final owing = game.shotDecisionPlayer!;
      game.refuseShot();

      final eligible = game.eligiblePlayersForChallenge;
      expect(eligible.every((p) => p.id != owing.id), isTrue);
    });

    test('refuseShot with fewer than 4 players is rejected', () {
      final smallGame = GameState(players: [alice, bob], random: Random(42));
      for (final _ in smallGame.activePlayers) {
        smallGame.revealCurrentPlayer();
        smallGame.passToNextPlayer();
      }
      for (var i = 0; i < smallGame.activePlayerCount; i++) {
        smallGame.holdOut(smallGame.pourCurrentPlayer);
      }
      expect(smallGame.shotDecisionPending, isTrue);
      expect(smallGame.canRefuseShot, isFalse);
      expect(
        () => smallGame.refuseShot(),
        throwsA(isA<YamadaRoundException>()),
      );
      // State unchanged after rejection.
      expect(smallGame.shotDecisionPending, isTrue);
      expect(smallGame.challengeActive, isFalse);
    });

    test(
      'refuseShot enters challenge while shotDecisionPending remains true',
      () {
        completeRoundToPendingShot(game);
        final owing = game.shotDecisionPlayer!;
        expect(game.shotDecisionPending, isTrue);
        game.refuseShot();

        // After refuseShot: challenge is active, shotDecisionPending is still
        // true (will be cleared by _advanceShotDecision after challenge resolves),
        // but shotDecisionPlayer is null.
        expect(game.challengeActive, isTrue);
        expect(game.shotDecisionPending, isTrue);
        expect(game.shotDecisionPlayer, isNull);

        // Challenge state has all required values.
        final cs = game.challengeState!;
        expect(cs.challengedPlayer.id, owing.id);
        expect(cs.challenger, isNull); // Not yet selected
        expect(cs.eligiblePlayers.length, game.activePlayerCount - 1);
        expect(cs.eligiblePlayers.every((p) => p.id != owing.id), isTrue);
      },
    );

    test('challenge flows correctly after refuseShot', () {
      completeRoundToPendingShot(game);
      game.refuseShot();
      game.selectChallenger();

      final cs = game.challengeState!;
      expect(cs.challenger, isNotNull);
      expect(cs.phase, ChallengePhase.typeSelection);

      final challenger = cs.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      expect(game.challengeState!.type, ChallengeType.rockPaperScissors);
    });

    test('canRefuseShot is false with 3 players and true with 4', () {
      final threePlayers = GameState(
        players: [alice, bob, carol],
        random: Random(42),
      );
      for (final _ in threePlayers.activePlayers) {
        threePlayers.revealCurrentPlayer();
        threePlayers.passToNextPlayer();
      }
      for (var i = 0; i < threePlayers.activePlayerCount; i++) {
        threePlayers.holdOut(threePlayers.pourCurrentPlayer);
      }
      expect(threePlayers.shotDecisionPending, isTrue);
      expect(threePlayers.canRefuseShot, isFalse);

      // With 4 players, canRefuseShot should be true.
      final fourPlayers = GameState(
        players: [alice, bob, carol, dave],
        random: Random(42),
      );
      for (final _ in fourPlayers.activePlayers) {
        fourPlayers.revealCurrentPlayer();
        fourPlayers.passToNextPlayer();
      }
      for (var i = 0; i < fourPlayers.activePlayerCount; i++) {
        fourPlayers.holdOut(fourPlayers.pourCurrentPlayer);
      }
      expect(fourPlayers.shotDecisionPending, isTrue);
      expect(fourPlayers.canRefuseShot, isTrue);
    });
  });

  // -------------------------------------------------------------------
  // Security: Protocol backward compatibility
  // -------------------------------------------------------------------
  group('Protocol backward compatibility', () {
    test('ChallengeType enum has expected values', () {
      expect(ChallengeType.values.length, 3);
      expect(ChallengeType.dare.name, 'dare');
      expect(ChallengeType.rockPaperScissors.name, 'rockPaperScissors');
      expect(ChallengeType.trivia.name, 'trivia');
    });

    test('ChallengeResult enum has expected values', () {
      expect(ChallengeResult.values.length, 2);
      expect(ChallengeResult.challengerPenalty.name, 'challengerPenalty');
      expect(ChallengeResult.challengedPenalty.name, 'challengedPenalty');
    });

    test('ChallengePhase enum has expected values', () {
      expect(ChallengePhase.values.length, 4);
      expect(ChallengePhase.selection.name, 'selection');
      expect(ChallengePhase.typeSelection.name, 'typeSelection');
      expect(ChallengePhase.inProgress.name, 'inProgress');
      expect(ChallengePhase.resolved.name, 'resolved');
    });
  });
}
