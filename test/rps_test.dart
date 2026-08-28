import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/challenge/challenge_engine.dart';
import 'package:turtle_king/challenge/challenge_state.dart';
import 'package:turtle_king/challenge/rps_state.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/driver.dart';
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

  /// Fast-forwards through the viewing phase so the pouring phase begins.
  void viewAll(GameState game) {
    while (!game.pouringStarted) {
      game.revealCurrentPlayer();
      game.passToNextPlayer();
    }
  }

  /// Completes viewing + round via holdOut to create pending shot, then refuses.
  void completeRoundAndRefuse(GameState game) {
    viewAll(game);
    for (var i = 0; i < game.activePlayerCount; i++) {
      game.holdOut(game.pourCurrentPlayer);
    }
    expect(game.shotDecisionPending, isTrue);
    game.refuseShot();
  }

  group('RpsState', () {
    test('initial state is correct', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);

      final state = RpsState(challengedPlayer: alice, challenger: bob);

      expect(state.currentRound, 1);
      expect(state.isMatchComplete, isFalse);
      expect(state.isInProgress, isTrue);
      expect(state.isInSuddenDeath, isFalse);
      expect(state.resolved, isFalse);
      expect(state.readyToResolve, isFalse);
      expect(state.roundResults, isEmpty);
      expect(state.winner, isNull);
      expect(state.loser, isNull);
    });

    test('match completes when a player reaches 2 wins', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);

      var state = RpsState(challengedPlayer: alice, challenger: bob);

      // Round 1: challenger wins
      state = state.copyWith(
        roundResults: [
          RpsRoundResult(
            roundNumber: 1,
            outcome: RpsRoundOutcome.challengerWon,
          ),
        ],
      );
      expect(state.isMatchComplete, isFalse);

      // Round 2: challenger wins (2-0)
      state = state.copyWith(
        roundResults: [
          ...state.roundResults,
          RpsRoundResult(
            roundNumber: 2,
            outcome: RpsRoundOutcome.challengerWon,
          ),
        ],
      );
      expect(state.isMatchComplete, isTrue);
      expect(state.winner, bob);
      expect(state.loser, alice);
    });

    test('readyToResolve requires a winner', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);

      var state = RpsState(challengedPlayer: alice, challenger: bob);

      // Add 3 rounds with 1-1 and a draw (no winner yet)
      state = state.copyWith(
        roundResults: [
          RpsRoundResult(
            roundNumber: 1,
            outcome: RpsRoundOutcome.challengerWon,
          ),
          RpsRoundResult(
            roundNumber: 2,
            outcome: RpsRoundOutcome.challengedPlayerWon,
          ),
          RpsRoundResult(roundNumber: 3, outcome: RpsRoundOutcome.draw),
        ],
      );

      // No winner yet — match is not complete
      expect(state.isMatchComplete, isFalse);
      expect(state.readyToResolve, isFalse);
      expect(state.isInSuddenDeath, isTrue);
    });

    test('copyWith preserves other fields', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);

      final state = RpsState(challengedPlayer: alice, challenger: bob);
      final updated = state.copyWith(resolved: true);

      expect(updated.challengedPlayer, alice);
      expect(updated.challenger, bob);
      expect(updated.resolved, isTrue);
    });
  });

  group('ChallengeEngine RPS', () {
    test('startRps creates RPS state', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final carol = Player(
        id: 'c',
        name: 'Carol',
        color: PlayerColors.palette[2],
      );

      final engine = ChallengeEngine(random: Random(0));
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      engine.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);

      final rps = engine.startRps();
      expect(rps, isNotNull);
      expect(rps.challengedPlayer, alice);
      expect(rps.challenger, challenger);
      expect(engine.state!.rpsState, rps);
    });

    test('recordRpsRound validates round number', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final carol = Player(
        id: 'c',
        name: 'Carol',
        color: PlayerColors.palette[2],
      );

      final engine = ChallengeEngine(random: Random(0));
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      engine.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      engine.startRps();

      // Round 1 is expected - trying round 2 should throw StateError
      expect(
        () => engine.recordRpsRound(2, RpsRoundOutcome.draw),
        throwsA(isA<StateError>()),
      );

      // Round 1 works
      engine.recordRpsRound(1, RpsRoundOutcome.draw);
      expect(engine.state!.rpsState!.currentRound, 2);
    });

    test('match ends immediately when a player reaches 2 wins', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final carol = Player(
        id: 'c',
        name: 'Carol',
        color: PlayerColors.palette[2],
      );

      final engine = ChallengeEngine(random: Random(0));
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      engine.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      engine.startRps();

      // Round 1: challenger wins
      engine.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      expect(engine.state!.rpsState!.isMatchComplete, isFalse);

      // Round 2: challenger wins (2-0)
      engine.recordRpsRound(2, RpsRoundOutcome.challengerWon);
      expect(engine.state!.rpsState!.isMatchComplete, isTrue);
      expect(engine.state!.rpsState!.winner, challenger);

      // Cannot record round 3 because match is complete
      expect(
        () => engine.recordRpsRound(3, RpsRoundOutcome.draw),
        throwsA(isA<StateError>()),
      );
    });

    test('resolveRps validates result matches winner', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final carol = Player(
        id: 'c',
        name: 'Carol',
        color: PlayerColors.palette[2],
      );

      final engine = ChallengeEngine(random: Random(0));
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      engine.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      engine.startRps();

      // 2-0 challenger wins
      engine.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      engine.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      // Resolve with challenger taking the penalty (wrong — challenger won)
      expect(
        () => engine.resolveRps(ChallengeResult.challengerPenalty),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('resolveRps works with correct result', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final carol = Player(
        id: 'c',
        name: 'Carol',
        color: PlayerColors.palette[2],
      );

      final engine = ChallengeEngine(random: Random(0));
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      engine.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      engine.startRps();

      // 2-0 challenger wins → challenged player (alice) takes the penalty
      engine.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      engine.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      final result = engine.resolveRps(ChallengeResult.challengedPenalty);
      expect(result.resolved, isTrue);
      expect(result.penaltyRecipient, alice);
    });
  });

  group('GameState RPS', () {
    test('startRps creates RPS state in game', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);

      final rps = game.startRps();
      expect(rps, isNotNull);
      expect(game.rpsState, rps);
    });

    test('match completes with 2-0', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      expect(game.rpsState!.isMatchComplete, isTrue);
      expect(game.rpsState!.winner, challenger);
    });

    test('resolveRps applies penalty and returns to normal flow', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      // 2-0 challenger wins
      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      final challenged = game.challengeState!.challengedPlayer;
      game.resolveRps(ChallengeResult.challengedPenalty);

      expect(game.challengeActive, isFalse);
      expect(game.drinksOf(challenged), 1);
    });

    test('resolveRps rejects if match not complete', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      // Only 1 round recorded — not complete
      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);

      expect(
        () => game.resolveRps(ChallengeResult.challengedPenalty),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('cannot record round after match is complete', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      // 2-0
      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      // Try to record round 3 — should throw (match complete)
      expect(
        () => game.recordRpsRound(3, RpsRoundOutcome.draw),
        throwsA(anyOf(isA<YamadaRoundException>(), isA<StateError>())),
      );
    });

    test('cannot record same round twice', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.draw);

      expect(
        () => game.recordRpsRound(1, RpsRoundOutcome.draw),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Sudden Death', () {
    test('1-1 after 2 rounds enters sudden death', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengedPlayerWon);

      expect(game.rpsState!.isMatchComplete, isFalse);
      expect(game.rpsState!.isInSuddenDeath, isFalse);
    });

    test('1-1 after 3 rounds with round 3 draw enters sudden death', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengedPlayerWon);
      game.recordRpsRound(3, RpsRoundOutcome.draw);

      expect(game.rpsState!.isMatchComplete, isFalse);
      expect(game.rpsState!.isInSuddenDeath, isTrue);
      expect(game.rpsState!.currentRound, 4);
    });

    test('sudden death round 4 decisive result resolves', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengedPlayerWon);
      game.recordRpsRound(3, RpsRoundOutcome.draw);

      // Round 4: challenger wins
      game.recordRpsRound(4, RpsRoundOutcome.challengerWon);

      expect(game.rpsState!.isMatchComplete, isTrue);
      expect(game.rpsState!.winner, challenger);
    });

    test('sudden death continues after round 4 draw', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengedPlayerWon);
      game.recordRpsRound(3, RpsRoundOutcome.draw);

      // Round 4: draw
      game.recordRpsRound(4, RpsRoundOutcome.draw);

      expect(game.rpsState!.isMatchComplete, isFalse);
      expect(game.rpsState!.isInSuddenDeath, isTrue);
      expect(game.rpsState!.currentRound, 5);
    });

    test('multiple consecutive sudden-death draws work', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengedPlayerWon);
      game.recordRpsRound(3, RpsRoundOutcome.draw);
      game.recordRpsRound(4, RpsRoundOutcome.draw);
      game.recordRpsRound(5, RpsRoundOutcome.draw);
      game.recordRpsRound(6, RpsRoundOutcome.draw);

      expect(game.rpsState!.isMatchComplete, isFalse);
      expect(game.rpsState!.isInSuddenDeath, isTrue);
      expect(game.rpsState!.currentRound, 7);
    });

    test('no manual loser selection needed', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      // 1-1 with round 3 draw
      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengedPlayerWon);
      game.recordRpsRound(3, RpsRoundOutcome.draw);

      // Match should NOT be complete yet (no winner)
      expect(game.rpsState!.isMatchComplete, isFalse);

      // Round 4: challenger wins
      game.recordRpsRound(4, RpsRoundOutcome.challengerWon);

      // Now match IS complete
      expect(game.rpsState!.isMatchComplete, isTrue);
      expect(game.rpsState!.winner, challenger);
      expect(game.rpsState!.loser, game.challengeState!.challengedPlayer);
    });
  });

  group('RPS penalty', () {
    test('winner receives 0 shots', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      // 2-0 challenger wins
      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      final challenged = game.challengeState!.challengedPlayer;
      game.resolveRps(ChallengeResult.challengedPenalty);

      expect(game.drinksOf(challenger), 0);
      expect(game.drinksOf(challenged), 1);
    });

    test('penalty applied exactly once', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      final challenged = game.challengeState!.challengedPlayer;
      game.resolveRps(ChallengeResult.challengedPenalty);

      expect(game.drinksOf(challenged), 1);
      expect(game.challengeActive, isFalse);

      // Cannot resolve again
      expect(
        () => game.resolveRps(ChallengeResult.challengedPenalty),
        throwsA(isA<YamadaRoundException>()),
      );
    });
  });

  group('RPS loop prevention', () {
    test('cannot start another challenge during RPS', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      // No shot pending during active challenge — refuseShot throws.
      expect(() => game.refuseShot(), throwsA(isA<YamadaRoundException>()));
    });

    test('resolved RPS cannot be resolved again', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      game.resolveRps(ChallengeResult.challengedPenalty);

      expect(
        () => game.resolveRps(ChallengeResult.challengerPenalty),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('RPS cannot trigger Dare', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      expect(() => game.drawDare(), throwsA(isA<YamadaRoundException>()));
    });
  });

  group('RPS game history', () {
    test('RPS events are recorded', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      completeRoundAndRefuse(game);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      game.startRps();

      game.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      game.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      game.resolveRps(ChallengeResult.challengedPenalty);

      final events = game.events;
      expect(events.any((e) => e.type == GameEventType.rpsStarted), isTrue);
      expect(
        events.any((e) => e.type == GameEventType.rpsRoundRecorded),
        isTrue,
      );
      expect(events.any((e) => e.type == GameEventType.rpsResolved), isTrue);
      expect(
        events.any((e) => e.type == GameEventType.challengePenalty),
        isTrue,
      );
    });
  });

  group('LocalDriver RPS', () {
    test('startRps delegates to GameState', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      final driver = LocalDriver(game);
      viewAll(game);
      for (var i = 0; i < game.activePlayerCount; i++) {
        driver.holdOut(game.pourCurrentPlayer);
      }
      expect(game.shotDecisionPending, isTrue);
      driver.refuseShot();
      driver.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      driver.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);

      final rps = driver.startRps();
      expect(rps, isNotNull);
      expect(game.rpsState, rps);
    });

    test('recordRpsRound delegates to GameState', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      final driver = LocalDriver(game);
      viewAll(game);
      for (var i = 0; i < game.activePlayerCount; i++) {
        driver.holdOut(game.pourCurrentPlayer);
      }
      expect(game.shotDecisionPending, isTrue);
      driver.refuseShot();
      driver.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      driver.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      driver.startRps();

      driver.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      expect(game.rpsState!.roundResults.length, 1);
    });

    test('resolveRps delegates to GameState', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      final driver = LocalDriver(game);
      viewAll(game);
      for (var i = 0; i < game.activePlayerCount; i++) {
        driver.holdOut(game.pourCurrentPlayer);
      }
      expect(game.shotDecisionPending, isTrue);
      driver.refuseShot();
      driver.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      driver.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      driver.startRps();

      driver.recordRpsRound(1, RpsRoundOutcome.challengerWon);
      driver.recordRpsRound(2, RpsRoundOutcome.challengerWon);

      final challenged = game.challengeState!.challengedPlayer;
      driver.resolveRps(ChallengeResult.challengedPenalty);

      expect(game.challengeActive, isFalse);
      expect(game.drinksOf(challenged), 1);
    });
  });
}
