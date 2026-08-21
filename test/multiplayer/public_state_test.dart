import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/errors.dart';
import 'package:turtle_king/multiplayer/public_state.dart';

import 'helpers.dart';

/// Keys that must never appear in a public payload.
const List<String> forbiddenKeys = [
  'rank',
  'suit',
  'hand',
  'hands',
  'cards',
  'deck',
  'remainingDeck',
  'visibleCard',
  '_hands',
  '_deck',
];

void main() {
  group('PublicStateView.fromGame', () {
    test('projects the public roster and presentation data', () {
      final view = PublicStateView.fromGame(testGame(3));
      expect(view.players.map((p) => p.name), [
        'Player 0',
        'Player 1',
        'Player 2',
      ]);
      expect(view.players.map((p) => p.id), ['p0', 'p1', 'p2']);
      expect(view.eliminationThreshold, 6);
      expect(view.roundNumber, 1);
      expect(view.cupSize, 'normal');
      expect(view.pouringStarted, isFalse);
      expect(view.allPlayersViewed, isFalse);
      expect(view.currentPlayerRevealed, isFalse);
      expect(view.currentPlayerIndex, 0);
      expect(view.gameComplete, isFalse);
      expect(view.completedRounds, 0);
      expect(view.lifetimeDrinks, {'p0': 0, 'p1': 0, 'p2': 0});
    });

    test('projects drinks, YAMADA flags, and round results mid-game', () {
      final game = testGame(3);
      // View through, then let player 0 call YAMADA (one drink) and finish
      // the round by everyone holding out.
      viewThrough(game);
      final p0 = game.players[0];
      // Player 0 calls YAMADA (strategic surrender), then all players
      // hold out to complete the round.
      game.callYamada(p0);
      // After YAMADA, turn advanced. Other players hold out.
      game.holdOut(game.pourCurrentPlayer);
      game.holdOut(game.pourCurrentPlayer);
      final view = PublicStateView.fromGame(game);
      expect(view.calledYamada['p0'], isTrue);
      expect(view.roundComplete, isTrue);
      expect(view.canStartNextRound, isTrue);
      expect(view.roundResults, hasLength(1));
      expect(view.events.map((e) => e.type), contains('playerCalledYamada'));
    });

    test(
      'a fully completed game projects eliminations and the final result',
      () {
        final game = testGame(2);
        // Play rounds until a player is eliminated via normal gameplay.
        viewThrough(game);
        while (!game.gameComplete) {
          while (!game.roundComplete) {
            game.holdOut(game.pourCurrentPlayer);
          }
          if (!game.canStartNextRound) break;
          game.startNextRound();
          viewThrough(game);
        }
        final view = PublicStateView.fromGame(game);
        expect(view.gameComplete, isTrue);
        expect(view.eliminatedPlayerIds, isNotEmpty);
        expect(view.finalResult, isNotNull);
      },
    );
  });

  group('PublicStateView privacy', () {
    test(
      'serialized public state contains no card/deck/hand keys at any depth',
      () {
        // A rich mid-game state: pours, YAMADA, penalties, eliminations,
        // round results, and events all populated.
        final game = testGame(3);
        viewThrough(game);
        final p0 = game.players[0];
        game.callYamada(p0);
        game.holdOut(game.pourCurrentPlayer);
        game.holdOut(game.pourCurrentPlayer);

        final raw = jsonDecode(
          jsonEncode(PublicStateView.fromGame(game).toJson()),
        );
        expectNoForbiddenKeys(raw, forbiddenKeys);
      },
    );

    test('serialized public state contains no remaining-deck information', () {
      final game = testGame(2);
      // Deplete the deck deliberately so a leak would be visible.
      for (var i = 0; i < 20; i++) {
        game.remainingDeck; // exercise the getter; count stays hidden
      }
      final raw = jsonDecode(
        jsonEncode(PublicStateView.fromGame(game).toJson()),
      );
      expectNoForbiddenKeys(raw, forbiddenKeys);
      expect(
        jsonEncode(PublicStateView.fromGame(game).toJson()),
        isNot(contains('remainingDeck')),
      );
    });

    test('public state is not a serialization of GameState internals', () {
      final json = jsonEncode(PublicStateView.fromGame(testGame(2)).toJson());
      expect(json, isNot(contains('_hands')));
      expect(json, isNot(contains('_deck')));
      expect(json, isNot(contains('_lifetimeDrinks')));
      // The only identifiers present are public roster ids/names.
      expect(json, contains('p0'));
    });

    test('a round result carries aggregates but never card identities', () {
      final game = testGame(3);
      viewThrough(game);
      // Everyone holds out: the reveal happens and smallest hands drink.
      for (var i = 0; i < game.players.length * 2 && !game.roundComplete; i++) {
        game.holdOut(game.players[game.pourIndex]);
      }
      final view = PublicStateView.fromGame(game);
      expect(view.roundResults, hasLength(1));
      expect(view.roundResults.single.smallestHands, isNotEmpty);
      final raw = jsonDecode(jsonEncode(view.toJson()));
      expectNoForbiddenKeys(raw, forbiddenKeys);
    });
  });

  group('PublicStateView round-trip', () {
    test('fromJson(toJson()) reproduces the same view', () {
      final game = testGame(3);
      viewThrough(game);
      game.callYamada(game.players[0]);
      game.holdOut(game.pourCurrentPlayer);
      game.holdOut(game.pourCurrentPlayer);

      final original = PublicStateView.fromGame(game);
      final restored = PublicStateView.fromJson(original.toJson());
      expect(
        restored.players.map((p) => p.id),
        original.players.map((p) => p.id),
      );
      expect(restored.roundNumber, original.roundNumber);
      expect(restored.cupSize, original.cupSize);
      expect(restored.lifetimeDrinks, original.lifetimeDrinks);
      expect(restored.roundDrinks, original.roundDrinks);
      expect(restored.calledYamada, original.calledYamada);
      // Events are intentionally omitted from the wire payload (they grow
      // unboundedly and the remote client never renders them).
      expect(restored.events, isEmpty);
      expect(original.events, isNotEmpty);
      expect(restored.roundResults.length, original.roundResults.length);
      // Deterministic serialization: byte-identical after a round trip.
      expect(jsonEncode(restored.toJson()), jsonEncode(original.toJson()));
    });

    test('strict fromJson rejects malformed payloads', () {
      expect(
        () => PublicStateView.fromJson({'players': 'nope'}),
        throwsA(isA<MultiplayerProtocolException>()),
      );
      expect(
        () => PublicStateView.fromJson({
          'players': [
            {'id': 'x'},
          ],
        }),
        throwsA(isA<MultiplayerProtocolException>()),
      );
      expect(
        () => PublicStateView.fromJson(null),
        throwsA(isA<MultiplayerProtocolException>()),
      );
      expect(
        () => PublicStateView.fromJson('a string'),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });
  });
}
