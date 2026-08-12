import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/errors.dart';
import 'package:turtle_king/multiplayer/private_state.dart';

import 'helpers.dart';

void main() {
  group('PrivateStateView.forVisibleCard', () {
    test('delivers exactly the recipient\'s own visible card', () {
      final game = testGame(3);
      final a = game.players[0];
      final view = PrivateStateView.forVisibleCard(game, a);

      expect(view.recipientPlayerId, a.id);
      expect(view.round, game.roundNumber);
      expect(view.card.suit, game.visibleCardOf(a).suit.name);
      expect(view.card.rank, game.visibleCardOf(a).rank.name);
      // The view reflects the live dealt card, not a fixed value.
      expect(
        '${view.card.suit}/${view.card.rank}',
        '${game.visibleCardOf(a).suit.name}/${game.visibleCardOf(a).rank.name}',
      );
    });

    test('the hidden second card never appears in a private update', () {
      final game = testGame(2);
      final a = game.players[0];
      final hand = game.handOf(a);
      final hidden = hand[1]; // the second card the player may NOT see yet

      final view = PrivateStateView.forVisibleCard(game, a);
      final json = jsonEncode(view.toJson());
      expect(json, isNot(contains(hidden.suit.name)));
      expect(json, isNot(contains(hidden.rank.name)));
    });

    test('a private update for player A cannot carry player B\'s card', () {
      final game = testGame(3);
      final a = game.players[0];
      final b = game.players[1];

      final forA = PrivateStateView.forVisibleCard(game, a);
      final forB = PrivateStateView.forVisibleCard(game, b);

      // The narrow API binds one recipient to one card; the factory reads
      // through visibleCardOf for exactly that player.
      expect(forA.recipientPlayerId, a.id);
      expect(forB.recipientPlayerId, b.id);
      expect(forA.card.rank, game.visibleCardOf(a).rank.name);
      expect(forB.card.rank, game.visibleCardOf(b).rank.name);
      // B's identity and cards never ride inside A's update.
      expect(jsonEncode(forA.toJson()), isNot(contains(b.id)));
    });

    test('a private update carries exactly one card', () {
      final game = testGame(2);
      final view = PrivateStateView.forVisibleCard(game, game.players[0]);
      final decoded = jsonDecode(jsonEncode(view.toJson()));
      final cardKeys = <String>[
        for (final entry in (decoded['card'] as Map).entries)
          entry.key as String,
      ];
      expect(cardKeys, containsAll(['suit', 'rank']));
      // No list, no second card, no hand anywhere.
      expect(decoded.containsKey('hand'), isFalse);
      expect(decoded.containsKey('hands'), isFalse);
      expect(decoded.containsKey('deck'), isFalse);
    });
  });

  group('PrivateStateView round-trip and validation', () {
    test('fromJson(toJson()) reproduces the same view', () {
      final game = testGame(2);
      final original = PrivateStateView.forVisibleCard(game, game.players[0]);
      final restored = PrivateStateView.fromJson(original.toJson());
      expect(restored.recipientPlayerId, original.recipientPlayerId);
      expect(restored.round, original.round);
      expect(restored.card.suit, original.card.suit);
      expect(restored.card.rank, original.card.rank);
      expect(jsonEncode(restored.toJson()), jsonEncode(original.toJson()));
    });

    test('malformed private updates are rejected', () {
      expect(
        () => PrivateStateView.fromJson(null),
        throwsA(isA<MultiplayerProtocolException>()),
      );
      expect(
        () =>
            PrivateStateView.fromJson({'recipientPlayerId': 'p0', 'round': 1}),
        throwsA(isA<MultiplayerProtocolException>()),
      );
      expect(
        () => PrivateStateView.fromJson({
          'recipientPlayerId': 'p0',
          'round': 1,
          'card': {'suit': 'hearts'},
        }),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });
  });
}
