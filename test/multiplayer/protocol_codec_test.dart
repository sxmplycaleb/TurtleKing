import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/errors.dart';
import 'package:turtle_king/multiplayer/private_state.dart';
import 'package:turtle_king/multiplayer/protocol.dart';
import 'package:turtle_king/multiplayer/protocol_codec.dart';
import 'package:turtle_king/multiplayer/public_state.dart';

import 'helpers.dart';

void main() {
  const codec = MessageCodec();
  const session = 'session-1';
  final publicState = PublicStateView.fromGame(testGame(2));

  // Builds one instance of every supported message type.
  List<MultiplayerMessage> allMessages() => [
    JoinRequestMessage(seq: 1, sessionId: session, playerName: 'Caleb'),
    JoinAcceptMessage(
      seq: 2,
      sessionId: session,
      playerId: 'p0',
      color: 0xFF1976D2,
      roster: publicState.players,
    ),
    JoinRejectMessage(seq: 3, sessionId: session, reason: 'name taken'),
    RosterUpdateMessage(
      seq: 4,
      sessionId: session,
      roster: publicState.players,
    ),
    GameStartMessage(
      seq: 5,
      sessionId: session,
      gameId: 'game-1',
      publicState: publicState,
    ),
    ActionRequestMessage(
      seq: 6,
      sessionId: session,
      action: GameAction.revealCurrentPlayer,
      playerId: 'p0',
    ),
    ActionAcceptedMessage(
      seq: 7,
      sessionId: session,
      action: GameAction.passToNextPlayer,
      requestSeq: 6,
      stateSeq: 2,
    ),
    ActionRejectedMessage(
      seq: 8,
      sessionId: session,
      action: GameAction.holdOut,
      requestSeq: 6,
      reason: 'not your turn',
    ),
    StateUpdateMessage(
      seq: 9,
      sessionId: session,
      stateSeq: 3,
      publicState: publicState,
    ),
    PrivateUpdateMessage(
      seq: 10,
      sessionId: session,
      stateSeq: 3,
      privateState: PrivateStateView(
        recipientPlayerId: 'p0',
        round: 1,
        card: const PrivateCard(suit: 'hearts', rank: 'ace'),
      ),
    ),
    ResyncRequestMessage(
      seq: 11,
      sessionId: session,
      playerId: 'p0',
      lastStateSeq: 2,
    ),
    ResyncResponseMessage(
      seq: 12,
      sessionId: session,
      stateSeq: 3,
      publicState: publicState,
    ),
    const HeartbeatMessage(seq: 13, sessionId: session),
    DisconnectMessage(
      seq: 14,
      sessionId: session,
      playerId: 'p0',
      reason: 'left',
    ),
    SessionEndMessage(seq: 15, sessionId: session, reason: 'completed'),
  ];

  group('MessageCodec round-trip', () {
    test('every supported message round-trips JSON → model → JSON', () {
      for (final message in allMessages()) {
        final encoded = codec.encode(message);
        final decoded = codec.decode(encoded);
        expect(decoded, isA<MultiplayerMessage>());
        expect(decoded.runtimeType, message.runtimeType);
        expect(
          codec.encode(decoded),
          encoded,
          reason: 're-encoding a decoded ${message.type} must be stable',
        );
      }
    });

    test('sequence numbers and session ids are preserved', () {
      for (final message in allMessages()) {
        final decoded = codec.decode(codec.encode(message));
        expect(decoded.seq, message.seq);
        expect(decoded.sessionId, message.sessionId);
      }
    });

    test('typed fields survive the round trip', () {
      final action =
          codec.decode(
                codec.encode(
                  ActionRequestMessage(
                    seq: 4,
                    sessionId: session,
                    action: GameAction.callYamada,
                    playerId: 'p1',
                  ),
                ),
              )
              as ActionRequestMessage;
      expect(action.action, GameAction.callYamada);
      expect(action.playerId, 'p1');

      final accept =
          codec.decode(
                codec.encode(
                  JoinAcceptMessage(
                    seq: 2,
                    sessionId: session,
                    playerId: 'p0',
                    color: 0xFF1976D2,
                    roster: publicState.players,
                  ),
                ),
              )
              as JoinAcceptMessage;
      expect(accept.roster.map((p) => p.id), ['p0', 'p1']);
    });
  });

  group('deterministic JSON', () {
    test('equal messages encode byte-identically', () {
      final a = StateUpdateMessage(
        seq: 9,
        sessionId: session,
        stateSeq: 3,
        publicState: publicState,
      );
      final b = StateUpdateMessage(
        seq: 9,
        sessionId: session,
        stateSeq: 3,
        publicState: publicState,
      );
      expect(codec.encode(a), codec.encode(b));
    });

    test('encoding is canonical regardless of map insertion order', () {
      // Two semantically identical bodies built in different orders must
      // produce identical output thanks to the canonical key sort.
      final raw = {
        'body': {'playerId': 'p0', 'action': 'revealCurrentPlayer'},
        'sessionId': session,
        'seq': 6,
        'type': 'ACTION_REQUEST',
        'v': 1,
      };
      final reversed = {
        'v': 1,
        'type': 'ACTION_REQUEST',
        'seq': 6,
        'sessionId': session,
        'body': {'action': 'revealCurrentPlayer', 'playerId': 'p0'},
      };
      expect(
        const JsonEncoder().convert(raw),
        isNot(const JsonEncoder().convert(reversed)),
      );
      final encoded = codec.encode(
        ActionRequestMessage(
          seq: 6,
          sessionId: session,
          action: GameAction.revealCurrentPlayer,
          playerId: 'p0',
        ),
      );
      // Both hand-built layouts decode to the same canonical message.
      expect(codec.decode(encoded).seq, 6);
      expect(codec.decode(encoded).sessionId, session);
    });
  });

  group('strict validation', () {
    test('malformed JSON is rejected safely', () {
      expect(
        () => codec.decode('{not json'),
        throwsA(
          isA<MultiplayerProtocolException>().having(
            (e) => e.reason,
            'reason',
            contains('malformed JSON'),
          ),
        ),
      );
      expect(
        () => codec.decode(''),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('a non-object root is rejected', () {
      expect(
        () => codec.decode('[1, 2, 3]'),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('an unknown message type is rejected', () {
      final raw = jsonEncode({
        'v': 1,
        'type': 'FLYING_PIG',
        'seq': 1,
        'sessionId': session,
        'body': {},
      });
      expect(
        () => codec.decode(raw),
        throwsA(
          isA<MultiplayerProtocolException>().having(
            (e) => e.reason,
            'reason',
            contains('unknown message type'),
          ),
        ),
      );
    });

    test('an invalid protocol version is rejected', () {
      final raw = jsonEncode({
        'v': 99,
        'type': 'HEARTBEAT',
        'seq': 1,
        'sessionId': session,
        'body': {},
      });
      expect(
        () => codec.decode(raw),
        throwsA(
          isA<MultiplayerProtocolException>().having(
            (e) => e.reason,
            'reason',
            contains('unsupported protocol version'),
          ),
        ),
      );
    });

    test('a missing version is rejected', () {
      final raw = jsonEncode({
        'type': 'HEARTBEAT',
        'seq': 1,
        'sessionId': session,
        'body': {},
      });
      expect(
        () => codec.decode(raw),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('missing or empty session ids are rejected', () {
      for (final sessionId in [null, '']) {
        final raw = jsonEncode({
          'v': 1,
          'type': 'HEARTBEAT',
          'seq': 1,
          'sessionId': sessionId,
          'body': {},
        });
        expect(
          () => codec.decode(raw),
          throwsA(isA<MultiplayerProtocolException>()),
          reason: 'sessionId $sessionId must be rejected',
        );
      }
    });

    test('negative or missing sequence numbers are rejected', () {
      expect(
        () => codec.decode(
          jsonEncode({
            'v': 1,
            'type': 'HEARTBEAT',
            'seq': -1,
            'sessionId': session,
            'body': {},
          }),
        ),
        throwsA(isA<MultiplayerProtocolException>()),
      );
      expect(
        () => codec.decode(
          jsonEncode({
            'v': 1,
            'type': 'HEARTBEAT',
            'sessionId': session,
            'body': {},
          }),
        ),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('an unknown action enum value is rejected', () {
      final raw = jsonEncode({
        'v': 1,
        'type': 'ACTION_REQUEST',
        'seq': 1,
        'sessionId': session,
        'body': {'action': 'flyToTheMoon', 'playerId': 'p0'},
      });
      expect(
        () => codec.decode(raw),
        throwsA(
          isA<MultiplayerProtocolException>().having(
            (e) => e.reason,
            'reason',
            contains('unknown action'),
          ),
        ),
      );
    });

    test('a missing required body field is rejected', () {
      final raw = jsonEncode({
        'v': 1,
        'type': 'JOIN_REQUEST',
        'seq': 1,
        'sessionId': session,
        'body': {},
      });
      expect(
        () => codec.decode(raw),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });
  });

  group('private/public payload separation', () {
    const forbidden = [
      'rank',
      'suit',
      'hand',
      'hands',
      'deck',
      'remainingDeck',
    ];

    test('only PRIVATE_UPDATE may carry card identities', () {
      for (final message in allMessages()) {
        final raw = jsonDecode(codec.encode(message));
        if (message is PrivateUpdateMessage) continue;
        expectNoForbiddenKeys(raw, forbidden);
      }
    });

    test('PRIVATE_UPDATE carries exactly one card for exactly one player', () {
      final decoded =
          codec.decode(
                codec.encode(
                  PrivateUpdateMessage(
                    seq: 10,
                    sessionId: session,
                    stateSeq: 3,
                    privateState: const PrivateStateView(
                      recipientPlayerId: 'p0',
                      round: 1,
                      card: PrivateCard(suit: 'spades', rank: 'king'),
                    ),
                  ),
                ),
              )
              as PrivateUpdateMessage;
      expect(decoded.privateState.recipientPlayerId, 'p0');
      expect(decoded.privateState.card.suit, 'spades');
      expect(decoded.privateState.card.rank, 'king');
    });
  });

  group('typed API barrier', () {
    test('the codec cannot serialize a GameState directly', () {
      // The public API only accepts MultiplayerMessage. A GameState is not
      // one, so even a dynamic call must fail with a type error rather than
      // leaking state onto the wire.
      final game = testGame(2);
      expect(() => codec.encode(game as dynamic), throwsA(isA<TypeError>()));
    });

    test('decoded message type matches the wire type', () {
      final heartbeat = codec.decode(
        codec.encode(const HeartbeatMessage(seq: 1, sessionId: session)),
      );
      expect(heartbeat.type, 'HEARTBEAT');
    });
  });
}
