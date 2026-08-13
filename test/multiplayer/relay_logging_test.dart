import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/relay_protocol.dart';
import 'package:turtle_king/multiplayer/relay_server.dart';

import 'relay_server_test.dart' show RelayTestPeer;

/// Regression suite for the relay's logging contract: the standalone relay
/// emits **routing metadata only**. It must never log game-protocol payloads
/// (which can contain private cards), the join code, or anything that would
/// let a log reader reconstruct game/private state.
void main() {
  group('relay logging privacy', () {
    test(
      'log lines carry routing metadata only — never payloads or codes',
      () async {
        final logs = <String>[];
        final relay = RelayServer(onLog: logs.add);
        final port = await relay.start(port: 0);
        final url = 'ws://127.0.0.1:$port';
        addTearDown(() => relay.stop());

        final h = await RelayTestPeer.connect(url);
        await h.exchange(
          const RelayHostFrame(
            sessionId: 'tk-log',
            joinCode: '483729',
            displayName: 'Game',
          ),
        );
        final c = await RelayTestPeer.connect(url);
        await c.exchange(const RelayJoinFrame(sessionId: 'tk-log'));
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Route a payload that looks like exactly the private data the relay
        // must never log: card identities, hands, deck, save data.
        c.ws.add(
          const RelaySendFrame(
            sessionId: 'tk-log',
            to: kRelayHostMember,
            payload:
                '{"type":"PRIVATE_UPDATE","rank":"A","suit":"hearts",'
                '"hand":["secret-card"],"deck":[],"save":"x",'
                '"GameState":{}}',
          ).encode(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await c.close();
        await h.close();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(logs, isNotEmpty, reason: 'lifecycle events are logged');
        for (final line in logs) {
          // The join code is a locator but must still never be logged.
          expect(line, isNot(contains('483729')), reason: line);
          for (final forbidden in const [
            'PRIVATE_UPDATE',
            'rank',
            'suit',
            'hand',
            'deck',
            'save',
            'GameState',
            'secret-card',
          ]) {
            expect(
              line,
              isNot(contains(forbidden)),
              reason: 'log line leaked game content: $line',
            );
          }
        }

        // The routing-metadata lifecycle events we do expect.
        expect(
          logs.any((l) => l.contains('session tk-log registered')),
          isTrue,
        );
        expect(logs.any((l) => l.contains('member m1 joined tk-log')), isTrue);
        expect(logs.any((l) => l.contains('session tk-log closed')), isTrue);
      },
    );

    test(
      'no logger configured means the relay stays completely silent',
      () async {
        final relay = RelayServer(); // default: onLog == null
        final port = await relay.start(port: 0);
        addTearDown(() => relay.stop());
        final url = 'ws://127.0.0.1:$port';
        final h = await RelayTestPeer.connect(url);
        await h.exchange(
          const RelayHostFrame(
            sessionId: 'tk-silent',
            joinCode: '483729',
            displayName: 'G',
          ),
        );
        final c = await RelayTestPeer.connect(url);
        await c.exchange(const RelayJoinFrame(sessionId: 'tk-silent'));
        await c.close();
        await h.close();
        // No logger attached: nothing is printed or captured anywhere.
      },
    );
  });
}
