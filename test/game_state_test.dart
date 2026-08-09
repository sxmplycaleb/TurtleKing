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
}
