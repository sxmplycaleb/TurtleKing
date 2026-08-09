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
      expect(
        () => GameState(players: makePlayers(1)),
        throwsArgumentError,
      );
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
        for (final player in game.players)
          player.id: [...game.handOf(player)],
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

    test('the initial center card comes from the original deck, never a hand',
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
    });

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

      final captured = game.callYamada(game.players[0]);

      expect(captured, center);
      expect(game.capturedCardsOf(game.players[0]), [center]);
      expect(game.capturedCardsOf(game.players[1]), isEmpty);
      expect(game.centerPile, isEmpty);
      expect(game.currentCenterCard, isNull);
      expect(game.remainingCards, 47); // capturing draws no card
      expect(game.roundPlayerIndex, 1);
      expect(game.roundCurrentPlayer, game.players[1]);
      expect(game.currentPlayerActed, isFalse);
    });

    test('callYamada is rejected when the center card is not between the '
        "player's cards", () {
      // Player 0 holds Queen and Jack; center is 3.
      final game = readyGame(2, 1)..startYamadaRound();
      expect(game.canCallYamada, isFalse);

      expect(
        () => game.callYamada(game.players[0]),
        throwsA(isA<YamadaRoundException>()),
      );
      // The rejected action leaves the state unchanged.
      expect(game.centerPile, hasLength(1));
      expect(game.capturedCardsOf(game.players[0]), isEmpty);
      expect(game.roundPlayerIndex, 0);
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

    test('acting before the round starts is rejected without mutating state',
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
    });

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
}
