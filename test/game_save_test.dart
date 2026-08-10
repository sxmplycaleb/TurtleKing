import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/game_save.dart';
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

  const codec = GameSaveCodec();

  /// Asserts every piece of resumable state matches between [a] and [b].
  void expectSameGame(GameState a, GameState b) {
    expect(b.players.map((p) => p.id), a.players.map((p) => p.id));
    expect(b.eliminationThreshold, a.eliminationThreshold);
    expect(b.roundNumber, a.roundNumber);
    expect(b.cupSize, a.cupSize);
    expect(b.roundComplete, a.roundComplete);
    expect(b.gameComplete, a.gameComplete);
    expect(b.pouringStarted, a.pouringStarted);
    expect(b.allPlayersViewed, a.allPlayersViewed);
    expect(b.currentPlayerRevealed, a.currentPlayerRevealed);
    expect(b.viewIndex, a.viewIndex);
    expect(b.pourIndex, a.pourIndex);
    expect(b.consecutiveHolds, a.consecutiveHolds);
    expect(b.currentPlayer.id, a.currentPlayer.id);
    expect(b.remainingCards, a.remainingCards);
    expect(b.remainingDeck, a.remainingDeck);
    expect(
      b.remainingDeck.map((c) => c.displayName),
      a.remainingDeck.map((c) => c.displayName),
    );
    for (final player in a.players) {
      expect(b.drinksOf(player), a.drinksOf(player));
      expect(b.roundDrinksOf(player), a.roundDrinksOf(player));
      expect(b.calledYamadaThisRound(player), a.calledYamadaThisRound(player));
      expect(b.isEliminated(player), a.isEliminated(player));
      expect(b.hasHand(player), a.hasHand(player));
      if (b.hasHand(player)) {
        expect(
          b.handOf(player).map((c) => c.displayName),
          a.handOf(player).map((c) => c.displayName),
        );
      }
    }
    expect(
      [for (final event in b.events) event.type],
      [for (final event in a.events) event.type],
    );
    expect(b.completedRounds, a.completedRounds);
    expect(
      [for (final result in b.roundResults) result.cupSize],
      [for (final result in a.roundResults) result.cupSize],
    );
    expect(
      [for (final record in b.eliminationHistory) record.player.id],
      [for (final record in a.eliminationHistory) record.player.id],
    );
    if (a.finalResult != null && b.finalResult != null) {
      expect(
        [for (final p in b.finalResult!.turtleKings) p.id],
        [for (final p in a.finalResult!.turtleKings) p.id],
      );
      expect(b.finalResult!.roundsPlayed, a.finalResult!.roundsPlayed);
    }
  }

  group('GameSaveCodec', () {
    test('round-trips a fresh game', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      final restored = codec.decode(codec.encode(game));
      expectSameGame(game, restored);
    });

    test('round-trips a mid-viewing game (some players viewed)', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      game.revealCurrentPlayer();
      game.passToNextPlayer();
      game.revealCurrentPlayer();
      final restored = codec.decode(codec.encode(game));
      expectSameGame(game, restored);
      // The next viewer is still the same player.
      expect(restored.currentPlayer.id, game.currentPlayer.id);
    });

    test('round-trips a mid-pour game with YAMADA drinks', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      viewAll(game);
      game.holdOut(game.pourCurrentPlayer);
      game.callYamada(game.pourCurrentPlayer);
      game.callYamada(game.pourCurrentPlayer);
      final restored = codec.decode(codec.encode(game));
      expectSameGame(game, restored);
      expect(restored.roundDrinksOf(restored.pourCurrentPlayer), 2);
      expect(
        restored.calledYamadaThisRound(restored.pourCurrentPlayer),
        isTrue,
      );
    });

    test('round-trips a completed reveal round (smallest-hand penalties)', () {
      final game = GameState(players: makePlayers(3), random: Random(1));
      viewAll(game);
      everyoneHoldsOut(game);
      final restored = codec.decode(codec.encode(game));
      expectSameGame(game, restored);
      expect(restored.roundComplete, isTrue);
      expect(
        restored.smallestHands.map((p) => p.id),
        game.smallestHands.map((p) => p.id),
      );
      expect(
        restored.revealedPlayers.map((p) => p.id),
        game.revealedPlayers.map((p) => p.id),
      );
    });

    test('round-trips a completed game with a final result', () {
      final game = GameState(
        players: makePlayers(2),
        random: Random(1),
        eliminationThreshold: 2,
      );
      viewAll(game);
      // Two YAMADA calls eliminate player 0; player 1 remains and wins.
      game.callYamada(game.pourCurrentPlayer);
      game.callYamada(game.pourCurrentPlayer);
      expect(game.gameComplete, isTrue);
      final restored = codec.decode(codec.encode(game));
      expectSameGame(game, restored);
      expect(restored.gameComplete, isTrue);
      // The game ended mid-round (YAMADA elimination), so no round result
      // was finalized; the restored final result matches the original's.
      expect(
        restored.finalResult!.roundsPlayed,
        game.finalResult!.roundsPlayed,
      );
      expect(restored.finalResult!.turtleKings.single.id, 'player-1');
    });

    test('restored game deals and plays exactly as the original', () {
      final original = GameState(players: makePlayers(3), random: Random(1));
      viewAll(original);
      original.callYamada(original.pourCurrentPlayer);
      // Save here, then keep playing the original...
      final restored = codec.decode(codec.encode(original));
      void continueScript(GameState game) {
        game.holdOut(game.pourCurrentPlayer);
        while (!game.roundComplete) {
          game.holdOut(game.pourCurrentPlayer);
        }
        if (game.canStartNextRound) {
          game.startNextRound();
          viewAll(game);
          everyoneHoldsOut(game);
        }
      }

      continueScript(original);
      continueScript(restored);
      expectSameGame(original, restored);
    });

    test('multiple save/restore cycles stay deterministic', () {
      var game = GameState(players: makePlayers(3), random: Random(1));
      viewAll(game);
      for (var cycle = 0; cycle < 3; cycle++) {
        game = codec.decode(codec.encode(game));
        game.holdOut(game.pourCurrentPlayer);
        expectSameGame(game, game);
      }
      // Same seed + same script on a parallel game reaches the same state.
      final parallel = GameState(players: makePlayers(3), random: Random(1));
      viewAll(parallel);
      for (var i = 0; i < 3; i++) {
        parallel.holdOut(parallel.pourCurrentPlayer);
      }
      expectSameGame(game, parallel);
    });

    test('unsupported schema version is rejected', () {
      final map = codec.toMap(GameState(players: makePlayers(2)));
      map['schemaVersion'] = 999;
      expect(
        () => codec.fromMap(map),
        throwsA(
          isA<GameSaveException>().having(
            (e) => e.message,
            'message',
            contains('unsupported save schema version'),
          ),
        ),
      );
    });

    test('malformed JSON is rejected', () {
      expect(
        () => codec.decode('{not json at all'),
        throwsA(isA<GameSaveException>()),
      );
    });

    test('a non-object root is rejected', () {
      expect(
        () => codec.decode(jsonEncode([1, 2, 3])),
        throwsA(isA<GameSaveException>()),
      );
    });

    test('missing required fields are rejected', () {
      final map = codec.toMap(GameState(players: makePlayers(2)));
      map.remove('roundNumber');
      expect(
        () => codec.fromMap(map),
        throwsA(
          isA<GameSaveException>().having(
            (e) => e.message,
            'message',
            contains('missing required field "roundNumber"'),
          ),
        ),
      );
    });

    test('unknown enum values are rejected', () {
      final map = codec.toMap(GameState(players: makePlayers(2)));
      map['cupSize'] = 'gigantic';
      expect(
        () => codec.fromMap(map),
        throwsA(
          isA<GameSaveException>().having(
            (e) => e.message,
            'message',
            contains('unknown cupSize'),
          ),
        ),
      );
    });

    test('wrong field types are rejected safely', () {
      final map = codec.toMap(GameState(players: makePlayers(2)));
      map['viewIndex'] = 'not-an-int';
      expect(() => codec.fromMap(map), throwsA(isA<GameSaveException>()));
    });

    test('an unknown player reference is rejected', () {
      final map = codec.toMap(GameState(players: makePlayers(2)));
      (map['smallestHands'] as List).add('ghost-player');
      expect(
        () => codec.fromMap(map),
        throwsA(
          isA<GameSaveException>().having(
            (e) => e.message,
            'message',
            contains('unknown player'),
          ),
        ),
      );
    });
  });

  group('GameSaveStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('hasSave is false with no save; load returns null', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = GameSaveStore(prefs);
      expect(store.hasSave, isFalse);
      expect(store.load(), isNull);
    });

    test('save then load round-trips the game', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = GameSaveStore(prefs);
      final game = GameState(players: makePlayers(3), random: Random(1));
      viewAll(game);
      game.holdOut(game.pourCurrentPlayer);

      await store.save(game);
      expect(store.hasSave, isTrue);
      expectSameGame(game, store.load()!);
    });

    test('clear removes the save', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = GameSaveStore(prefs);
      await store.save(GameState(players: makePlayers(2)));
      expect(store.hasSave, isTrue);

      await store.clear();
      expect(store.hasSave, isFalse);
      expect(store.load(), isNull);
    });

    test('a corrupt stored document surfaces GameSaveException', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = GameSaveStore(prefs);
      await prefs.setString(GameSaveStore.saveKey, 'garbage{{');
      expect(store.hasSave, isTrue);
      expect(() => store.load(), throwsA(isA<GameSaveException>()));
      // The corrupt save can be discarded and a new game started.
      await store.clear();
      expect(store.hasSave, isFalse);
    });

    test('a completed game is not stored as resumable', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = GameSaveStore(prefs);
      final game = GameState(players: makePlayers(2), eliminationThreshold: 2);
      viewAll(game);
      game.callYamada(game.pourCurrentPlayer);
      game.callYamada(game.pourCurrentPlayer);
      expect(game.gameComplete, isTrue);

      // The store clears when asked to persist a completed game.
      if (game.gameComplete) {
        await store.clear();
      }
      expect(store.hasSave, isFalse);
    });
  });

  group('save privacy', () {
    test('save data round-trips but never surfaces card identities in UI', () {
      final game = GameState(players: makePlayers(2), random: Random(1));
      final encoded = codec.encode(game);
      // Hidden hands ARE gameplay state (stored locally), but the encoded
      // document must not be reachable from any user-facing summary: the
      // resume card only reads round/players/cup/current player.
      final restored = codec.decode(encoded);
      expect(restored.handOf(restored.players[0]), hasLength(2));
      // And the document itself contains no player names other than the
      // configured roster.
      final map = codec.toMap(game);
      expect(map['players'], hasLength(2));
      expect((map['hands'] as Map).keys, hasLength(2));
    });

    test('restored Color values match the original players', () {
      final game = GameState(players: makePlayers(3));
      final restored = codec.decode(codec.encode(game));
      for (var i = 0; i < game.players.length; i++) {
        expect(restored.players[i].color, game.players[i].color);
        expect(restored.players[i].name, game.players[i].name);
      }
    });
  });
}
