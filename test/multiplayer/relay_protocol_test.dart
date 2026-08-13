import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/errors.dart';
import 'package:turtle_king/multiplayer/relay_protocol.dart';

void main() {
  group('relay frame encoding', () {
    test('every frame round-trips through decodeRelayFrame', () {
      final frames = <RelayFrame>[
        const RelayHostFrame(
          sessionId: 'tk-1',
          joinCode: '483729',
          displayName: 'Friday',
          maxPlayers: 6,
        ),
        const RelayLookupFrame(joinCode: '483729'),
        const RelayJoinFrame(sessionId: 'tk-1'),
        const RelaySendFrame(
          sessionId: 'tk-1',
          to: kRelayHostMember,
          payload: '{"type":"JOIN_REQUEST"}',
        ),
        const RelayKickFrame(sessionId: 'tk-1', member: 'm1'),
        const RelayLeaveFrame(),
        const RelayRegisteredFrame(sessionId: 'tk-1', member: kRelayHostMember),
        const RelayLookupAckFrame(sessionId: 'tk-1', displayName: 'Friday'),
        const RelayLookupErrFrame(reason: 'no game found with this code'),
        const RelayJoinAckFrame(sessionId: 'tk-1', member: 'm1'),
        const RelayJoinErrFrame(reason: 'session full'),
        const RelayPeerFrame(
          sessionId: 'tk-1',
          from: kRelayHostMember,
          payload: '{"type":"STATE_UPDATE"}',
        ),
        const RelayPeerJoinedFrame(sessionId: 'tk-1', member: 'm1'),
        const RelayPeerLeftFrame(
          sessionId: 'tk-1',
          member: 'm1',
          reason: 'left',
        ),
        const RelayErrFrame(reason: 'not allowed'),
      ];
      for (final frame in frames) {
        final decoded = decodeRelayFrame(frame.encode());
        expect(decoded.runtimeType, frame.runtimeType, reason: frame.type);
        expect(decoded.encode(), frame.encode(), reason: 'deterministic');
      }
    });

    test('encoding is canonical and deterministic', () {
      const a = RelayHostFrame(
        sessionId: 'tk-1',
        joinCode: '483729',
        displayName: 'G',
      );
      const b = RelayHostFrame(
        sessionId: 'tk-1',
        joinCode: '483729',
        displayName: 'G',
      );
      expect(a.encode(), b.encode());
      expect(a.encode(), contains('"code":"483729"'));
    });
  });

  group('relay frame validation', () {
    test('rejects malformed JSON without throwing', () {
      expect(
        () => decodeRelayFrame('not json'),
        throwsA(isA<MultiplayerProtocolException>()),
      );
      expect(
        () => decodeRelayFrame('{}'),
        throwsA(isA<MultiplayerProtocolException>()),
      );
      expect(
        () => decodeRelayFrame('[]'),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('rejects an unknown protocol version', () {
      final raw = const RelayHostFrame(
        sessionId: 's',
        joinCode: '483729',
        displayName: 'G',
      ).encode().replaceFirst('"v":$kRelayProtocolVersion', '"v":99');
      expect(
        () => decodeRelayFrame(raw),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('rejects an unknown frame type', () {
      const raw = '{"v":1,"t":"NOPE","sid":"s"}';
      expect(
        () => decodeRelayFrame(raw),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('rejects an invalid join code in a HOST frame', () {
      final raw = const RelayHostFrame(
        sessionId: 's',
        joinCode: '483729',
        displayName: 'G',
      ).encode().replaceFirst('483729', '083729');
      expect(
        () => decodeRelayFrame(raw),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('rejects an invalid join code in a LOOKUP frame', () {
      final raw = const RelayLookupFrame(
        joinCode: '483729',
      ).encode().replaceFirst('483729', '083729');
      expect(
        () => decodeRelayFrame(raw),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('rejects an empty session id', () {
      final raw = const RelayHostFrame(
        sessionId: 's',
        joinCode: '483729',
        displayName: 'G',
      ).encode().replaceFirst('"sid":"s"', '"sid":""');
      expect(
        () => decodeRelayFrame(raw),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });

    test('rejects oversized frames', () {
      final huge = RelaySendFrame(
        sessionId: 's',
        to: kRelayHostMember,
        payload: 'x' * (kMaxRelayFrameBytes + 1),
      ).encode();
      expect(
        () => decodeRelayFrame(huge),
        throwsA(isA<MultiplayerProtocolException>()),
      );
    });
  });
}
