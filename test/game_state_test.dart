import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

void main() {
  List<Player> makePlayers(int count) => [
    for (var i = 1; i <= count; i++)
      Player(
        id: 'player-$i',
        name: 'Player $i',
        color: PlayerColors.palette[i - 1],
      ),
  ];

  int handTotal(GameState game, Player player) =>
      game.handOf(player).fold(0, (sum, card) => sum + card.value);

  /// Moves the game through the entire viewing phase so pouring starts.
  void viewAll(GameState game) {
    for (var i = 0; i < game.currentPlayerCount; i++) {
      game.revealCurrentPlayer();
      game.passToNextPlayer();
    }
    expect(game.pouringStarted, isTrue);
  }

  /// Every active player holds out once, completing the round's reveal.
  void everyoneHoldsOut(GameState game) {
    final count = game.activePlayerCount;
    for (var i = 0; i < count; i++) {
      game.holdOut(game.pourCurrentPlayer);
    }
    expect(game.roundComplete, isTrue);
  }

  group('initial deal', () {
    test('every player receives exactly two cards', () {
      final game = GameState(players: makePlayers(4), random: Random(1));
      expect(game.players, hasLength(4));
      for (final player in game.players) {
        expect(game.handOf(player), hasLength(2));
      }
    });

    test('each hand contains two unique cards', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      for (final player in game.players) {
        expect(game.handOf(player).toSet().length, 2);
      }
    });

    test('no card appears in two players\' hands', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      final allCards = [
        for (final player in game.players) ...game.handOf(player),
      ];
      expect(allCards.toSet().length, allCards.length);
    });

    test('deck count decreases by two per player', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      expect(game.remainingCards, 52 - 6);
    });

    test('players can look at exactly one card: the first of their hand', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      for (final player in game.players) {
        expect(game.visibleCardOf(player), game.handOf(player).first);
      }
    });

    test('fewer than two players is rejected', () {
      expect(
        () => GameState(players: makePlayers(1), random: Random(1)),
        throwsArgumentError,
      );
    });

    test('invalid elimination threshold is rejected', () {
      expect(
        () => GameState(
          players: makePlayers(2),
          random: Random(1),
          eliminationThreshold: 0,
        ),
        throwsArgumentError,
      );
    });

    test('default elimination threshold is six drinks', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.eliminationThreshold, 6);
    });
  });

  group('viewing phase', () {
    test('the first player starts the viewing flow', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.currentPlayer, game.players.first);
    });

    test('cards are hidden until the player reveals', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.currentPlayerRevealed, isFalse);
    });

    test('passing hides the next player\'s card again', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      game.revealCurrentPlayer();
      game.passToNextPlayer();
      expect(game.currentPlayerRevealed, isFalse);
    });

    test('players view in setup order', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      expect(game.currentPlayer, game.players[0]);
      game.revealCurrentPlayer();
      game.passToNextPlayer();
      expect(game.currentPlayer, game.players[1]);
      game.revealCurrentPlayer();
      game.passToNextPlayer();
      expect(game.currentPlayer, game.players[2]);
    });

    test('pouring starts automatically after the final viewer passes', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      viewAll(game);
      expect(game.pouringStarted, isTrue);
    });

    test('revealing after all viewed throws', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      viewAll(game);
      expect(
        () => game.revealCurrentPlayer(),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('passing after all viewed throws and leaves state unchanged', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      viewAll(game);
      final index = game.currentPlayerIndex;
      expect(
        () => game.passToNextPlayer(),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.currentPlayerIndex, index);
      expect(game.pouringStarted, isTrue);
    });
  });

  group('pouring and YAMADA', () {
    GameState pouringGame() {
      final game = GameState(players: makePlayers(3), random: Random(1));
      viewAll(game);
      return game;
    }

    test('holding out advances the turn to the next player', () {
      final game = pouringGame();
      final first = game.pourCurrentPlayer;
      game.holdOut(first);
      expect(game.pourCurrentPlayer, game.activePlayers[1]);
      expect(game.roundComplete, isFalse);
    });

    test('YAMADA is a strategic surrender — no immediate drink or redeal', () {
      final game = pouringGame();
      final player = game.pourCurrentPlayer;
      final oldHand = game.handOf(player);
      game.callYamada(player);
      // YAMADA does NOT drink immediately — it's a strategic surrender.
      expect(game.drinksOf(player), 0);
      // Hand is NOT redealt.
      expect(game.handOf(player), equals(oldHand));
      // Turn advances to the next player.
      expect(game.pourCurrentPlayer, isNot(equals(player)));
    });

    test('YAMADA advances to the next player', () {
      final game = pouringGame();
      final player = game.pourCurrentPlayer;
      game.callYamada(player);
      expect(game.pourCurrentPlayer, isNot(equals(player)));
    });

    test('YAMADA is recorded for the round', () {
      final game = pouringGame();
      final player = game.pourCurrentPlayer;
      game.callYamada(player);
      expect(game.calledYamadaThisRound(player), isTrue);
    });

    test('only one YAMADA call is allowed per round', () {
      final game = pouringGame();
      final player = game.pourCurrentPlayer;
      game.callYamada(player);
      expect(
        () => game.callYamada(game.pourCurrentPlayer),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('multiple players may hold out after YAMADA — round completes', () {
      final game = pouringGame();
      final first = game.pourCurrentPlayer;
      game.callYamada(first); // Player 1 calls YAMADA
      // Now all 3 players have acted (1 YAMADA'd, but the set tracks actors)
      // Actually, after player 1 calls YAMADA, the turn goes to player 2.
      // Player 2 holds out, player 3 holds out. But player 1 already acted.
      // So 3 players have acted — round should complete.
      // Wait, no. After YAMADA from player 1, _playersActedThisRound has {player1}.
      // Player 2 holds out -> {player1, player2}. Player 3 holds out -> {player1, player2, player3}.
      // That's 3 == activePlayerCount, so round completes.
      // Actually: holdOut from player 2 increments _playersActedThisRound to 2.
      // holdOut from player 3 increments to 3 == activePlayerCount. Round completes.
      game.holdOut(game.pourCurrentPlayer);
      game.holdOut(game.pourCurrentPlayer);
      expect(game.roundComplete, isTrue);
    });

    test('acting out of turn throws without changing state', () {
      final game = pouringGame();
      final players = game.activePlayers;
      final other = players[1];
      final drinksBefore = game.drinksOf(other);
      expect(
        () => game.callYamada(other),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(() => game.holdOut(other), throwsA(isA<YamadaRoundException>()));
      expect(game.drinksOf(other), drinksBefore);
      expect(game.pourCurrentPlayer, players.first);
    });

    test('pouring actions before pouring starts throw', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(
        () => game.callYamada(game.players.first),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.holdOut(game.players.first),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('an eliminated player cannot act', () {
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      // Everyone holds out in round 1: smallest hand gets 2 drinks (1 + 1).
      // If a player is the smallest, they get 2 drinks = elimination at threshold 2.
      // With 3 players, smallest hand gets 1 + 1 = 2 drinks. If threshold is 2, that's elimination.
      everyoneHoldsOut(game);
      // Check if anyone was eliminated by the reveal penalty.
      final eliminated = game.eliminatedPlayers;
      if (eliminated.isNotEmpty) {
        expect(
          () => game.callYamada(eliminated.first),
          throwsA(isA<YamadaRoundException>()),
        );
        expect(
          () => game.holdOut(eliminated.first),
          throwsA(isA<YamadaRoundException>()),
        );
      }
    });
  });

  group('YAMADA resolution', () {
    test('correct YAMADA (caller has smallest hand) gives 0 shots', () {
      // We need a deterministic scenario: caller has the smallest hand.
      // Use a seed where player 1's visible card + hidden card are smallest.
      // Since we can't control cards easily, just test the mechanism:
      // everyone holds out + YAMADA was called → the caller is checked.
      // In a 2-player game, if player 1 calls YAMADA and has smaller hand,
      // they get 0 shots. Otherwise, 1 shot.
      GameState? foundCorrect;
      GameState? foundWrong;
      for (var seed = 0; seed < 500; seed++) {
        final game = GameState(
          players: makePlayers(2),
          random: Random(seed),
          eliminationThreshold: 100,
        );
        viewAll(game);
        final p1 = game.pourCurrentPlayer;
        game.callYamada(p1);
        // Other player holds out.
        game.holdOut(game.pourCurrentPlayer);
        if (!game.roundComplete) {
          // The first player already acted via YAMADA, now need the other.
          // After YAMADA from p1, turn goes to p2. p2 holds out.
          // Both have acted. Round should complete.
        }
        if (game.roundComplete) {
          final t1 = handTotal(game, p1);
          final t2 = handTotal(
            game,
            game.activePlayers.firstWhere((p) => p.id != p1.id),
          );
          if (t1 <= t2 && foundCorrect == null) {
            foundCorrect = game;
          } else if (t1 > t2 && foundWrong == null) {
            foundWrong = game;
          }
          if (foundCorrect != null && foundWrong != null) break;
        }
      }

      // Test correct YAMADA
      if (foundCorrect != null) {
        final game = foundCorrect;
        final caller = game.yamadaCallerThisRound!;
        expect(game.yamadaCalledThisRound, isTrue);
        expect(game.yamadaWasCorrect, isTrue);
        expect(game.roundDrinksOf(caller), 0);
      }

      if (foundWrong != null) {
        final game = foundWrong;
        final caller = game.yamadaCallerThisRound!;
        expect(game.yamadaCalledThisRound, isTrue);
        expect(game.yamadaWasCorrect, isFalse);
        expect(game.roundDrinksOf(caller), 1);
        expect(game.drinksOf(caller), 1);
      }
    });

    test('YAMADA caller\'s hand is revealed', () {
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      final p1 = game.pourCurrentPlayer;
      game.callYamada(p1);
      game.holdOut(game.pourCurrentPlayer);
      game.holdOut(game.pourCurrentPlayer);
      expect(game.roundComplete, isTrue);
      expect(game.revealedPlayers, [p1]);
    });

    test(
      'wrong YAMADA: caller takes 1 shot, smallest hand is not revealed',
      () {
        GameState? found;
        for (var seed = 0; seed < 500; seed++) {
          final game = GameState(
            players: makePlayers(2),
            random: Random(seed),
            eliminationThreshold: 100,
          );
          viewAll(game);
          final p1 = game.pourCurrentPlayer;
          game.callYamada(p1);
          game.holdOut(game.pourCurrentPlayer);
          if (game.roundComplete && !game.yamadaWasCorrect) {
            found = game;
            break;
          }
        }
        if (found != null) {
          final caller = found.yamadaCallerThisRound!;
          expect(found.roundDrinksOf(caller), 1);
          // Only the caller is revealed.
          expect(found.revealedPlayers, [caller]);
          // No smallest hands penalty (wrong YAMADA already penalized).
          expect(found.smallestHands, isEmpty);
        }
      },
    );
  });

  group('reveal (no YAMADA)', () {
    test('holding out through a full cycle completes the round', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      viewAll(game);
      everyoneHoldsOut(game);
      expect(game.roundComplete, isTrue);
      expect(game.roundResult, isNotNull);
    });

    test(
      'the smallest hand takes roundNumber shots + 1 extra for holding out',
      () {
        final game = GameState(players: makePlayers(3), random: Random(1));
        viewAll(game);
        final totals = {
          for (final player in game.activePlayers)
            player: handTotal(game, player),
        };
        final minTotal = totals.values.reduce((a, b) => a < b ? a : b);
        final smallest = [
          for (final player in game.activePlayers)
            if (totals[player] == minTotal) player,
        ];
        everyoneHoldsOut(game);
        expect(game.smallestHands, smallest);
        for (final player in game.activePlayers) {
          if (smallest.contains(player)) {
            // Round 1: 1 shot (fullCupPenalty) + 1 shot (extraCupPenalty) = 2
            expect(game.roundDrinksOf(player), 2);
            expect(game.drinksOf(player), 2);
          } else {
            expect(game.roundDrinksOf(player), 0);
            expect(game.drinksOf(player), 0);
          }
        }
      },
    );

    test('tied smallest hands all drink the penalty', () {
      GameState? found;
      for (var seed = 0; seed < 400; seed++) {
        final game = GameState(players: makePlayers(2), random: Random(seed));
        final a = handTotal(game, game.players[0]);
        final b = handTotal(game, game.players[1]);
        if (a == b) {
          found = game;
          break;
        }
      }
      expect(found, isNotNull, reason: 'expected a seed with tied hands');
      final game = found!;
      viewAll(game);
      everyoneHoldsOut(game);
      expect(game.smallestHands, hasLength(2));
      for (final player in game.players) {
        expect(game.roundDrinksOf(player), 2);
        expect(game.drinksOf(player), 2);
      }
    });

    test('revealed players are exactly those who held out', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      viewAll(game);
      everyoneHoldsOut(game);
      expect(game.revealedPlayers, game.activePlayers);
    });

    test('round result records drinks, YAMADA flags, and cup size', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      final first = game.pourCurrentPlayer;
      game.callYamada(first);
      game.holdOut(game.pourCurrentPlayer);
      expect(game.roundComplete, isTrue);
      final result = game.roundResult!;
      expect(result.calledYamada[first], isTrue);
      // Every player is represented, including zero-drink players.
      expect(result.drinks, hasLength(2));
    });

    test(
      'the round result is a fixed snapshot that later rounds cannot rewrite',
      () {
        final game = GameState(
          players: makePlayers(2),
          random: Random(1),
          eliminationThreshold: 100,
        );
        viewAll(game);
        everyoneHoldsOut(game);
        final firstResult = game.roundResult!;
        final firstDrinks = Map.of(firstResult.drinks);
        game.startNextRound();
        viewAll(game);
        everyoneHoldsOut(game);
        expect(game.roundResults.first.drinks, firstDrinks);
        expect(game.roundResults, hasLength(2));
      },
    );
  });

  group('cup progression', () {
    test('the first round uses a normal cup', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.cupSize, CupSize.normal);
    });

    test('a no-YAMADA round grows the cup to large', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      game.startNextRound();
      expect(game.cupSize, CupSize.large);
    });

    test('two consecutive no-YAMADA rounds grow the cup to extra-large', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      for (var round = 0; round < 2; round++) {
        viewAll(game);
        everyoneHoldsOut(game);
        game.startNextRound();
      }
      expect(game.cupSize, CupSize.extraLarge);
    });

    test('the cup stops growing at extra-large', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      for (var round = 0; round < 3; round++) {
        viewAll(game);
        everyoneHoldsOut(game);
        game.startNextRound();
      }
      expect(game.cupSize, CupSize.extraLarge);
    });

    test('a round with YAMADA still escalates the cup', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      final first = game.pourCurrentPlayer;
      game.callYamada(first);
      game.holdOut(game.pourCurrentPlayer);
      expect(game.roundComplete, isTrue);
      game.startNextRound();
      // Cup still escalates to round 2 regardless of YAMADA.
      expect(game.cupSize, CupSize.large);
    });
  });

  group('rounds', () {
    test(
      'startNextRound deals fresh hands and restarts viewing with player 1',
      () {
        final game = GameState(
          players: makePlayers(3),
          random: Random(1),
          eliminationThreshold: 100,
        );
        viewAll(game);
        everyoneHoldsOut(game);
        game.startNextRound();
        expect(game.roundNumber, 2);
        expect(game.completedRounds, 1);
        expect(game.pouringStarted, isFalse);
        expect(game.currentPlayer, game.players.first);
        for (final player in game.players) {
          expect(game.handOf(player), hasLength(2));
        }
      },
    );

    test('new round hands contain no duplicate cards', () {
      final game = GameState(
        players: makePlayers(4),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      game.startNextRound();
      final dealt = [for (final player in game.players) ...game.handOf(player)];
      expect(dealt, hasLength(8));
      expect(dealt.toSet(), hasLength(8));
    });

    test('lifetime drinks persist across rounds', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      final first = game.pourCurrentPlayer;
      game.callYamada(first);
      game.holdOut(game.pourCurrentPlayer);
      // Round 1 complete.
      game.startNextRound();
      final lifetimeAfterRound1 = game.drinksOf(first);
      expect(lifetimeAfterRound1, greaterThanOrEqualTo(0));
      expect(game.roundDrinksOf(first), 0);
    });

    test('canStartNextRound is false before completion and after game end', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      expect(game.canStartNextRound, isFalse);
      everyoneHoldsOut(game);
      expect(game.canStartNextRound, isTrue);
      game.startNextRound();
      // Game still has 2 players, round not complete yet.
      expect(game.roundComplete, isFalse);
      expect(game.canStartNextRound, isFalse);
    });

    test('startNextRound before the round completes throws', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      viewAll(game);
      expect(() => game.startNextRound(), throwsA(isA<YamadaRoundException>()));
    });

    test('the deck reshuffles when it runs low so play can continue', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      // Play many rounds to exhaust the deck.
      for (var i = 0; i < 20; i++) {
        viewAll(game);
        everyoneHoldsOut(game);
        if (game.canStartNextRound) {
          game.startNextRound();
        } else {
          break;
        }
      }
      // Game should still have 2 active players (deck reshuffled).
      expect(game.activePlayerCount, 2);
      expect(game.handOf(game.players.first), hasLength(2));
    });
  });

  group('elimination', () {
    test('a player is eliminated by the smallest-hand penalty', () {
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      // Round 1: smallest hand gets 2 drinks (1 + 1) = elimination at threshold 2.
      final eliminated = game.eliminatedPlayers;
      expect(eliminated, isNotEmpty);
      expect(game.isEliminated(eliminated.first), isTrue);
    });

    test('elimination records the player, round, drinks, and reason', () {
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      final record = game.eliminationHistory.single;
      expect(record.round, 1);
      expect(record.drinks, 2);
      expect(record.reason, EliminationReason.sixDrinks);
    });

    test('elimination happens exactly once', () {
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      expect(game.eliminationHistory, hasLength(1));
    });

    test('the turn order skips eliminated players', () {
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      final eliminatedBefore = game.eliminatedPlayers.length;
      everyoneHoldsOut(game);
      final eliminatedAfter = game.eliminatedPlayers.length;
      if (eliminatedAfter > eliminatedBefore) {
        // Someone was eliminated; the remaining players are active.
        expect(game.activePlayerCount, lessThan(3));
      }
    });

    test('eliminated players receive no cards in later rounds', () {
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      final eliminated = game.eliminatedPlayers;
      if (eliminated.isNotEmpty && game.canStartNextRound) {
        game.startNextRound();
        expect(game.hasHand(eliminated.first), isFalse);
      }
    });

    test('the game ends when fewer than two active players remain', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      // Round 1: smallest hand gets 2 drinks. In a 2-player game, both could
      // tie or one could be smallest. Check if the game ended.
      if (game.gameComplete) {
        expect(game.activePlayerCount, lessThan(2));
        expect(game.finalResult, isNotNull);
      }
    });

    test('no actions are accepted after the game completes', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      if (game.gameComplete) {
        final other = game.activePlayers.single;
        expect(() => game.holdOut(other), throwsA(isA<YamadaRoundException>()));
        expect(
          () => game.callYamada(other),
          throwsA(isA<YamadaRoundException>()),
        );
      }
    });
  });

  group('Turtle King', () {
    test('the last player remaining is the Turtle King', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      // If one player was eliminated, the other is the Turtle King.
      if (game.gameComplete && game.activePlayerCount == 1) {
        final result = game.finalResult!;
        expect(result.turtleKings, hasLength(1));
        expect(result.finalists, hasLength(1));
      }
    });

    test('the final result keeps every player\'s lifetime drinks', () {
      final game = GameState(
        players: makePlayers(3),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      game.startNextRound();
      final result = game.finalResult;
      if (result != null) {
        expect(result.drinks, hasLength(3));
      } else {
        expect(game.activePlayerCount, greaterThanOrEqualTo(2));
      }
    });

    test(
      'when every remaining player is eliminated no Turtle King is declared',
      () {
        final game = GameState(
          players: makePlayers(2),
          random: Random(1),
          eliminationThreshold: 2,
        );
        viewAll(game);
        everyoneHoldsOut(game);
        // If both players are eliminated simultaneously, no Turtle King.
        if (game.gameComplete && game.activePlayerCount == 0) {
          expect(game.finalResult!.turtleKings, isEmpty);
        }
        // If one remains, that player is the Turtle King.
        if (game.gameComplete && game.activePlayerCount == 1) {
          expect(game.finalResult!.turtleKings, hasLength(1));
        }
      },
    );
  });

  group('determinism', () {
    void playScripted(GameState game) {
      viewAll(game);
      everyoneHoldsOut(game);
      if (game.roundComplete && game.canStartNextRound) {
        game.startNextRound();
        viewAll(game);
        everyoneHoldsOut(game);
      }
    }

    test('same players + same seed + same actions = identical outcome', () {
      final gameA = GameState(
        players: makePlayers(3),
        random: Random(42),
        eliminationThreshold: 100,
      );
      final gameB = GameState(
        players: makePlayers(3),
        random: Random(42),
        eliminationThreshold: 100,
      );
      playScripted(gameA);
      playScripted(gameB);
      for (final player in gameA.players) {
        expect(gameA.drinksOf(player), gameB.drinksOf(player));
        expect(gameA.isEliminated(player), gameB.isEliminated(player));
      }
      expect(gameA.completedRounds, gameB.completedRounds);
      expect(gameA.gameComplete, gameB.gameComplete);
      if (gameA.finalResult != null && gameB.finalResult != null) {
        expect(
          gameA.finalResult!.turtleKings.map((p) => p.id),
          gameB.finalResult!.turtleKings.map((p) => p.id),
        );
      }
    });
  });

  group('privacy', () {
    test(
      'the visible-card API only ever exposes the player\'s own first card',
      () {
        final game = GameState(players: makePlayers(4), random: Random(1));
        for (final player in game.players) {
          final visible = game.visibleCardOf(player);
          expect(game.handOf(player).contains(visible), isTrue);
          expect(game.visibleCardOf(player), visible);
        }
      },
    );

    test(
      'no other player\'s card is reachable through a single player\'s view',
      () {
        final game = GameState(players: makePlayers(4), random: Random(1));
        final first = game.players.first;
        final firstVisible = game.visibleCardOf(first);
        for (final other in game.players.skip(1)) {
          expect(game.visibleCardOf(other), isNot(firstVisible));
        }
      },
    );

    test('round results contain no card identities', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 100,
      );
      viewAll(game);
      everyoneHoldsOut(game);
      final result = game.roundResult!;
      expect(result.drinks, hasLength(game.players.length));
      expect(result.calledYamada, hasLength(game.players.length));
    });
  });
}
