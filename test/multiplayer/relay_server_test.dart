import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/relay_protocol.dart';
import 'package:turtle_king/multiplayer/relay_server.dart';

/// A raw WebSocket peer for driving the relay protocol directly (no session
/// layer involved — these tests target the relay itself).
class RelayTestPeer {
  RelayTestPeer(this.ws);

  final WebSocket ws;
  final List<RelayFrame> received = [];
  final List<Completer<RelayFrame>> _pending = [];
  StreamSubscription<dynamic>? _sub;
  bool closed = false;

  static Future<RelayTestPeer> connect(String url) async {
    final peer = RelayTestPeer(await WebSocket.connect(url));
    peer._sub = peer.ws.listen(
      (data) {
        if (data is! String) return;
        final frame = decodeRelayFrame(data);
        if (peer._pending.isNotEmpty) {
          peer._pending.removeAt(0).complete(frame);
        } else {
          peer.received.add(frame);
        }
      },
      onError: (_) => peer.closed = true,
      onDone: () => peer.closed = true,
    );
    return peer;
  }

  /// Sends [frame] and returns the next relay frame from the relay
  /// (strict request/response for handshakes).
  Future<RelayFrame> exchange(
    RelayFrame frame, {
    Duration timeout = const Duration(seconds: 4),
  }) {
    final completer = Completer<RelayFrame>();
    _pending.add(completer);
    ws.add(frame.encode());
    return completer.future.timeout(timeout);
  }

  Future<void> close() async {
    try {
      await ws.close();
    } catch (_) {}
    await _sub?.cancel();
  }
}

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

  group('session registration', () {
    test('a host registers a session and receives REGISTERED', () async {
      final h = await host('tk-reg');
      expect(h.received, isEmpty);
      await h.close();
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
}
