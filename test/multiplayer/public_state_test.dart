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
      // YAMADA drinks the cup and the caller's turn repeats, so the round
      // completes with three consecutive holds: p0, p1, p2.
      game.callYamada(p0);
      game.holdOut(game.players[0]);
      game.holdOut(game.players[1]);
      game.holdOut(game.players[2]);
      // The YAMADA round ends without a reveal and the cup does not grow.
      final view = PublicStateView.fromGame(game);
      expect(view.lifetimeDrinks['p0'], 1);
      expect(view.calledYamada['p0'], isTrue);
      expect(view.roundComplete, isTrue);
      expect(view.canStartNextRound, isTrue);
      expect(view.cupSize, 'normal');
      expect(view.roundResults, hasLength(1));
      expect(view.roundResults.single.smallestHands, isEmpty);
      expect(view.events.map((e) => e.type), contains('playerCalledYamada'));
    });

    test(
      'a fully completed game projects eliminations and the final result',
      () {
        final game = testGame(2);
        // Play until one player is eliminated: give p0 six drinks directly
        // (each YAMADA call drinks and repeats p0's turn).
        final p0 = game.players[0];
        viewThrough(game);
        for (var i = 0; i < 6 && !game.gameComplete; i++) {
          game.callYamada(p0);
        }
        final view = PublicStateView.fromGame(game);
        expect(view.gameComplete, isTrue);
        expect(view.eliminatedPlayerIds, contains('p0'));
        expect(view.finalResult, isNotNull);
        expect(view.finalResult!.turtleKings, ['p1']);
        // The game ended mid-round through elimination, so no round was
        // finalized; the result still records the state faithfully.
        expect(view.finalResult!.roundsPlayed, 0);
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
        game.holdOut(game.players[0]);
        game.holdOut(game.players[1]);
        game.holdOut(game.players[2]);

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
      game.holdOut(game.players[0]);
      game.holdOut(game.players[1]);
      game.holdOut(game.players[2]);

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
