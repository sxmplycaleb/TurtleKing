import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/relay_protocol.dart';
import 'package:turtle_king/multiplayer/relay_server.dart';
import 'package:turtle_king/multiplayer/relay_transport.dart';
import 'package:turtle_king/multiplayer/transport.dart';

import 'helpers.dart';

/// Regression tests for the relay's heartbeat liveness.
///
/// The production defect this guards: through an internet proxy/CDN a
/// WebSocket close frame can be swallowed (or a phone's app can be killed,
/// which never sends one), so the relay cannot rely on close frames to
/// notice a dead host. The relay pings every connection and drops ones that
/// stay silent past the heartbeat timeout — which tears the dead host's
/// session down for everyone.
void main() {
  late RelayServer relay;
  late String url;

  setUp(() async {
    relay = RelayServer(
      // Short, so the tests run fast without depending on the 2s/10s
      // production defaults.
      heartbeatInterval: const Duration(milliseconds: 50),
      heartbeatTimeout: const Duration(milliseconds: 500),
    );
    final port = await relay.start(port: 0);
    url = 'ws://127.0.0.1:$port';
  });

  tearDown(() async {
    await relay.stop();
  });

  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  group('ping/pong protocol', () {
    test('ping and pong are empty liveness signals', () {
      const ping = RelayPingFrame();
      const pong = RelayPongFrame();
      expect(ping.type, 'PING');
      expect(pong.type, 'PONG');
      // No session, member, join code, or game data in either direction.
      expect(ping.body(), isEmpty);
      expect(pong.body(), isEmpty);

      final decodedPing = decodeRelayFrame(const RelayPingFrame().encode());
      expect(decodedPing, isA<RelayPingFrame>());
      final decodedPong = decodeRelayFrame(const RelayPongFrame().encode());
      expect(decodedPong, isA<RelayPongFrame>());
    });
  });

  group('heartbeat liveness', () {
    test(
      'a silent connection is dropped after the heartbeat timeout',
      () async {
        final peer = await RelayTestPeer.connect(url, respondToPings: false);
        // The relay registers the connection asynchronously after the upgrade;
        // wait for it before asserting the drop. The socket close round-trip
        // lands after the relay removes the connection, so wait on `closed`.
        await waitUntil(() => relay.connectionCount == 1);
        await waitUntil(() => peer.closed);
        expect(relay.connectionCount, 0, reason: 'silent connection reaped');
        await peer.close();
      },
    );

    test('a connection that answers pings stays alive indefinitely', () async {
      final peer = await RelayTestPeer.connect(url);
      // Many heartbeat periods, well past the 500ms timeout: the pongs keep
      // the connection alive.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(relay.connectionCount, 1);
      expect(peer.closed, isFalse);
      await peer.close();
    });

    test(
      'an unbound silent connection is dropped without touching sessions',
      () async {
        final h = await RelayTestPeer.connect(url);
        await h.exchange(
          const RelayHostFrame(
            sessionId: 'tk-hb-unbound',
            joinCode: '483729',
            displayName: 'G',
          ),
        );
        final idle = await RelayTestPeer.connect(url, respondToPings: false);
        await waitUntil(() => relay.connectionCount == 1);
        expect(relay.sessionCount, 1, reason: 'session unaffected');
        await h.close();
        await idle.close();
      },
    );
  });

  group('host loss without a close frame', () {
    test('a host that goes silent has its session torn down', () async {
      // The host registers, then stops sending anything and never pongs —
      // exactly what a killed app (or a proxy-swallowed close frame) looks
      // like to the relay. The heartbeat must detect it and close the
      // member's socket.
      final host = await RelayTestPeer.connect(url, respondToPings: false);
      await host.exchange(
        const RelayHostFrame(
          sessionId: 'tk-hb-hostloss',
          joinCode: '483729',
          displayName: 'G',
        ),
      );
      final member = await RelayTestPeer.connect(url);
      await member.exchange(const RelayJoinFrame(sessionId: 'tk-hb-hostloss'));

      // The relay removes the session before the member's close frame lands,
      // so wait on the socket state (the assertion that matters).
      await waitUntil(() => member.closed);
      expect(relay.sessionCount, 0, reason: 'session ends when host dies');
      expect(member.closed, isTrue, reason: 'host loss closes the member');
      await host.close();
      await member.close();
    });

    test('a host that keeps playing is never dropped', () async {
      final host = await RelayTestPeer.connect(url);
      await host.exchange(
        const RelayHostFrame(
          sessionId: 'tk-hb-alive',
          joinCode: '483729',
          displayName: 'G',
        ),
      );
      final member = await RelayTestPeer.connect(url);
      await member.exchange(const RelayJoinFrame(sessionId: 'tk-hb-alive'));
      // Keep traffic flowing on both sides across many heartbeat periods.
      for (var i = 0; i < 8; i++) {
        member.ws.add(
          RelaySendFrame(
            sessionId: 'tk-hb-alive',
            to: kRelayHostMember,
            payload: '{"n":$i}',
          ).encode(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(relay.sessionCount, 1);
      expect(member.closed, isFalse);
      await host.close();
      await member.close();
    });
  });

  group('app transport', () {
    test(
      'RelaySocket auto-pongs so a host and client survive the heartbeat',
      () async {
        final transport = RelayMultiplayerTransport(relayUrl: url);
        final server = await transport.startServer(
          sessionId: 'tk-hb-app',
          joinCode: '483729',
          displayName: 'App Host',
        );
        final hostConnections = <TransportConnection>[];
        server.connections.listen(hostConnections.add);

        final client = await transport.connect(
          hostAddress: url,
          sessionId: 'tk-hb-app',
        );
        await waitUntil(() => hostConnections.isNotEmpty);

        // Many heartbeat periods: without auto-pong the relay would drop both
        // sockets at ~500ms and isOpen would go false.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        expect(client.isOpen, isTrue, reason: 'client survives the heartbeat');
        expect(
          hostConnections.single.isOpen,
          isTrue,
          reason: 'host survives the heartbeat',
        );

        await client.close();
        await server.close();
        await transport.dispose();
      },
    );

    test('routing still works with the heartbeat active', () async {
      final transport = RelayMultiplayerTransport(relayUrl: url);
      final server = await transport.startServer(
        sessionId: 'tk-hb-route',
        joinCode: '483729',
        displayName: 'App Host',
      );
      final received = <String>[];
      final sub = server.connections.listen((connection) {
        connection.incoming.listen(received.add);
      });
      final client = await transport.connect(
        hostAddress: url,
        sessionId: 'tk-hb-route',
      );
      await client.send('{"hello":"from-client"}');
      await waitUntil(() => received.isNotEmpty);
      expect(received.single, '{"hello":"from-client"}');

      await sub.cancel();
      await client.close();
      await server.close();
      await transport.dispose();
    });
  });
}
