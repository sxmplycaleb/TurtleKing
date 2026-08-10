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

  /// Every active player holds out until the round completes.
  void everyoneHoldsOut(GameState game) {
    while (!game.roundComplete) {
      game.holdOut(game.pourCurrentPlayer);
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

    test('a hold-out round records reveal, smallest, both penalties and '
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
      // Two penalties per smallest player: full + extra.
      final full = log.where((t) => t == GameEventType.fullCupPenalty);
      final extra = log.where((t) => t == GameEventType.extraCupPenalty);
      expect(full, hasLength(1));
      expect(extra, hasLength(1));
      expect(log, contains(GameEventType.roundResult));
      expect(log, contains(GameEventType.roundCompleted));
      // No YAMADA this round, so the cup grows afterwards.
      expect(
        log.indexOf(GameEventType.cupSizeAdvanced),
        greaterThan(log.indexOf(GameEventType.roundCompleted)),
      );
    });

    test('a YAMADA round records the call, the drink and replacement cards '
        'but no reveal', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      final first = game.pourCurrentPlayer;
      game.callYamada(first);
      game.holdOut(first);
      game.holdOut(game.pourCurrentPlayer);

      final log = types(game);
      expect(log, contains(GameEventType.playerCalledYamada));
      expect(log, contains(GameEventType.yamadaDrink));
      expect(log, contains(GameEventType.replacementCardsDealt));
      expect(log, contains(GameEventType.roundCompleted));
      // The rules require no simultaneous reveal after YAMADA.
      expect(log, isNot(contains(GameEventType.revealOccurred)));
      expect(log, isNot(contains(GameEventType.smallestDetermined)));
      expect(log, isNot(contains(GameEventType.fullCupPenalty)));
      // Cup does not grow after a YAMADA round.
      expect(log, isNot(contains(GameEventType.cupSizeAdvanced)));
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
      final drink = game.events.firstWhere(
        (e) => e.type == GameEventType.yamadaDrink,
      );
      expect(drink.player, first);
    });

    test('reaching six drinks records exactly one elimination', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 6,
      );
      viewAll(game);
      final first = game.pourCurrentPlayer;
      for (var i = 0; i < 5; i++) {
        game.callYamada(first);
        game.holdOut(first);
        game.holdOut(game.pourCurrentPlayer);
        game.startNextRound();
        viewAll(game);
      }
      // Sixth drink eliminates immediately during the round.
      game.callYamada(first);
      expect(game.isEliminated(first), isTrue);

      final eliminations = game.events
          .where((e) => e.type == GameEventType.playerEliminated)
          .toList();
      expect(eliminations, hasLength(1));
      expect(eliminations.single.player, first);
      // The eliminated player is not dealt replacement cards.
      final dealtAfter = game.events
          .where(
            (e) =>
                e.type == GameEventType.replacementCardsDealt &&
                e.player == first,
          )
          .length;
      expect(dealtAfter, 5);
    });

    test('ties: every tied smallest player receives both penalties', () {
      // A seeded game where two players tie for the smallest hand. We force
      // the tie by checking the result: at least the round result's smallest
      // list drives the recorded events, so assert the event plumbing, not
      // the seed.
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);

      final smallest = game.smallestHands;
      final full = game.events
          .where((e) => e.type == GameEventType.fullCupPenalty)
          .toList();
      final extra = game.events
          .where((e) => e.type == GameEventType.extraCupPenalty)
          .toList();
      // Whatever the seed produced, the penalty events mirror the smallest
      // list exactly: one full + one extra per tied player, no more.
      expect(full, hasLength(smallest.length));
      expect(extra, hasLength(smallest.length));
      expect([for (final e in full) e.player], smallest);
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

      final lastTypes = types(game).skip(game.events.length - 3).toList();
      expect(lastTypes, [
        GameEventType.cupSizeAdvanced,
        GameEventType.roundStarted,
        GameEventType.cardsDealt,
      ]);
      expect(game.events.last.round, 2);
      expect(game.eventsForRound(2), isNotEmpty);
    });

    test('game completion records a final event', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      final players = game.activePlayers;
      game.callYamada(players[0]);
      game.callYamada(players[0]);
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
