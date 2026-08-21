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

    test('wrong player cannot choose challenge type', () {
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.refuseDrink(game.pourCurrentPlayer);
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
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.refuseDrink(game.pourCurrentPlayer);
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
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);

      final drinksBefore = game.drinksOf(challenger);
      game.resolveChallenge(ChallengeResult.challengerPenalty);
      final drinksAfter = game.drinksOf(challenger);

      expect(drinksAfter - drinksBefore, 1);
    });

    test('penalty does not trigger another challenge', () {
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.resolveChallenge(ChallengeResult.challengerPenalty);

      // After resolution, no challenge should be active
      expect(game.challengeActive, isFalse);
      expect(game.challengeState, isNull);
    });

    test('eligible players always exclude challenged player', () {
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      final current = game.pourCurrentPlayer;
      game.refuseDrink(current);

      final eligible = game.eligiblePlayersForChallenge;
      expect(eligible.every((p) => p.id != current.id), isTrue);
    });

    test('refuseDrink with fewer than 3 others does not start challenge', () {
      final smallGame = GameState(players: [alice, bob], random: Random(42));
      for (final _ in smallGame.activePlayers) {
        smallGame.revealCurrentPlayer();
        smallGame.passToNextPlayer();
      }
      final initiated = smallGame.refuseDrink(smallGame.pourCurrentPlayer);
      expect(initiated, isFalse);
      expect(smallGame.challengeActive, isFalse);
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
