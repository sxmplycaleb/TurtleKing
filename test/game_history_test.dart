import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

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

  /// Every active player views their one visible card.
  void viewAll(GameState game) {
    while (!game.allPlayersViewed) {
      game.revealCurrentPlayer();
      game.passToNextPlayer();
    }
  }

  /// Every active player holds out once, then resolves pending shots.
  void everyoneHoldsOut(GameState game) {
    final count = game.activePlayerCount;
    for (var i = 0; i < count; i++) {
      game.holdOut(game.pourCurrentPlayer);
    }
    while (game.shotDecisionPending) {
      game.takeShot();
    }
  }

  List<GameEventType> types(GameState game) => [
    for (final event in game.events) event.type,
  ];

  group('game event log', () {
    test('records game start, round start and the first deal', () {
      final game = GameState(players: makePlayers(2), random: Random(1));

      expect(types(game).take(3), [
        GameEventType.gameStarted,
        GameEventType.roundStarted,
        GameEventType.cardsDealt,
      ]);
      expect(game.events.first.round, 0);
      expect(game.events[1].round, 1);
      expect(game.events[2].round, 1);
      // The deal event names the players, never any card.
      expect(game.events[2].players, hasLength(2));
    });

    test('events are immutable and ordered', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      final snapshot = game.events;
      viewAll(game);
      everyoneHoldsOut(game);

      // The snapshot is unmodifiable and the live list only grows.
      expect(() => snapshot.add(snapshot.first), throwsUnsupportedError);
      expect(game.events.length, greaterThan(snapshot.length));
    });

    test('viewing and handoff are recorded in order', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      viewAll(game);

      final log = types(game);
      final viewed = log.where((t) => t == GameEventType.playerViewed);
      final handoffs = log.where((t) => t == GameEventType.handoff);
      expect(viewed, hasLength(2));
      expect(handoffs, hasLength(2));
      expect(log, contains(GameEventType.pouringStarted));
      expect(log.last, GameEventType.pouringStarted);
    });

    test('each player looked at their own card', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      final seen = <String>[];
      while (!game.allPlayersViewed) {
        final viewer = game.currentPlayer;
        game.revealCurrentPlayer();
        seen.add(viewer.id);
        game.passToNextPlayer();
      }

      final viewedEvents = game.events
          .where((e) => e.type == GameEventType.playerViewed)
          .toList();
      expect([for (final e in viewedEvents) e.player!.id], seen);
    });

    test('a hold-out round records reveal, smallest, shot-taken and '
        'round completion', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);

      final log = types(game);
      expect(log, contains(GameEventType.revealOccurred));
      expect(log, contains(GameEventType.smallestDetermined));
      // M20: single flat 1-shot penalty recorded as shotTaken.
      final shots = log.where((t) => t == GameEventType.shotTaken);
      expect(shots, hasLength(1));
      expect(log, contains(GameEventType.roundResult));
      expect(log, contains(GameEventType.roundCompleted));
    });

    test('a YAMADA round records the call and a reveal with resolution', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      final first = game.pourCurrentPlayer;
      game.callYamada(first);
      game.holdOut(game.pourCurrentPlayer);

      // M20: if YAMADA is wrong, pending shot must be resolved first.
      while (game.shotDecisionPending) {
        game.takeShot();
      }

      final log = types(game);
      expect(log, contains(GameEventType.playerCalledYamada));
      expect(log, contains(GameEventType.roundCompleted));
      // YAMADA rounds now show a reveal and resolution.
      expect(log, contains(GameEventType.revealOccurred));
    });

    test('the YAMADA event carries the caller and the cup in effect', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      final first = game.pourCurrentPlayer;
      game.callYamada(first);

      final call = game.events.firstWhere(
        (e) => e.type == GameEventType.playerCalledYamada,
      );
      expect(call.player, first);
      expect(call.cupSize, CupSize.normal);
    });

    test('reaching six drinks records exactly one elimination', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 6,
      );
      // Play rounds until first player reaches 6 drinks.
      while (game.drinksOf(game.activePlayers.first) < 6 &&
          !game.gameComplete) {
        viewAll(game);
        everyoneHoldsOut(game);
        if (!game.canStartNextRound) break;
        game.startNextRound();
      }

      final eliminations = game.events
          .where((e) => e.type == GameEventType.playerEliminated)
          .toList();
      expect(eliminations, hasLength(1));
    });

    test('ties: every tied smallest player receives a shot-taken event', () {
      // A seeded game where two players tie for the smallest hand.
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);

      final smallest = game.smallestHands;
      // M20: each tied player gets one flat 1-shot penalty.
      final shots = game.events
          .where((e) => e.type == GameEventType.shotTaken)
          .toList();
      expect(shots, hasLength(smallest.length));
      expect([for (final e in shots) e.player], smallest);
    });

    test('a new round records round start and a fresh deal', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      game.startNextRound();

      final lastTypes = types(game).skip(game.events.length - 2).toList();
      expect(lastTypes, [GameEventType.roundStarted, GameEventType.cardsDealt]);
      expect(game.events.last.round, 2);
      expect(game.eventsForRound(2), isNotEmpty);
    });

    test('game completion records a final event', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 2,
      );
      // Play rounds until the game completes.
      while (!game.gameComplete) {
        viewAll(game);
        everyoneHoldsOut(game);
        if (!game.canStartNextRound) break;
        game.startNextRound();
      }

      expect(game.gameComplete, isTrue);
      expect(game.events.last.type, GameEventType.gameCompleted);
    });

    test('rejected actions record nothing', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      final before = game.events.length;
      // A non-current player cannot act.
      expect(
        () => game.callYamada(game.players.last),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.events.length, before);
    });

    test('the log never contains card identities', () {
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

      // Events carry only types, players, cup sizes and round results.
      // Round results are aggregate (drinks, YAMADA flags, smallest hands,
      // cup size) and have no card field.
      for (final event in game.events) {
        expect(
          event.toString(),
          isNot(contains('Card(')),
          reason: 'events must never serialize cards',
        );
        if (event.result != null) {
          expect(
            event.result!.toString(),
            isNot(contains('Card(')),
            reason: 'round results must never serialize cards',
          );
        }
      }
    });
  });
}
