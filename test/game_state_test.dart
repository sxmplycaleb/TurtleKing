import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

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
}
