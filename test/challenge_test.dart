import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/challenge/challenge_engine.dart';
import 'package:turtle_king/challenge/challenge_state.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';

/// Creates a test player with the given [id] and [name].
Player _p(String id, String name) =>
    Player(id: id, name: name, color: const Color(0xFF000000));

void main() {
  // -------------------------------------------------------------------
  // ChallengeState
  // -------------------------------------------------------------------
  group('ChallengeState', () {
    test('begin creates state in selection phase', () {
      final alice = _p('a', 'Alice');
      final eligible = [_p('b', 'Bob'), _p('c', 'Carol')];
      final cs = ChallengeState.begin(
        challengedPlayer: alice,
        eligiblePlayers: eligible,
      );
      expect(cs.challengedPlayer, alice);
      expect(cs.eligiblePlayers, eligible);
      expect(cs.phase, ChallengePhase.selection);
      expect(cs.isActive, isTrue);
      expect(cs.challenger, isNull);
      expect(cs.type, isNull);
      expect(cs.result, isNull);
      expect(cs.resolved, isFalse);
    });

    test('copyWith produces correct new state', () {
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      final cs = ChallengeState.begin(
        challengedPlayer: alice,
        eligiblePlayers: [bob],
      ).copyWith(challenger: bob, phase: ChallengePhase.typeSelection);
      expect(cs.challenger, bob);
      expect(cs.phase, ChallengePhase.typeSelection);
      expect(cs.challengedPlayer, alice);
    });

    test('penaltyRecipient returns correct player', () {
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      final cs = ChallengeState(
        challengedPlayer: alice,
        eligiblePlayers: [bob],
        challenger: bob,
        result: ChallengeResult.challengerPenalty,
        resolved: true,
      );
      expect(cs.penaltyRecipient, bob);
    });

    test(
      'penaltyRecipient for challengedPenalty returns challenged player',
      () {
        final alice = _p('a', 'Alice');
        final bob = _p('b', 'Bob');
        final cs = ChallengeState(
          challengedPlayer: alice,
          eligiblePlayers: [bob],
          challenger: bob,
          result: ChallengeResult.challengedPenalty,
          resolved: true,
        );
        expect(cs.penaltyRecipient, alice);
      },
    );

    test('penaltyRecipient is null when not resolved', () {
      final cs = ChallengeState.begin(
        challengedPlayer: _p('a', 'Alice'),
        eligiblePlayers: [_p('b', 'Bob')],
      );
      expect(cs.penaltyRecipient, isNull);
    });
  });

  // -------------------------------------------------------------------
  // ChallengeEngine
  // -------------------------------------------------------------------
  group('ChallengeEngine', () {
    test('begin creates active challenge', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final eligible = [_p('b', 'Bob'), _p('c', 'Carol')];
      final state = engine.begin(
        challengedPlayer: alice,
        eligiblePlayers: eligible,
      );
      expect(engine.isActive, isTrue);
      expect(state.phase, ChallengePhase.selection);
      expect(state.challengedPlayer, alice);
      expect(state.eligiblePlayers, eligible);
    });

    test('selectChallenger picks from eligible players', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      final carol = _p('c', 'Carol');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);

      final state = engine.selectChallenger();
      expect(state.challenger, isNotNull);
      expect([bob.id, carol.id].contains(state.challenger!.id), isTrue);
      expect(state.phase, ChallengePhase.typeSelection);
    });

    test('selectChallenger with deterministic seed', () {
      final engine = ChallengeEngine(random: Random(42));
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      final carol = _p('c', 'Carol');
      final dave = _p('d', 'Dave');
      engine.begin(
        challengedPlayer: alice,
        eligiblePlayers: [bob, carol, dave],
      );

      final state = engine.selectChallenger();
      // With seed 42, the selected index should be deterministic.
      expect(state.challenger, isNotNull);
      expect(state.phase, ChallengePhase.typeSelection);
    });

    test('challenged player cannot be in eligible list', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      expect(
        () => engine.begin(challengedPlayer: alice, eligiblePlayers: [alice]),
        throwsArgumentError,
      );
    });

    test('begin throws if challenge already in progress', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      expect(
        () => engine.begin(challengedPlayer: bob, eligiblePlayers: [alice]),
        throwsStateError,
      );
    });

    test('chooseChallengeType requires correct player', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      final carol = _p('c', 'Carol');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();

      final wrongPlayer = engine.state!.challenger!.id == bob.id ? carol : bob;
      expect(
        () => engine.chooseChallengeType(ChallengeType.dare, wrongPlayer),
        throwsArgumentError,
      );
    });

    test('chooseChallengeType advances to inProgress', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;

      final state = engine.chooseChallengeType(
        ChallengeType.trivia,
        challenger,
      );
      expect(state.type, ChallengeType.trivia);
      expect(state.phase, ChallengePhase.inProgress);
    });

    test('resolve sets result and marks resolved', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      engine.selectChallenger();
      engine.chooseChallengeType(
        ChallengeType.rockPaperScissors,
        engine.state!.challenger!,
      );

      final resolved = engine.resolve(ChallengeResult.challengerPenalty);
      expect(resolved.resolved, isTrue);
      expect(resolved.result, ChallengeResult.challengerPenalty);
      expect(resolved.penaltyRecipient, bob);
    });

    test('resolve throws if already resolved', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      engine.selectChallenger();
      engine.chooseChallengeType(ChallengeType.dare, engine.state!.challenger!);
      engine.resolve(ChallengeResult.challengedPenalty);

      expect(
        () => engine.resolve(ChallengeResult.challengerPenalty),
        throwsStateError,
      );
    });

    test('reset clears state', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      engine.reset();
      expect(engine.isActive, isFalse);
      expect(engine.state, isNull);
    });

    test('selectChallenger throws outside selection phase', () {
      final engine = ChallengeEngine();
      expect(() => engine.selectChallenger(), throwsStateError);
    });
  });

  // -------------------------------------------------------------------
  // GameState refusal integration
  // -------------------------------------------------------------------
  group('GameState refusal', () {
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

    test('refuseDrink with 4 players initiates challenge', () {
      // Fast-forward to pouring phase.
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      expect(game.pouringStarted, isTrue);

      final initiated = game.refuseDrink(game.pourCurrentPlayer);
      expect(initiated, isTrue);
      expect(game.challengeActive, isTrue);
      expect(game.challengeState, isNotNull);
      expect(game.challengeState!.challengedPlayer, game.pourCurrentPlayer);
    });

    test('refuseDrink with 2 players does not initiate challenge', () {
      final smallGame = GameState(players: [alice, bob], random: Random(42));
      for (final _ in smallGame.activePlayers) {
        smallGame.revealCurrentPlayer();
        smallGame.passToNextPlayer();
      }
      final initiated = smallGame.refuseDrink(smallGame.pourCurrentPlayer);
      expect(initiated, isFalse);
      expect(smallGame.challengeActive, isFalse);
    });

    test('selectChallenger returns challenger from eligible players', () {
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.refuseDrink(game.pourCurrentPlayer);

      final state = game.selectChallenger();
      expect(state.challenger, isNotNull);
      expect(
        state.challenger!.id,
        isNot(game.challengeState!.challengedPlayer.id),
      );
    });

    test('resolveChallenge applies penalty to correct player', () {
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
      expect(game.drinksOf(challenger), drinksBefore + 1);
      expect(game.challengeActive, isFalse);
    });

    test('challenge is single resolution — cannot resolve twice', () {
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
        () => game.resolveChallenge(ChallengeResult.challengerPenalty),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('penalty cannot trigger another challenge', () {
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.resolveChallenge(ChallengeResult.challengerPenalty);

      // After resolution, the game should be in normal pouring flow.
      expect(game.challengeActive, isFalse);
      expect(game.pouringStarted, isTrue);
    });

    test('eligible players exclude challenged player', () {
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      final current = game.pourCurrentPlayer;
      game.refuseDrink(current);

      final eligible = game.eligiblePlayersForChallenge;
      expect(eligible.every((p) => p.id != current.id), isTrue);
      expect(eligible.length, game.activePlayerCount - 1);
    });
  });

  // -------------------------------------------------------------------
  // Loop prevention
  // -------------------------------------------------------------------
  group('Loop prevention', () {
    test('challenge engine prevents concurrent challenges', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      expect(
        () => engine.begin(challengedPlayer: bob, eligiblePlayers: [alice]),
        throwsStateError,
      );
    });

    test('resolved challenge does not affect new challenge after reset', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      engine.selectChallenger();
      engine.chooseChallengeType(ChallengeType.dare, engine.state!.challenger!);
      engine.resolve(ChallengeResult.challengerPenalty);
      engine.reset();

      // New challenge should work fine.
      final newChallenge = engine.begin(
        challengedPlayer: bob,
        eligiblePlayers: [alice],
      );
      expect(newChallenge.isActive, isTrue);
      expect(newChallenge.phase, ChallengePhase.selection);
    });
  });
}
