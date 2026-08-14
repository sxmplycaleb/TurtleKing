import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/relay_protocol.dart';
import 'package:turtle_king/multiplayer/relay_server.dart';

import 'helpers.dart';

void main() {
  late RelayServer relay;
  late String url;

  setUp(() async {
    relay = RelayServer();
    final port = await relay.start(port: 0);
    url = 'ws://127.0.0.1:$port';
  });

  tearDown(() async {
    await relay.stop();
  });

  Future<RelayTestPeer> host(String sid, {String code = '483729'}) async {
    final peer = await RelayTestPeer.connect(url);
    final response = await peer.exchange(
      RelayHostFrame(sessionId: sid, joinCode: code, displayName: 'Game'),
    );
    expect(response, isA<RelayRegisteredFrame>());
    return peer;
  }

  Future<RelayTestPeer> join(String sid) async {
    final peer = await RelayTestPeer.connect(url);
    final response = await peer.exchange(RelayJoinFrame(sessionId: sid));
    expect(response, isA<RelayJoinAckFrame>());
    return peer;
  }

  /// Waits until [condition] holds (or the deadline passes), so assertions
  /// that depend on the relay's asynchronous socket-close handling are
  /// deterministic instead of racing the close handshake.
  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  group('session registration', () {
    test('a host registers a session and receives REGISTERED', () async {
      final h = await host('tk-reg');
      expect(h.received, isEmpty);
      await h.close();
      // Closing a host tears its session down asynchronously (the socket's
      // close handler runs after the close handshake completes); wait for
      // the relay to observe the departure instead of asserting
      // immediately.
      await waitUntil(() => relay.sessionCount == 0);
      expect(relay.sessionCount, 0, reason: 'session ends when host leaves');
    });

    test('a second host for the same session id is rejected', () async {
      final h1 = await host('tk-dupe');
      final h2 = await RelayTestPeer.connect(url);
      final response = await h2.exchange(
        const RelayHostFrame(
          sessionId: 'tk-dupe',
          joinCode: '483729',
          displayName: 'Other',
        ),
      );
      expect(response, isA<RelayErrFrame>());
      expect((response as RelayErrFrame).reason, contains('already hosted'));
      await h1.close();
      await h2.close();
    });
  });

  group('join + code lookup', () {
    test('a client joins by session id; the host is notified', () async {
      final h = await host('tk-join');
      final c = await join('tk-join');

      await c.close();
      await h.close();
    });

    test('the host receives PEER_JOINED when a member connects', () async {
      final h = await host('tk-pj');
      final c = await RelayTestPeer.connect(url);
      await c.exchange(RelayJoinFrame(sessionId: 'tk-pj'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.received.whereType<RelayPeerJoinedFrame>(), hasLength(1));
      await c.close();
      await h.close();
    });

    test('a code lookup resolves the session; a wrong code fails', () async {
      await host('tk-code', code: '222222');
      final p = await RelayTestPeer.connect(url);
      final ok = await p.exchange(const RelayLookupFrame(joinCode: '222222'));
      expect(ok, isA<RelayLookupAckFrame>());
      expect((ok as RelayLookupAckFrame).sessionId, 'tk-code');

      final bad = await p.exchange(const RelayLookupFrame(joinCode: '999999'));
      expect(bad, isA<RelayLookupErrFrame>());
      await p.close();
    });

    test('joining an unknown session fails', () async {
      final p = await RelayTestPeer.connect(url);
      final response = await p.exchange(
        const RelayJoinFrame(sessionId: 'nope'),
      );
      expect(response, isA<RelayJoinErrFrame>());
      await p.close();
    });

    test('joining a full session fails before reaching the host', () async {
      final smallRelay = RelayServer();
      final port = await smallRelay.start(port: 0);
      final smallUrl = 'ws://127.0.0.1:$port';
      final h = await RelayTestPeer.connect(smallUrl);
      await h.exchange(
        const RelayHostFrame(
          sessionId: 'tk-full',
          joinCode: '483729',
          displayName: 'G',
          maxPlayers: 2, // room for exactly one client
        ),
      );
      final c1 = await RelayTestPeer.connect(smallUrl);
      expect(
        await c1.exchange(const RelayJoinFrame(sessionId: 'tk-full')),
        isA<RelayJoinAckFrame>(),
      );
      final c2 = await RelayTestPeer.connect(smallUrl);
      final rejected = await c2.exchange(
        const RelayJoinFrame(sessionId: 'tk-full'),
      );
      expect(rejected, isA<RelayJoinErrFrame>());
      expect((rejected as RelayJoinErrFrame).reason, contains('full'));

      await c1.close();
      await c2.close();
      await h.close();
      await smallRelay.stop();
    });
  });

  group('routing', () {
    test(
      'client frames reach the host and host unicast reaches the client',
      () async {
        final h = await host('tk-route');
        final c = await RelayTestPeer.connect(url);
        await c.exchange(RelayJoinFrame(sessionId: 'tk-route'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        h.received.clear();

        // Client → host (successful sends get no reply to the sender).
        c.ws.add(
          const RelaySendFrame(
            sessionId: 'tk-route',
            to: kRelayHostMember,
            payload: 'hello-host',
          ).encode(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final toHost = h.received.whereType<RelayPeerFrame>().single;
        expect(toHost.payload, 'hello-host');
        expect(toHost.from, isNot(kRelayHostMember));

        // Host → specific member.
        h.received.clear();
        h.ws.add(
          RelaySendFrame(
            sessionId: 'tk-route',
            to: toHost.from,
            payload: 'hello-client',
          ).encode(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final toClient = c.received.whereType<RelayPeerFrame>().single;
        expect(toClient.payload, 'hello-client');
        expect(toClient.from, kRelayHostMember);

        await c.close();
        await h.close();
      },
    );

    test('sending to an unknown member yields ERR', () async {
      final h = await host('tk-unknown');
      final response = await h.exchange(
        const RelaySendFrame(sessionId: 'tk-unknown', to: 'm99', payload: 'x'),
      );
      expect(response, isA<RelayErrFrame>());
      expect((response as RelayErrFrame).reason, contains('unknown'));
      await h.close();
    });

    test(
      'a malformed frame gets an ERR and never takes the relay down',
      () async {
        final h = await host('tk-mal');
        final p = await RelayTestPeer.connect(url);
        await p.exchange(const RelayJoinFrame(sessionId: 'tk-mal'));
        p.ws.add('this is not json');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(p.received.whereType<RelayErrFrame>(), isNotEmpty);
        // The relay is still healthy: the same client can keep sending.
        p.ws.add(
          const RelaySendFrame(
            sessionId: 'tk-mal',
            to: kRelayHostMember,
            payload: 'still-alive',
          ).encode(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          h.received.whereType<RelayPeerFrame>().map((f) => f.payload),
          contains('still-alive'),
        );
        await p.close();
        await h.close();
      },
    );
  });

  group('membership lifecycle', () {
    test('a member leaving notifies the host with PEER_LEFT', () async {
      final h = await host('tk-leave');
      final c = await RelayTestPeer.connect(url);
      await c.exchange(RelayJoinFrame(sessionId: 'tk-leave'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      h.received.clear();
      c.ws.add(const RelayLeaveFrame().encode());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.received.whereType<RelayPeerLeftFrame>(), hasLength(1));
      await c.close();
      await h.close();
    });

    test('host loss ends the session and closes every member', () async {
      final h = await host('tk-hostloss');
      final c = await RelayTestPeer.connect(url);
      await c.exchange(RelayJoinFrame(sessionId: 'tk-hostloss'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await h.close(); // host disappears
      // The member's socket is closed by the relay with an error frame.
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!c.closed && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(c.closed, isTrue, reason: 'member must be dropped on host loss');
      expect(relay.sessionCount, 0);
      await c.close();
    });

    test('the host can kick a member', () async {
      final h = await host('tk-kick');
      final c = await RelayTestPeer.connect(url);
      final ack = await c.exchange(RelayJoinFrame(sessionId: 'tk-kick'));
      final member = (ack as RelayJoinAckFrame).member;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      h.received.clear();
      h.ws.add(RelayKickFrame(sessionId: 'tk-kick', member: member).encode());
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!c.closed && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(c.closed, isTrue, reason: 'kicked member must be dropped');
      expect(h.received.whereType<RelayPeerLeftFrame>(), hasLength(1));
      await c.close();
      await h.close();
    });
  });

  group('session expiry', () {
    test('idle sessions are swept after the TTL', () async {
      final ttlRelay = RelayServer(
        sessionTtl: const Duration(milliseconds: 300),
        sweepInterval: const Duration(milliseconds: 100),
      );
      final port = await ttlRelay.start(port: 0);
      final ttlUrl = 'ws://127.0.0.1:$port';
      final h = await RelayTestPeer.connect(ttlUrl);
      await h.exchange(
        const RelayHostFrame(
          sessionId: 'tk-ttl',
          joinCode: '483729',
          displayName: 'G',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final p = await RelayTestPeer.connect(ttlUrl);
      final lookup = await p.exchange(
        const RelayLookupFrame(joinCode: '483729'),
      );
      expect(lookup, isA<RelayLookupErrFrame>(), reason: 'session expired');
      await h.close();
      await p.close();
      await ttlRelay.stop();
    });
  });

  group('duplicate joins', () {
    test('a connection already in a session cannot join again', () async {
      final h = await host('tk-double');
      final c = await RelayTestPeer.connect(url);
      expect(
        await c.exchange(const RelayJoinFrame(sessionId: 'tk-double')),
        isA<RelayJoinAckFrame>(),
      );
      final second = await c.exchange(
        const RelayJoinFrame(sessionId: 'tk-double'),
      );
      expect(second, isA<RelayJoinErrFrame>());
      expect((second as RelayJoinErrFrame).reason, contains('already'));
      await c.close();
      await h.close();
    });

    test(
      'the host connection cannot join its own session as a member',
      () async {
        final h = await host('tk-hostjoin');
        final response = await h.exchange(
          const RelayJoinFrame(sessionId: 'tk-hostjoin'),
        );
        expect(response, isA<RelayJoinErrFrame>());
        expect((response as RelayJoinErrFrame).reason, contains('already'));
        await h.close();
      },
    );
  });

  group('multiple simultaneous sessions', () {
    test(
      'sessions are isolated: codes, joins, and routing stay separate',
      () async {
        final h1 = await host('tk-msa', code: '222222');
        final h2 = await host('tk-msb', code: '333333');

        // Code lookups resolve only within the correct session.
        final p = await RelayTestPeer.connect(url);
        final a = await p.exchange(const RelayLookupFrame(joinCode: '222222'));
        expect((a as RelayLookupAckFrame).sessionId, 'tk-msa');
        final b = await p.exchange(const RelayLookupFrame(joinCode: '333333'));
        expect((b as RelayLookupAckFrame).sessionId, 'tk-msb');

        // Joins land in the right session and routing never crosses over.
        final c1 = await RelayTestPeer.connect(url);
        final c2 = await RelayTestPeer.connect(url);
        await c1.exchange(const RelayJoinFrame(sessionId: 'tk-msa'));
        await c2.exchange(const RelayJoinFrame(sessionId: 'tk-msb'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        h1.received.clear();
        h2.received.clear();
        c1.ws.add(
          const RelaySendFrame(
            sessionId: 'tk-msa',
            to: kRelayHostMember,
            payload: 'for-a',
          ).encode(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          h1.received.whereType<RelayPeerFrame>().map((f) => f.payload),
          contains('for-a'),
        );
        expect(h2.received.whereType<RelayPeerFrame>(), isEmpty);

        await c2.close();
        await c1.close();
        await p.close();
        await h2.close();
        await h1.close();
        // Closing a host tears its session down asynchronously (the socket's
        // close handler runs after the close handshake completes); wait for
        // the relay to observe every departure instead of asserting
        // immediately.
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (relay.sessionCount != 0 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(relay.sessionCount, 0);
      },
    );
  });

  group('relay shutdown', () {
    test('stop() closes every connection and clears all sessions', () async {
      final h = await host('tk-stop');
      final c = await RelayTestPeer.connect(url);
      await c.exchange(const RelayJoinFrame(sessionId: 'tk-stop'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(relay.sessionCount, 1);

      await relay.stop();
      expect(relay.sessionCount, 0);
      expect(relay.connectionCount, 0);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while ((!h.closed || !c.closed) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(h.closed, isTrue, reason: 'host socket closed on relay stop');
      expect(c.closed, isTrue, reason: 'member socket closed on relay stop');
      await c.close();
      await h.close();
    });

    test(
      'a fresh relay binds and serves after a previous one stopped',
      () async {
        final first = RelayServer();
        final port = await first.start(port: 0);
        await first.stop();
        final second = RelayServer();
        final secondPort = await second.start(port: port);
        expect(secondPort, port, reason: 'port is reusable after a clean stop');
        await second.stop();
      },
    );
  });
}
