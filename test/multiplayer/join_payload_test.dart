import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/join_payload.dart';

JoinPayload sample() => const JoinPayload(
  sessionId: 'tk-abc123',
  joinCode: '483729',
  relayUrl: 'wss://relay.example.com/tk',
);

void main() {
  group('join payload encoding', () {
    test('encodes only the session/relay locator fields', () {
      final json = sample().encode();
      final map = jsonDecode(json) as Map<String, dynamic>;
      expect(map.keys.toSet(), {'v', 't', 'sid', 'code', 'relay'});
      expect(map['v'], kJoinPayloadVersion);
      expect(map['t'], kJoinPayloadType);
      expect(map['sid'], 'tk-abc123');
      expect(map['code'], '483729');
      expect(map['relay'], 'wss://relay.example.com/tk');
    });

    test('encoding is deterministic', () {
      expect(sample().encode(), sample().encode());
    });

    test('round-trips through parse', () {
      final parsed = JoinPayload.parse(sample().encode());
      expect(parsed, isNotNull);
      expect(parsed!.sessionId, 'tk-abc123');
      expect(parsed.joinCode, '483729');
      expect(parsed.relayUrl, 'wss://relay.example.com/tk');
    });

    test('the payload never carries private game data or a LAN address', () {
      final json = sample().encode();
      for (final forbidden in [
        'rank',
        'suit',
        'hand',
        'cards',
        'deck',
        'save',
        'GameState',
        'player',
        'history',
        '192.168.',
        'host',
        'port',
      ]) {
        expect(
          json,
          isNot(contains(forbidden)),
          reason: 'QR payload must not contain "$forbidden"',
        );
      }
    });
  });

  group('join payload validation', () {
    JoinPayload? parse(String raw) => JoinPayload.parse(raw);

    test('rejects malformed JSON', () {
      expect(parse('not json'), isNull);
      expect(parse(''), isNull);
      expect(parse('[]'), isNull);
      expect(parse('{}'), isNull);
    });

    test('rejects unknown protocol versions', () {
      final raw = sample().encode().replaceFirst(
        '"v":$kJoinPayloadVersion',
        '"v":99',
      );
      expect(parse(raw), isNull);
    });

    test('rejects the legacy v1 payload that carried a LAN IP', () {
      final legacy =
          '{"v":1,"t":"TKJOIN","sid":"tk-abc123","host":"192.168.1.5",'
          '"port":41321,"code":"483729"}';
      expect(parse(legacy), isNull, reason: 'v1 LAN payloads are rejected');
    });

    test('rejects wrong message types', () {
      final raw = sample().encode().replaceFirst(
        '"t":"$kJoinPayloadType"',
        '"t":"OTHER"',
      );
      expect(parse(raw), isNull);
    });

    test('rejects an empty session id', () {
      final raw = sample().encode().replaceFirst('tk-abc123', '');
      expect(parse(raw), isNull);
    });

    test('rejects an invalid relay endpoint', () {
      for (final bad in [
        '',
        'http://relay.example.com',
        'ftp://relay.example.com',
        '192.168.1.5',
        'wss://',
        'relay.example.com',
        'ws://',
      ]) {
        final raw = sample().encode().replaceFirst(
          'wss://relay.example.com/tk',
          bad,
        );
        expect(parse(raw), isNull, reason: 'relay "$bad" must be rejected');
      }
    });

    test('rejects an invalid join code', () {
      for (final bad in ['48372', '4837290', '083729', 'abcdef', '']) {
        final raw = sample().encode().replaceFirst('483729', bad);
        expect(parse(raw), isNull, reason: 'code "$bad" must be rejected');
      }
    });

    test('rejects payloads with extra unknown fields', () {
      final raw =
          '{"v":2,"t":"TKJOIN","sid":"s","code":"483729",'
          '"relay":"wss://relay.example.com/tk","deck":"secret"}';
      expect(parse(raw), isNotNull, reason: 'extra fields are tolerated');
    });
  });
}
