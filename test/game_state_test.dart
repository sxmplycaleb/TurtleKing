import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/card.dart';
import 'package:turtle_king/deck.dart';
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

  /// A game where every player has already viewed their two cards.
  GameState readyGame(int playerCount, int seed) {
    final game = GameState(
      players: makePlayers(playerCount),
      random: Random(seed),
    );
    for (var i = 0; i < playerCount; i++) {
      game.revealCurrentPlayer();
      game.passToNextPlayer();
    }
    expect(game.allPlayersViewed, isTrue);
    return game;
  }

  group('GameState dealing', () {
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
        expect(game.handOf(player).toSet(), hasLength(2));
      }
    });

    test('no card appears in two players\' hands', () {
      final game = GameState(players: makePlayers(5), random: Random(1));
      final allDealt = [
        for (final player in game.players) ...game.handOf(player),
      ];
      expect(allDealt, hasLength(10));
      expect(allDealt.toSet(), hasLength(10));
    });

    test('deck count decreases by two per player', () {
      final twoPlayers = GameState(players: makePlayers(2), random: Random(1));
      expect(twoPlayers.remainingCards, 48);

      final fourPlayers = GameState(players: makePlayers(4), random: Random(1));
      expect(fourPlayers.remainingCards, 44);
    });

    test('hands come from the shuffled deck', () {
      const seed = 42;
      final game = GameState(players: makePlayers(3), random: Random(seed));
      final deck = Deck(random: Random(seed))..shuffle();
      for (final player in game.players) {
        expect(game.handOf(player), deck.deal(2));
      }
    });

    test('rejects fewer than two players', () {
      expect(() => GameState(players: makePlayers(1)), throwsArgumentError);
    });
  });

  group('GameState viewing flow', () {
    test('the first player starts the viewing flow with cards hidden', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      expect(game.currentPlayerIndex, 0);
      expect(game.currentPlayer, game.players.first);
      expect(game.currentPlayerRevealed, isFalse);
      expect(game.allPlayersViewed, isFalse);
    });

    test('cards stay hidden until the current player reveals them', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.currentPlayerRevealed, isFalse);

      game.revealCurrentPlayer();
      expect(game.currentPlayerRevealed, isTrue);
    });

    test('passing moves to the next player with their cards hidden', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      game.revealCurrentPlayer();
      game.passToNextPlayer();

      expect(game.currentPlayerIndex, 1);
      expect(game.currentPlayer, game.players[1]);
      expect(game.currentPlayerRevealed, isFalse);
    });

    test('player order is preserved as players pass', () {
      final game = GameState(players: makePlayers(4), random: Random(1));
      for (var i = 0; i < 4; i++) {
        expect(game.currentPlayerIndex, i);
        expect(game.currentPlayer, game.players[i]);
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      expect(game.allPlayersViewed, isTrue);
    });

    test('all players have viewed only after the final player passes', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.allPlayersViewed, isFalse);

      game.revealCurrentPlayer();
      game.passToNextPlayer();
      // The second player still needs to view their cards.
      expect(game.allPlayersViewed, isFalse);

      game.revealCurrentPlayer();
      game.passToNextPlayer();
      expect(game.allPlayersViewed, isTrue);
    });

    test('revealing after the flow ends is a no-op', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      game.revealCurrentPlayer();
      game.passToNextPlayer();
      game.revealCurrentPlayer();
      game.passToNextPlayer();

      expect(game.allPlayersViewed, isTrue);
      game.revealCurrentPlayer();
      expect(game.currentPlayerRevealed, isFalse);
    });
  });

  group('GameState center pile', () {
    test('a new game starts with an empty center pile', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      expect(game.centerPile, isEmpty);
    });

    test('dealToCenter consumes one card from the undealt deck', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.remainingCards, 48);

      final card = game.dealToCenter();

      expect(card, isA<Card>());
      expect(game.remainingCards, 47);
      expect(game.centerPile, [card]);
    });

    test('the drawn card comes from the original 52-card deck', () {
      const seed = 7;
      final game = GameState(players: makePlayers(3), random: Random(seed));
      // Replay the same seeded deal: 2 cards per player, then the next card
      // in the deck is exactly what dealToCenter draws.
      final deck = Deck(random: Random(seed))..shuffle();
      deck.deal(2 * game.players.length);
      final expected = deck.dealOne();

      expect(game.dealToCenter(), expected);
    });

    test('dealing to the center leaves player hands unchanged', () {
      final game = GameState(players: makePlayers(4), random: Random(1));
      final handsBefore = {
        for (final player in game.players) player.id: [...game.handOf(player)],
      };

      game.dealToCenter();
      game.dealToCenter();
      game.dealToCenter();

      for (final player in game.players) {
        expect(game.handOf(player), handsBefore[player.id]);
      }
    });

    test('remainingCards decreases by one per center draw', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      const draws = 10;
      for (var i = 0; i < draws; i++) {
        game.dealToCenter();
      }
      expect(game.remainingCards, 48 - draws);
      expect(game.centerPile, hasLength(draws));
    });

    test('repeated center draws never duplicate a card or a hand card', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      final handCards = {
        for (final player in game.players) ...game.handOf(player),
      };

      for (var i = 0; i < 20; i++) {
        final card = game.dealToCenter();
        expect(handCards, isNot(contains(card)));
        expect(game.centerPile.where((c) => c == card), hasLength(1));
      }
      expect(game.centerPile.toSet(), hasLength(20));
    });

    test('dealing to the center when the deck is empty throws', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      while (game.remainingCards > 0) {
        game.dealToCenter();
      }
      expect(game.remainingCards, 0);
      expect(() => game.dealToCenter(), throwsA(isA<EmptyDeckException>()));
    });

    test('center draws do not affect the viewing flow', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      game.dealToCenter();

      game.revealCurrentPlayer();
      expect(game.currentPlayerRevealed, isTrue);
      expect(game.allPlayersViewed, isFalse);

      game.passToNextPlayer();
      expect(game.currentPlayer, game.players[1]);
      expect(game.currentPlayerRevealed, isFalse);
    });
  });

  group('GameState YAMADA round', () {
    test('the round has not started on a new game', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.roundStarted, isFalse);
      expect(game.roundComplete, isFalse);
      expect(game.currentCenterCard, isNull);
      expect(game.currentPlayerActed, isFalse);
      expect(game.roundPlayerIndex, 0);
    });

    test('starting the round before everyone has viewed is rejected', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(
        () => game.startYamadaRound(),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.roundStarted, isFalse);
      expect(game.centerPile, isEmpty);
      expect(game.remainingCards, 48);
    });

    test('starting the round twice is rejected', () {
      final game = readyGame(2, 1)..startYamadaRound();
      expect(
        () => game.startYamadaRound(),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.centerPile, hasLength(1));
      expect(game.remainingCards, 47);
    });

    test('starting the round deals the first center card and starts with '
        'the first player', () {
      final game = readyGame(2, 1)..startYamadaRound();
      expect(game.roundStarted, isTrue);
      expect(game.roundComplete, isFalse);
      expect(game.roundPlayerIndex, 0);
      expect(game.roundCurrentPlayer, game.players[0]);
      expect(game.currentPlayerActed, isFalse);
      expect(game.remainingCards, 47);
      expect(game.currentCenterCard, game.centerPile.last);
    });

    test('the initial center card is deterministic for a given seed', () {
      final first = readyGame(3, 7)..startYamadaRound();
      final second = readyGame(3, 7)..startYamadaRound();
      expect(first.currentCenterCard, second.currentCenterCard);
    });

    test(
      'the initial center card comes from the original deck, never a hand',
      () {
        const seed = 7;
        final game = readyGame(3, seed)..startYamadaRound();
        final deck = Deck(random: Random(seed))..shuffle();
        deck.deal(2 * game.players.length);
        expect(game.currentCenterCard, deck.dealOne());

        final handCards = {
          for (final player in game.players) ...game.handOf(player),
        };
        expect(handCards, isNot(contains(game.currentCenterCard)));
        expect({...handCards, game.currentCenterCard!}, hasLength(7));
      },
    );

    test('canCallYamada is true only when the center card is between the '
        "player's cards", () {
      // Player 0 holds 9 of Clubs and Ace of Diamonds; center is 8 of Spades.
      final canCapture = readyGame(2, 2)..startYamadaRound();
      expect(canCapture.canCallYamada, isTrue);

      // Player 0 holds Queen and Jack; center is 3.
      final cannotCapture = readyGame(2, 1)..startYamadaRound();
      expect(cannotCapture.canCallYamada, isFalse);
    });

    test('drawToCenter moves the top deck card onto the pile and advances '
        'the turn', () {
      final game = readyGame(3, 1)..startYamadaRound();
      final before = game.centerPile;

      final drawn = game.drawToCenter(game.players[0]);

      expect(drawn, isA<Card>());
      expect(game.centerPile, [...before, drawn]);
      expect(game.currentCenterCard, drawn);
      expect(game.remainingCards, 44); // 52 - 6 hands - 1 center - 1 draw
      expect(game.roundPlayerIndex, 1);
      expect(game.roundCurrentPlayer, game.players[1]);
      expect(game.currentPlayerActed, isFalse);
    });

    test('callYamada captures the center card into the player\'s pile', () {
      // Player 0 holds 9 of Clubs and Ace of Diamonds; center is 8 of Spades.
      final game = readyGame(2, 2)..startYamadaRound();
      final center = game.currentCenterCard!;
      expect(game.canCallYamada, isTrue);

      final result = game.callYamada(game.players[0]);

      expect(result.penalized, isFalse);
      expect(result.card, center);
      expect(game.capturedCardsOf(game.players[0]), [center]);
      expect(game.capturedCardsOf(game.players[1]), isEmpty);
      expect(game.centerPile, isEmpty);
      expect(game.currentCenterCard, isNull);
      expect(game.remainingCards, 47); // capturing draws no card
      expect(game.roundPlayerIndex, 1);
      expect(game.roundCurrentPlayer, game.players[1]);
      expect(game.currentPlayerActed, isFalse);
    });

    test('a wrong YAMADA call applies a penalty and captures nothing', () {
      // Player 0 holds Queen and Jack; center is 3, so the call is wrong.
      final game = readyGame(2, 1)..startYamadaRound();
      expect(game.canCallYamada, isFalse);

      final result = game.callYamada(game.players[0]);

      expect(result.penalized, isTrue);
      expect(result.card, isNull);
      expect(game.capturedCardsOf(game.players[0]), isEmpty);
      expect(game.centerPile, hasLength(1)); // the center card stays put
      expect(game.currentCenterCard, isNotNull);
      expect(game.penaltyCountOf(game.players[0]), 1);
      expect(game.roundPlayerIndex, 1);
      expect(game.remainingCards, 47);
    });

    test('calling YAMADA with an empty center pile is rejected', () {
      final game = readyGame(2, 2)..startYamadaRound();
      game.callYamada(game.players[0]); // Captures the only center card.
      expect(game.centerPile, isEmpty);

      expect(
        () => game.callYamada(game.players[1]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.roundPlayerIndex, 1);
      expect(game.remainingCards, 47);
    });

    test('the center pile preserves deal order across draws and captures', () {
      const seed = 1;
      final game = readyGame(2, seed)..startYamadaRound();
      final deck = Deck(random: Random(seed))..shuffle();
      deck.deal(4);
      final initialCenter = deck.dealOne();
      expect(game.centerPile, [initialCenter]);

      final drawn = game.drawToCenter(game.players[0]);
      expect(game.centerPile, [initialCenter, drawn]);
      // The drawn card is the very next card of the same seeded deck.
      expect(drawn, deck.dealOne());
    });

    test('a full round advances through every player exactly once', () {
      final game = readyGame(3, 3)..startYamadaRound();
      // Player 0 can capture the center card (2 < 3 < 12).
      expect(game.roundCurrentPlayer, game.players[0]);
      game.callYamada(game.players[0]);
      expect(game.roundCurrentPlayer, game.players[1]);
      game.drawToCenter(game.players[1]);
      expect(game.roundCurrentPlayer, game.players[2]);
      game.drawToCenter(game.players[2]);

      expect(game.roundComplete, isTrue);
      expect(game.roundPlayerIndex, 3);
    });

    test('acting after the round is complete is rejected without mutating '
        'state', () {
      final game = readyGame(2, 1)..startYamadaRound();
      game.drawToCenter(game.players[0]);
      game.drawToCenter(game.players[1]);
      expect(game.roundComplete, isTrue);

      final pileBefore = game.centerPile;
      final remainingBefore = game.remainingCards;
      expect(
        () => game.drawToCenter(game.players[0]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.callYamada(game.players[1]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.centerPile, pileBefore);
      expect(game.remainingCards, remainingBefore);
    });

    test(
      'acting before the round starts is rejected without mutating state',
      () {
        final game = GameState(players: makePlayers(2), random: Random(1));
        expect(
          () => game.drawToCenter(game.players[0]),
          throwsA(isA<YamadaRoundException>()),
        );
        expect(
          () => game.callYamada(game.players[0]),
          throwsA(isA<YamadaRoundException>()),
        );
        expect(game.centerPile, isEmpty);
        expect(game.remainingCards, 48);
      },
    );

    test('acting when it is not the player\'s turn is rejected without '
        'mutating state', () {
      final game = readyGame(2, 1)..startYamadaRound();
      final pileBefore = game.centerPile;

      expect(
        () => game.drawToCenter(game.players[1]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.callYamada(game.players[1]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.centerPile, pileBefore);
      expect(game.roundPlayerIndex, 0);
      expect(game.remainingCards, 47);
    });

    test('a player cannot act twice in a row', () {
      final game = readyGame(2, 1)..startYamadaRound();
      game.drawToCenter(game.players[0]);
      final pileBefore = game.centerPile;

      expect(
        () => game.drawToCenter(game.players[0]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.centerPile, pileBefore);
      expect(game.roundPlayerIndex, 1);
    });

    test('YAMADA captures never change player hands', () {
      final game = readyGame(2, 2)..startYamadaRound();
      final handsBefore = {
        for (final player in game.players) player.id: [...game.handOf(player)],
      };

      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);

      for (final player in game.players) {
        expect(game.handOf(player), handsBefore[player.id]);
      }
    });

    test('captured cards never duplicate a hand, the pile, or a capture', () {
      final game = readyGame(2, 2)..startYamadaRound();
      game.callYamada(game.players[0]); // Captures the initial center card.
      game.drawToCenter(game.players[1]);

      final allCards = [
        for (final player in game.players) ...game.handOf(player),
        ...game.centerPile,
        ...game.capturedCardsOf(game.players[0]),
        ...game.capturedCardsOf(game.players[1]),
      ];
      expect(allCards.toSet(), hasLength(allCards.length));
    });

    test('a full round is deterministic for a given seed', () {
      final first = readyGame(2, 2)..startYamadaRound();
      first.callYamada(first.players[0]);
      first.drawToCenter(first.players[1]);

      final second = readyGame(2, 2)..startYamadaRound();
      second.callYamada(second.players[0]);
      second.drawToCenter(second.players[1]);

      expect(second.centerPile, first.centerPile);
      expect(
        second.capturedCardsOf(second.players[0]),
        first.capturedCardsOf(first.players[0]),
      );
      expect(second.remainingCards, first.remainingCards);
      expect(second.roundComplete, isTrue);
    });
  });

  group('GameState scoring', () {
    test('new players have zero captures', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      for (final player in game.players) {
        expect(game.capturedCardsOf(player), isEmpty);
        expect(game.captureCountOf(player), 0);
      }
      expect(game.totalCapturedCards, 0);
    });

    test('each capture counts one point for the capturing player', () {
      final game = readyGame(2, 2)..startYamadaRound(); // 9/Ace vs 8.
      game.callYamada(game.players[0]);

      expect(game.captureCountOf(game.players[0]), 1);
      expect(game.captureCountOf(game.players[1]), 0);
      expect(game.totalCapturedCards, 1);
    });

    test('scores are independent and total correctly across players', () {
      // Seed 3: p0 captures 3 of Spades, p1 draws, p2 captures Jack of
      // Spades — two captures from two different players in one round.
      final game = readyGame(3, 3)..startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      game.callYamada(game.players[2]);

      expect(game.captureCountOf(game.players[0]), 1);
      expect(game.captureCountOf(game.players[1]), 0);
      expect(game.captureCountOf(game.players[2]), 1);
      expect(game.totalCapturedCards, 2);
    });

    test('scoring never changes player hands', () {
      final game = readyGame(3, 3)..startYamadaRound();
      final handsBefore = {
        for (final player in game.players) player.id: [...game.handOf(player)],
      };

      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      game.callYamada(game.players[2]);
      expect(
        game.captureCountOf(game.players[0]) +
            game.captureCountOf(game.players[2]),
        2,
      );

      for (final player in game.players) {
        expect(game.handOf(player), handsBefore[player.id]);
      }
    });

    test('captured cards never duplicate a hand, the pile, or a capture', () {
      final game = readyGame(3, 3)..startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      game.callYamada(game.players[2]);

      final allCards = [
        for (final player in game.players) ...game.handOf(player),
        ...game.centerPile,
        for (final player in game.players) ...game.capturedCardsOf(player),
      ];
      expect(allCards.toSet(), hasLength(allCards.length));
    });
  });

  group('GameState cup and penalties', () {
    test('a valid YAMADA call applies no penalty', () {
      final game = readyGame(2, 2)..startYamadaRound();
      game.callYamada(game.players[0]);

      expect(game.penaltyCountOf(game.players[0]), 0);
      expect(game.cupFillOf(game.players[0]), 0);
      expect(game.cupDrinksOf(game.players[0]), 0);
    });

    test('a wrong YAMADA call adds one penalty to the caller\'s cup', () {
      final game = readyGame(2, 1)..startYamadaRound(); // Queen/Jack vs 3.
      game.callYamada(game.players[0]);

      expect(game.penaltyCountOf(game.players[0]), 1);
      expect(game.cupFillOf(game.players[0]), 1);
      expect(game.cupDrinksOf(game.players[0]), 0);
      expect(game.penaltyCountOf(game.players[1]), 0);
    });

    test('penalties accumulate independently across players', () {
      // Seed 1: neither player can capture the initial center card.
      final game = readyGame(2, 1)..startYamadaRound();
      game.callYamada(game.players[0]);
      game.callYamada(game.players[1]);

      expect(game.penaltyCountOf(game.players[0]), 1);
      expect(game.penaltyCountOf(game.players[1]), 1);
      expect(game.roundComplete, isTrue);
    });

    test('a penalized call never moves the center card', () {
      final game = readyGame(2, 1)..startYamadaRound();
      final center = game.currentCenterCard!;

      game.callYamada(game.players[0]);

      expect(game.centerPile, [center]);
      expect(game.currentCenterCard, center);
      expect(game.capturedCardsOf(game.players[0]), isEmpty);
    });

    test('invalid API calls leave penalty state unchanged', () {
      final game = readyGame(2, 1)..startYamadaRound();
      expect(
        () => game.callYamada(game.players[1]), // not the current player
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.drawToCenter(game.players[1]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.penaltyCountOf(game.players[0]), 0);
      expect(game.penaltyCountOf(game.players[1]), 0);
      expect(game.cupFillOf(game.players[0]), 0);
    });

    test('a full cup overflows and empties while the total keeps counting', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        cupCapacity: 1,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();

      game.callYamada(game.players[0]); // One penalty fills the 1-slot cup.

      expect(game.penaltyCountOf(game.players[0]), 1);
      expect(game.cupFillOf(game.players[0]), 0); // overflowed and emptied
      expect(game.cupDrinksOf(game.players[0]), 1); // one full cup drunk
      expect(game.cupCapacity, 1);
    });

    test('rejects an invalid cup capacity', () {
      expect(
        () => GameState(players: makePlayers(2), cupCapacity: 0),
        throwsArgumentError,
      );
    });
  });

  group('GameState round result', () {
    test('roundResult is null until the round completes', () {
      final game = readyGame(2, 2)..startYamadaRound();
      expect(game.roundResult, isNull);
      game.callYamada(game.players[0]);
      expect(game.roundResult, isNull);
    });

    test('the completed round exposes final capture counts', () {
      final game = readyGame(2, 2)..startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      expect(game.roundComplete, isTrue);

      final result = game.roundResult!;
      expect(result.scores, {game.players[0]: 1, game.players[1]: 0});
      expect(game.totalCapturedCards, 1);
    });

    test('the result exposes a unique highest scorer', () {
      final game = readyGame(2, 2)..startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);

      final result = game.roundResult!;
      expect(result.highestScorers, [game.players[0]]);
      expect(result.lowestScorers, [game.players[1]]);
    });

    test('the result exposes tied scorers without a hidden tie-breaker', () {
      // Seed 3: p0 and p2 each capture one card; p1 captures none.
      final game = readyGame(3, 3)..startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      game.callYamada(game.players[2]);

      final result = game.roundResult!;
      expect(result.highestScorers, [game.players[0], game.players[2]]);
      expect(result.lowestScorers, [game.players[1]]);
    });

    test('no further actions are allowed once the round completes', () {
      final game = readyGame(2, 1)..startYamadaRound();
      game.drawToCenter(game.players[0]);
      game.drawToCenter(game.players[1]);
      expect(game.roundComplete, isTrue);

      expect(
        () => game.callYamada(game.players[0]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.drawToCenter(game.players[1]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.roundResult, isNotNull);
    });

    test('the result stays stable after completion', () {
      final game = readyGame(2, 2)..startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);

      final first = game.roundResult!;
      final second = game.roundResult!;
      expect(second.scores, first.scores);
      expect(second.highestScorers, first.highestScorers);
      expect(second.lowestScorers, first.lowestScorers);
    });
  });

  group('GameState penalty determinism', () {
    test('a full round with penalties and captures is deterministic', () {
      GameState play(int seed) {
        final game = readyGame(2, seed)..startYamadaRound();
        game.callYamada(game.players[0]); // seed 1: wrong call
        game.callYamada(game.players[1]); // seed 1: wrong call
        return game;
      }

      final first = play(1);
      final second = play(1);

      expect(second.penaltyCountOf(second.players[0]), 1);
      expect(second.penaltyCountOf(second.players[1]), 1);
      expect(
        second.penaltyCountOf(second.players[0]),
        first.penaltyCountOf(first.players[0]),
      );
      expect(second.centerPile, first.centerPile);
      expect(
        second.capturedCardsOf(second.players[0]),
        first.capturedCardsOf(first.players[0]),
      );
      expect(second.remainingCards, first.remainingCards);
      // Players compare by identity, so compare the score values in order.
      expect(
        second.roundResult!.scores.values.toList(),
        first.roundResult!.scores.values.toList(),
      );
    });
  });

  group('GameState multi-round', () {
    /// Completes the private viewing phase for every player.
    void viewAll(GameState game) {
      for (var i = 0; i < game.players.length; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      expect(game.allPlayersViewed, isTrue);
    }

    /// Plays one full round: [acts][i] is true for a capture, false for a
    /// draw. Requires the round to already be started.
    void playRound(GameState game, List<bool> acts) {
      for (var i = 0; i < game.players.length; i++) {
        if (acts[i]) {
          game.callYamada(game.players[i]);
        } else {
          game.drawToCenter(game.players[i]);
        }
      }
      expect(game.roundComplete, isTrue);
    }

    /// Views, starts, and plays round 1 for seed 22: player 0 captures the
    /// initial center card, player 1 draws.
    void playSeed22Round1(GameState game) {
      viewAll(game);
      game.startYamadaRound();
      playRound(game, [true, false]);
    }

    test('a fresh game has no rounds and is not complete', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.roundNumber, 0);
      expect(game.completedRounds, 0);
      expect(game.maxRounds, 3);
      expect(game.gameComplete, isFalse);
      expect(game.finalResult, isNull);
      expect(game.canStartNextRound, isFalse);
      expect(game.roundResults, isEmpty);
      expect(game.totalCapturesAcrossGame, 0);
      for (final player in game.players) {
        expect(game.totalCapturesOf(player), 0);
      }
    });

    test('rejects an invalid maxRounds', () {
      expect(
        () => GameState(players: makePlayers(2), maxRounds: 0),
        throwsArgumentError,
      );
    });

    test('starting the first round sets the round number to one', () {
      final game = readyGame(2, 2);
      expect(game.roundNumber, 0);
      game.startYamadaRound();
      expect(game.roundNumber, 1);
    });

    test('a completed round is recorded and the game stays open', () {
      final game = GameState(players: makePlayers(2), random: Random(2));
      playSeed22Round1(game);

      expect(game.roundNumber, 1);
      expect(game.completedRounds, 1);
      expect(game.roundResults, hasLength(1));
      expect(game.gameComplete, isFalse);
      expect(game.canStartNextRound, isTrue);
    });

    test('startNextRound deals fresh hands and resets per-round state', () {
      const seed = 22;
      final game = GameState(players: makePlayers(2), random: Random(seed));
      playSeed22Round1(game);
      final roundOneHands = {
        for (final player in game.players) player.id: [...game.handOf(player)],
      };

      game.startNextRound();

      // The deck is never reshuffled: the new hands are the next cards of the
      // same seeded deal, never the previous round's hands.
      final deck = Deck(random: Random(seed))..shuffle();
      deck.deal(4); // round 1 hands
      deck.dealOne(); // round 1 center
      deck.dealOne(); // round 1 draw
      final expectedRoundTwo = [deck.deal(2), deck.deal(2)];
      for (var i = 0; i < 2; i++) {
        final player = game.players[i];
        expect(game.handOf(player), isNot(roundOneHands[player.id]));
        expect(game.handOf(player), expectedRoundTwo[i]);
      }

      expect(game.roundNumber, 2);
      expect(game.completedRounds, 1);
      expect(game.allPlayersViewed, isFalse);
      expect(game.currentPlayerIndex, 0);
      expect(game.currentPlayer, game.players[0]);
      expect(game.roundStarted, isFalse);
      expect(game.centerPile, isEmpty);
      for (final player in game.players) {
        expect(game.capturedCardsOf(player), isEmpty);
        expect(game.captureCountOf(player), 0);
      }
    });

    test('startNextRound before the round completes is rejected', () {
      final game = readyGame(2, 2)..startYamadaRound();
      final centerBefore = game.centerPile;

      expect(() => game.startNextRound(), throwsA(isA<YamadaRoundException>()));
      expect(game.centerPile, centerBefore);
      expect(game.roundNumber, 1);
    });

    test('startNextRound before any round has started is rejected', () {
      final game = readyGame(2, 2);
      expect(() => game.startNextRound(), throwsA(isA<YamadaRoundException>()));
    });

    test('a new round restarts the private viewing flow', () {
      final game = GameState(players: makePlayers(2), random: Random(22));
      playSeed22Round1(game);
      game.startNextRound();

      expect(game.allPlayersViewed, isFalse);
      game.revealCurrentPlayer();
      expect(game.currentPlayerRevealed, isTrue);
      game.passToNextPlayer();
      expect(game.currentPlayer, game.players[1]);
      expect(game.currentPlayerRevealed, isFalse);
    });

    test(
      'a second round plays to completion and ends the game at maxRounds',
      () {
        final game = GameState(
          players: makePlayers(2),
          random: Random(22),
          maxRounds: 2,
        );
        playSeed22Round1(game);
        game.startNextRound();
        viewAll(game);
        game.startYamadaRound();
        expect(game.roundNumber, 2);
        playRound(game, [true, false]);

        expect(game.completedRounds, 2);
        expect(game.gameComplete, isTrue);
        expect(game.canStartNextRound, isFalse);
        expect(game.finalResult, isNotNull);
        expect(game.finalResult!.roundsPlayed, 2);
      },
    );
  });

  group('GameState cumulative scoring', () {
    test('total captures accumulate across rounds', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(22),
        maxRounds: 2,
      );
      // Round 1: player 0 captures, player 1 draws.
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);

      expect(game.totalCapturesOf(game.players[0]), 1);
      expect(game.totalCapturesOf(game.players[1]), 0);
      expect(game.totalCapturesAcrossGame, 1);

      game.startNextRound();
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]); // player 0 captures again
      game.drawToCenter(game.players[1]);

      expect(game.totalCapturesOf(game.players[0]), 2);
      expect(game.totalCapturesOf(game.players[1]), 0);
      expect(game.totalCapturesAcrossGame, 2);
    });

    test('current-round scores stay separate from cumulative totals', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(22),
        maxRounds: 2,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      game.startNextRound();
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();

      // Round 2 has not scored yet: current captures are zero while the
      // cumulative total still reflects round 1.
      expect(game.captureCountOf(game.players[0]), 0);
      expect(game.totalCapturedCards, 0);
      expect(game.totalCapturesOf(game.players[0]), 1);
      expect(game.totalCapturesAcrossGame, 1);
    });

    test('previous round results remain in the round history', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(22),
        maxRounds: 2,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      final roundOne = game.roundResult!;

      game.startNextRound();
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.drawToCenter(game.players[0]);
      game.drawToCenter(game.players[1]);

      expect(game.roundResults, hasLength(2));
      expect(
        game.roundResults[0].scores.values.toList(),
        roundOne.scores.values.toList(),
      );
    });

    test('scoring never mutates hands across rounds', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(22),
        maxRounds: 2,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      game.startNextRound();
      final roundTwo = {
        for (final player in game.players) player.id: [...game.handOf(player)],
      };
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);

      for (final player in game.players) {
        expect(game.handOf(player), roundTwo[player.id]);
      }
      expect(game.totalCapturesAcrossGame, 2);
    });
  });

  group('GameState cup persistence', () {
    test('penalties and cup state persist across rounds', () {
      // Seed 3: neither player can capture the round-1 center card, and
      // player 0 cannot capture the round-2 center card either.
      final game = GameState(
        players: makePlayers(2),
        random: Random(3),
        maxRounds: 2,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]); // wrong call
      game.callYamada(game.players[1]); // wrong call
      expect(game.penaltyCountOf(game.players[0]), 1);

      game.startNextRound();
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]); // wrong call again

      // Nothing reset: penalties are lifetime.
      expect(game.penaltyCountOf(game.players[0]), 2);
      expect(game.cupFillOf(game.players[0]), 2); // 2 % 3
      expect(game.cupDrinksOf(game.players[0]), 0);
      expect(game.penaltyCountOf(game.players[1]), 1);
    });

    test('cup capacity still applies across rounds', () {
      // Seed 3: wrong calls in both rounds (see the persistence test above).
      final game = GameState(
        players: makePlayers(2),
        random: Random(3),
        cupCapacity: 2,
        maxRounds: 2,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.callYamada(game.players[1]);
      // One penalty per player in round 1: the 2-slot cup is half full.
      expect(game.penaltyCountOf(game.players[0]), 1);
      expect(game.cupFillOf(game.players[0]), 1);
      expect(game.cupDrinksOf(game.players[0]), 0);

      game.startNextRound();
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]); // player 0's second penalty
      game.drawToCenter(game.players[1]);

      // The second penalty fills the cup: it overflows and empties while
      // the lifetime count keeps rising.
      expect(game.penaltyCountOf(game.players[0]), 2);
      expect(game.cupFillOf(game.players[0]), 0);
      expect(game.cupDrinksOf(game.players[0]), 1);
      expect(game.gameComplete, isTrue);
    });
  });

  group('GameState game completion', () {
    test('the game completes after maxRounds', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(22),
        maxRounds: 2,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      expect(game.gameComplete, isFalse);

      game.startNextRound();
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);

      expect(game.gameComplete, isTrue);
      expect(game.finalResult!.roundsPlayed, 2);
    });

    test('the game ends early when the deck cannot support another round', () {
      // 10 players all draw: round 1 consumes 20 hands + 1 center + 10
      // draws = 31 cards, leaving 21 — too few to guarantee a second round.
      final game = GameState(
        players: makePlayers(10),
        random: Random(1),
        maxRounds: 5,
      );
      for (var i = 0; i < 10; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      for (final player in game.players) {
        game.drawToCenter(player);
      }

      expect(game.roundComplete, isTrue);
      expect(game.gameComplete, isTrue);
      expect(game.finalResult!.roundsPlayed, 1);
      expect(game.canStartNextRound, isFalse);
      expect(() => game.startNextRound(), throwsA(isA<YamadaRoundException>()));
    });

    test('no further actions are allowed after the game completes', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(2),
        maxRounds: 1,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      expect(game.gameComplete, isTrue);

      expect(
        () => game.callYamada(game.players[0]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.drawToCenter(game.players[1]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(() => game.startNextRound(), throwsA(isA<YamadaRoundException>()));
    });
  });

  group('GameState Turtle King', () {
    test(
      'the assumed rule crowns the player with the fewest total captures',
      () {
        // Seed 22: player 0 captures in both rounds (2 total), player 1 never.
        final game = GameState(
          players: makePlayers(2),
          random: Random(22),
          maxRounds: 2,
        );
        for (var i = 0; i < 2; i++) {
          game.revealCurrentPlayer();
          game.passToNextPlayer();
        }
        game.startYamadaRound();
        game.callYamada(game.players[0]);
        game.drawToCenter(game.players[1]);
        game.startNextRound();
        for (var i = 0; i < 2; i++) {
          game.revealCurrentPlayer();
          game.passToNextPlayer();
        }
        game.startYamadaRound();
        game.callYamada(game.players[0]);
        game.drawToCenter(game.players[1]);

        final result = game.finalResult!;
        expect(result.scores.values.toList(), [2, 0]);
        expect(result.turtleKings, [game.players[1]]);
        expect(result.topScorers, [game.players[0]]);
        expect(result.roundsPlayed, 2);
      },
    );

    test('tied scorers share the Turtle King title', () {
      // Seed 13: player 0 captures round 1, player 1 captures round 2.
      final game = GameState(
        players: makePlayers(2),
        random: Random(13),
        maxRounds: 2,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      game.startNextRound();
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.drawToCenter(game.players[0]);
      game.callYamada(game.players[1]);

      final result = game.finalResult!;
      expect(result.scores.values.toList(), [1, 1]);
      expect(result.turtleKings, [game.players[0], game.players[1]]);
      expect(result.topScorers, [game.players[0], game.players[1]]);
    });

    test('no premature result before the game completes', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(22),
        maxRounds: 2,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);

      expect(game.gameComplete, isFalse);
      expect(game.finalResult, isNull);
    });

    test('the final result is stable after completion', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(22),
        maxRounds: 2,
      );
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);
      game.startNextRound();
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      game.startYamadaRound();
      game.callYamada(game.players[0]);
      game.drawToCenter(game.players[1]);

      final first = game.finalResult!;
      final second = game.finalResult!;
      expect(second.scores.values.toList(), first.scores.values.toList());
      expect(second.turtleKings, first.turtleKings);
      expect(second.roundsPlayed, first.roundsPlayed);
    });
  });

  group('GameState card integrity across rounds', () {
    test('no physical card is ever dealt twice across rounds', () {
      const seed = 22;
      final game = GameState(
        players: makePlayers(2),
        random: Random(seed),
        maxRounds: 2,
      );
      // Every card the deck ever deals, in order: 4 hands + 1 center + 1
      // draw in round 1, then 4 hands + 1 center + 2 draws in round 2.
      final deckDealt = <Card>[];

      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      deckDealt.addAll([
        ...game.handOf(game.players[0]),
        ...game.handOf(game.players[1]),
      ]);
      game.startYamadaRound();
      deckDealt.add(game.currentCenterCard!);
      game.callYamada(game.players[0]); // capture: no deck card consumed
      deckDealt.add(game.drawToCenter(game.players[1]));

      game.startNextRound();
      for (var i = 0; i < 2; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      deckDealt.addAll([
        ...game.handOf(game.players[0]),
        ...game.handOf(game.players[1]),
      ]);
      game.startYamadaRound();
      deckDealt.add(game.currentCenterCard!);
      deckDealt.add(game.drawToCenter(game.players[0]));
      deckDealt.add(game.drawToCenter(game.players[1]));

      expect(deckDealt, hasLength(13));
      expect(deckDealt.toSet(), hasLength(13)); // never re-dealt
      expect(game.remainingCards, 52 - 13);
    });

    test(
      'deterministic seeded games produce identical multi-round results',
      () {
        GameState play() {
          final game = GameState(
            players: makePlayers(2),
            random: Random(22),
            maxRounds: 2,
          );
          for (var round = 0; round < 2; round++) {
            for (var i = 0; i < 2; i++) {
              game.revealCurrentPlayer();
              game.passToNextPlayer();
            }
            game.startYamadaRound();
            game.callYamada(game.players[0]);
            game.drawToCenter(game.players[1]);
            if (!game.gameComplete) {
              game.startNextRound();
            }
          }
          return game;
        }

        final first = play();
        final second = play();

        expect(second.gameComplete, isTrue);
        expect(
          second.finalResult!.scores.values.toList(),
          first.finalResult!.scores.values.toList(),
        );
        // Players compare by identity, so compare names across games.
        List<String> kingNames(GameResult result) =>
            result.turtleKings.map((player) => player.name).toList();
        expect(kingNames(second.finalResult!), kingNames(first.finalResult!));
        expect(
          second.finalResult!.roundsPlayed,
          first.finalResult!.roundsPlayed,
        );
        expect(second.remainingCards, first.remainingCards);
        expect(second.totalCapturesAcrossGame, first.totalCapturesAcrossGame);
        expect(
          second.penaltyCountOf(second.players[0]),
          first.penaltyCountOf(first.players[0]),
        );
      },
    );
  });

  group('GameState elimination state', () {
    test('no player is eliminated on a new game', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      expect(game.eliminatedPlayers, isEmpty);
      expect(game.eliminationHistory, isEmpty);
      expect(game.activePlayerCount, 3);
      expect(game.activePlayers, game.players);
      for (final player in game.players) {
        expect(game.isEliminated(player), isFalse);
      }
    });

    test('the default elimination threshold is two full cups', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      expect(game.eliminationThreshold, 2);
    });

    test('a custom elimination threshold is honored', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 4,
      );
      expect(game.eliminationThreshold, 4);
    });

    test('rejects an invalid elimination threshold', () {
      expect(
        () => GameState(players: makePlayers(2), eliminationThreshold: 0),
        throwsArgumentError,
      );
    });
  });

  group('GameState elimination', () {
    /// Plays the private viewing phase for every active player.
    void viewAll(GameState game) {
      for (var i = 0; i < game.activePlayers.length; i++) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      expect(game.allPlayersViewed, isTrue);
    }

    /// Seed 1, 3 players, 1-slot cups, threshold 2: player 0 wrong-calls in
    /// round 1 and round 2, reaching two full cups (the threshold) on the
    /// round-2 action.
    GameState eliminatedGame() => GameState(
      players: makePlayers(3),
      random: Random(1),
      cupCapacity: 1,
      eliminationThreshold: 2,
    );

    /// Round 1 of [eliminatedGame]: player 0 wrong-calls, players 1 and 2
    /// draw. Completes the round.
    void playRoundOne(GameState game) {
      viewAll(game);
      game.startYamadaRound();
      game.callYamada(game.players[0]); // wrong call, one full cup
      game.drawToCenter(game.players[1]);
      game.drawToCenter(game.players[2]);
      expect(game.roundComplete, isTrue);
    }

    /// Starts round 2 and has player 0 wrong-call, which fills their second
    /// cup and eliminates them mid-round.
    void eliminatePlayerZero(GameState game) {
      game.startNextRound();
      viewAll(game);
      game.startYamadaRound();
      game.callYamada(game.players[0]); // wrong call, second full cup
      expect(game.isEliminated(game.players[0]), isTrue);
    }

    test(
      'a player reaching the threshold is eliminated after their action',
      () {
        final game = eliminatedGame();
        playRoundOne(game);
        expect(game.eliminatedPlayers, isEmpty);
        expect(game.penaltyCountOf(game.players[0]), 1);
        expect(game.cupDrinksOf(game.players[0]), 1); // below threshold

        eliminatePlayerZero(game);

        expect(game.penaltyCountOf(game.players[0]), 2);
        expect(game.cupDrinksOf(game.players[0]), 2);
        expect(game.isEliminated(game.players[0]), isTrue);
        expect(game.activePlayerCount, 2);
        // The elimination never interrupts an action halfway through and does
        // not end the game while the round is still playable.
        expect(game.roundComplete, isFalse);
        expect(game.gameComplete, isFalse);
        expect(game.roundCurrentPlayer, game.players[1]);
      },
    );

    test('elimination happens exactly once and records who, when, and why', () {
      final game = eliminatedGame();
      playRoundOne(game);
      eliminatePlayerZero(game);
      // The rest of the round plays out.
      game.drawToCenter(game.players[1]);
      game.drawToCenter(game.players[2]);
      expect(game.roundComplete, isTrue);

      expect(game.eliminationHistory, hasLength(1));
      final record = game.eliminationHistory.single;
      expect(record.player, game.players[0]);
      expect(record.round, 2);
      expect(record.reason, EliminationReason.cupOverflow);
      expect(game.eliminatedPlayers, [game.players[0]]);
    });

    test('an eliminated player cannot act and rejected actions leave the '
        'state unchanged', () {
      final game = eliminatedGame();
      playRoundOne(game);
      eliminatePlayerZero(game);
      final pileBefore = game.centerPile;
      final remainingBefore = game.remainingCards;
      final penaltiesBefore = game.penaltyCountOf(game.players[0]);

      expect(
        () => game.callYamada(game.players[0]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.drawToCenter(game.players[0]),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(game.centerPile, pileBefore);
      expect(game.remainingCards, remainingBefore);
      expect(game.penaltyCountOf(game.players[0]), penaltiesBefore);
      expect(game.roundPlayerIndex, 1); // still player 1's turn
    });

    test('turn progression skips eliminated players and the current player '
        'is always active', () {
      final game = eliminatedGame();
      playRoundOne(game);
      eliminatePlayerZero(game);

      expect(game.roundCurrentPlayer, game.players[1]);
      game.drawToCenter(game.players[1]);
      expect(game.roundCurrentPlayer, game.players[2]);
      game.drawToCenter(game.players[2]);
      expect(game.roundComplete, isTrue);
      // The eliminated player never received a turn after elimination.
      expect(game.roundPlayerIndex, 3);
    });

    test('the next round deals to active players only and resets per-round '
        'state', () {
      final game = eliminatedGame();
      playRoundOne(game);
      eliminatePlayerZero(game);
      game.drawToCenter(game.players[1]);
      game.drawToCenter(game.players[2]);

      game.startNextRound();
      viewAll(game);
      game.startYamadaRound();

      expect(game.roundPlayerCount, 2);
      expect(game.roundCurrentPlayer, game.players[1]);
      expect(game.hasHand(game.players[0]), isFalse);
      expect(game.hasHand(game.players[1]), isTrue);
      expect(game.hasHand(game.players[2]), isTrue);
      expect(game.handOf(game.players[1]), hasLength(2));
      expect(game.handOf(game.players[2]), hasLength(2));

      // All round-3 cards come from the same deck, never re-dealt.
      final allRoundCards = [
        ...game.handOf(game.players[1]),
        ...game.handOf(game.players[2]),
        game.currentCenterCard!,
      ];
      expect(allRoundCards.toSet(), hasLength(allRoundCards.length));

      // Deck accounting: rounds 1-2 each consumed 6 hands + 1 center + 2
      // draws (wrong calls draw no card), and round 3 has dealt 4 hands +
      // 1 center so far: 9 + 9 + 5 = 23 cards.
      expect(game.remainingCards, 52 - 23);
    });

    test('an eliminated player\'s history stays intact', () {
      final game = eliminatedGame();
      playRoundOne(game);
      eliminatePlayerZero(game);
      final captures = game.totalCapturesOf(game.players[0]);
      final penalties = game.penaltyCountOf(game.players[0]);
      final drinks = game.cupDrinksOf(game.players[0]);

      game.drawToCenter(game.players[1]);
      game.drawToCenter(game.players[2]);
      game.startNextRound();
      viewAll(game);
      game.startYamadaRound();
      game.drawToCenter(game.players[1]);
      game.drawToCenter(game.players[2]);
      expect(game.gameComplete, isTrue);

      // Nothing was deleted or reset for the eliminated player.
      expect(game.totalCapturesOf(game.players[0]), captures);
      expect(game.penaltyCountOf(game.players[0]), penalties);
      expect(game.cupDrinksOf(game.players[0]), drinks);
      expect(game.finalResult!.scores[game.players[0]], captures);
    });

    test('the game ends when fewer than two active players remain', () {
      // Seed 1, 2 players, 1-slot cups, threshold 1: player 0's wrong call in
      // round 1 fills their cup, eliminates them, and leaves one player.
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        cupCapacity: 1,
        eliminationThreshold: 1,
      );
      viewAll(game);
      game.startYamadaRound();
      game.callYamada(game.players[0]);

      expect(game.isEliminated(game.players[0]), isTrue);
      expect(game.activePlayerCount, 1);
      expect(game.gameComplete, isTrue);
      expect(game.finalResult, isNotNull);
      expect(game.canStartNextRound, isFalse);
      // No further rounds or actions are accepted.
      expect(() => game.startNextRound(), throwsA(isA<YamadaRoundException>()));
      expect(
        () => game.startYamadaRound(),
        throwsA(isA<YamadaRoundException>()),
      );
      expect(
        () => game.callYamada(game.players[1]),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('the final result exposes elimination and finalist data', () {
      final game = eliminatedGame();
      playRoundOne(game);
      eliminatePlayerZero(game);
      game.drawToCenter(game.players[1]);
      game.drawToCenter(game.players[2]);
      game.startNextRound();
      viewAll(game);
      game.startYamadaRound();
      game.drawToCenter(game.players[1]);
      game.drawToCenter(game.players[2]);
      expect(game.gameComplete, isTrue);

      final result = game.finalResult!;
      expect(result.finalists, [game.players[1], game.players[2]]);
      expect(result.eliminated, [game.players[0]]);
      expect(result.eliminations.single.round, 2);
      expect(result.eliminations.single.player, game.players[0]);
      expect(result.roundsPlayed, 3);
      // Nobody captured in this seed, so every player ties for fewest
      // captures — including the eliminated player, whose history still
      // counts under the assumed Turtle King rule.
      expect(result.scores.values.toList(), [0, 0, 0]);
      expect(result.turtleKings, hasLength(3));
    });

    test('deterministic seeded games produce identical elimination sequences '
        'and final results', () {
      GameState play() {
        final game = eliminatedGame();
        playRoundOne(game);
        eliminatePlayerZero(game);
        game.drawToCenter(game.players[1]);
        game.drawToCenter(game.players[2]);
        game.startNextRound();
        viewAll(game);
        game.startYamadaRound();
        game.drawToCenter(game.players[1]);
        game.drawToCenter(game.players[2]);
        return game;
      }

      final first = play();
      final second = play();

      List<String> names(List<Player> players) =>
          players.map((player) => player.name).toList();
      expect(
        second.eliminationHistory.map((record) => record.round).toList(),
        first.eliminationHistory.map((record) => record.round).toList(),
      );
      expect(names(second.eliminatedPlayers), names(first.eliminatedPlayers));
      expect(names(second.activePlayers), names(first.activePlayers));
      expect(
        second.finalResult!.scores.values.toList(),
        first.finalResult!.scores.values.toList(),
      );
      expect(
        names(second.finalResult!.finalists),
        names(first.finalResult!.finalists),
      );
      expect(
        names(second.finalResult!.turtleKings),
        names(first.finalResult!.turtleKings),
      );
      expect(second.remainingCards, first.remainingCards);
      expect(
        second.penaltyCountOf(second.players[0]),
        first.penaltyCountOf(first.players[0]),
      );
    });
  });
}
