import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/protocol.dart';
import 'package:turtle_king/multiplayer/protocol_codec.dart';
import 'package:turtle_king/multiplayer/session.dart';

/// Small real-time settle for loopback socket delivery.
Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 60));

/// Generous budget for multi-round-trip loopback flows on I/O-locked CI
/// machines (OneDrive sync can stall socket delivery well past a 3s budget).
const Duration kSlowLoopback = Duration(seconds: 12);

Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A raw protocol-speaking TCP client used to exercise the host from the
/// wire (garbage, wrong versions, wrong session ids, silent connections).
class RawClient {
  RawClient(this.sessionId, this.playerName);

  final String sessionId;
  final String playerName;
  final MessageCodec codec = const MessageCodec();
  final List<String> received = <String>[];
  final Completer<void> closed = Completer<void>();
  Socket? socket;

  Future<void> connect(int port) async {
    socket = await Socket.connect('127.0.0.1', port);
    socket!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          received.add,
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
        );
    await send(
      JoinRequestMessage(seq: 1, sessionId: sessionId, playerName: playerName),
    );
  }

  Future<void> send(MultiplayerMessage message) async {
    socket!.write('${codec.encode(message)}\n');
    await socket!.flush();
  }

  Future<void> sendRaw(String raw) async {
    socket!.write('$raw\n');
    await socket!.flush();
  }

  /// Returns the first decoded message of [type] seen, or fails after the
  /// timeout.
  Future<T> awaitMessage<T extends MultiplayerMessage>({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      for (final raw in List.of(received)) {
        try {
          final message = codec.decode(raw);
          if (message is T) return message;
        } on Object {
          // Ignore unparseable frames while waiting.
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('no ${T.toString()} received within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> close() async {
    await socket?.close();
    socket = null;
  }
}

/// A raw server that speaks (or fails to speak) the protocol, used to
/// exercise the client's failure paths.
class RawServer {
  final MessageCodec codec = const MessageCodec();
  final List<String> received = <String>[];
  ServerSocket? server;
  Socket? socket;

  Future<int> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((client) {
      socket = client;
      client
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(received.add);
    });
    return server!.port;
  }

  Future<void> send(MultiplayerMessage message) async {
    socket!.write('${codec.encode(message)}\n');
    await socket!.flush();
  }

  Future<void> sendRaw(String raw) async {
    socket!.write('$raw\n');
    await socket!.flush();
  }

  Future<void> close() async {
    await server?.close();
    await socket?.close();
  }
}

void main() {
  const codec = MessageCodec();

  group('HostSession + ClientSession over loopback', () {
    test('full join flow: accept, roster sync, disconnect', () async {
      final host = HostSession(sessionId: 's-1');
      final server = await host.start(
        displayName: 'Game',
        hostName: 'Caleb',
        port: 0,
      );
      expect(host.roster.single.name, 'Caleb');
      expect(host.port, server.port);
      final hostEvents = <HostSessionEvent>[];
      final hostSub = host.events.listen(hostEvents.add);

      final client = ClientSession(sessionId: 's-1', playerName: 'Mia');
      final result = await client.join(
        hostAddress: '127.0.0.1',
        port: server.port,
      );
      expect(result.isAccepted, isTrue);
      expect(result.self!.name, 'Mia');
      expect(result.roster!.map((p) => p.name), ['Caleb', 'Mia']);

      await pumpUntil(() => host.roster.length == 2);
      expect(host.roster.map((p) => p.name), ['Caleb', 'Mia']);
      expect(
        hostEvents.any((e) => e.type == HostSessionEventType.clientJoined),
        isTrue,
      );
      expect(client.roster.map((p) => p.name), ['Caleb', 'Mia']);

      await client.disconnect();
      await pumpUntil(() => host.roster.length == 1);
      expect(host.roster.map((p) => p.name), ['Caleb']);
      expect(
        hostEvents.any((e) => e.type == HostSessionEventType.clientLeft),
        isTrue,
      );

      await client.dispose();
      await host.stop();
      await hostSub.cancel();
    });

    test(
      'a second client joins and everyone sees the updated roster',
      () async {
        final host = HostSession(sessionId: 's-2');
        final server = await host.start(
          displayName: 'G',
          hostName: 'H',
          port: 0,
        );
        final clientA = ClientSession(sessionId: 's-2', playerName: 'A');
        final clientB = ClientSession(sessionId: 's-2', playerName: 'B');

        final aRes = await clientA.join(
          hostAddress: '127.0.0.1',
          port: server.port,
        );
        expect(aRes.isAccepted, isTrue);
        final bEvents = <ClientSessionEvent>[];
        final bSub = clientB.events.listen(bEvents.add);
        final bRes = await clientB.join(
          hostAddress: '127.0.0.1',
          port: server.port,
        );
        expect(bRes.isAccepted, isTrue);

        await pumpUntil(() => host.roster.length == 3, timeout: kSlowLoopback);
        expect(host.roster.map((p) => p.name), ['H', 'A', 'B']);
        await pumpUntil(
          () => bEvents.any(
            (e) => e.type == ClientSessionEventType.rosterUpdated,
          ),
          timeout: kSlowLoopback,
        );
        expect(clientA.roster.map((p) => p.name), ['H', 'A', 'B']);
        expect(clientB.roster.map((p) => p.name), ['H', 'A', 'B']);

        await clientA.disconnect();
        await clientB.disconnect();
        await host.stop();
        await bSub.cancel();
      },
    );

    test('host stop sends SESSION_END to clients', () async {
      final host = HostSession(sessionId: 's-3');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final client = ClientSession(sessionId: 's-3', playerName: 'A');
      final jr = await client.join(hostAddress: '127.0.0.1', port: server.port);
      expect(jr.isAccepted, isTrue);

      final events = <ClientSessionEvent>[];
      final sub = client.events.listen(events.add);
      await host.stop(reason: 'host-left');

      await pumpUntil(
        () => events.any((e) => e.type == ClientSessionEventType.sessionEnded),
        timeout: kSlowLoopback,
      );
      expect(client.isConnected, isFalse);
      await sub.cancel();
    });

    test('a duplicate name is rejected', () async {
      final host = HostSession(sessionId: 's-4');
      final server = await host.start(
        displayName: 'G',
        hostName: 'Caleb',
        port: 0,
      );
      final a = ClientSession(sessionId: 's-4', playerName: 'Mia');
      final b = ClientSession(sessionId: 's-4', playerName: 'mia');

      expect(
        (await a.join(hostAddress: '127.0.0.1', port: server.port)).isAccepted,
        isTrue,
      );
      final result = await b.join(hostAddress: '127.0.0.1', port: server.port);
      expect(result.outcome, JoinOutcome.rejected);
      expect(result.reason, contains('already taken'));

      await a.disconnect();
      await host.stop();
    });

    test('the player limit is enforced', () async {
      final host = HostSession(sessionId: 's-5', playerLimit: 2);
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final a = ClientSession(sessionId: 's-5', playerName: 'A');
      final b = ClientSession(sessionId: 's-5', playerName: 'B');

      expect(
        (await a.join(hostAddress: '127.0.0.1', port: server.port)).isAccepted,
        isTrue,
      );
      final result = await b.join(hostAddress: '127.0.0.1', port: server.port);
      expect(result.outcome, JoinOutcome.rejected);
      expect(result.reason, contains('full'));

      await a.disconnect();
      await host.stop();
    });
  });

  group('HostSession robustness (raw clients)', () {
    test('a malformed client message cannot crash the server', () async {
      final host = HostSession(sessionId: 's-6');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);

      final bad = RawClient('s-6', 'Bad');
      await bad.connect(server.port);
      await bad.sendRaw('{{{not json');
      await bad.sendRaw(
        '{"v":1,"type":"NOPE","seq":1,"sessionId":"s-6","body":{}}',
      );
      await pump();

      // The server is still accepting: a valid client can still join.
      final good = ClientSession(sessionId: 's-6', playerName: 'Good');
      final result = await good.join(
        hostAddress: '127.0.0.1',
        port: server.port,
      );
      expect(result.isAccepted, isTrue);

      await good.disconnect();
      await bad.close();
      await host.stop();
    });

    test('an unsupported protocol version closes the connection', () async {
      final host = HostSession(sessionId: 's-7');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);

      final raw = RawClient('s-7', 'Old');
      // Bypass the codec: send v=99 directly.
      raw.socket = await Socket.connect('127.0.0.1', server.port);
      final sub = raw.socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            raw.received.add,
            onDone: () {
              if (!raw.closed.isCompleted) raw.closed.complete();
            },
          );
      await raw.sendRaw(
        jsonEncode({
          'v': 99,
          'type': 'JOIN_REQUEST',
          'seq': 1,
          'sessionId': 's-7',
          'body': {'playerName': 'Old'},
        }),
      );
      await raw.closed.future.timeout(const Duration(seconds: 3));
      await sub.cancel();
      await host.stop();
    });

    test('a wrong session id on an established connection closes it', () async {
      final host = HostSession(sessionId: 's-8');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);

      final raw = RawClient('s-8', 'A');
      await raw.connect(server.port);
      await raw.awaitMessage<JoinAcceptMessage>();

      // Post-join messages must carry the host session id.
      await raw.send(HeartbeatMessage(seq: 9, sessionId: 'some-other-session'));
      await raw.closed.future.timeout(const Duration(seconds: 3));

      expect(host.roster.map((p) => p.name), ['H']);
      await host.stop();
    });

    test(
      'a silent connected client is detected as dead by heartbeats',
      () async {
        final host = HostSession(
          sessionId: 's-9',
          heartbeatInterval: const Duration(milliseconds: 30),
          heartbeatTimeout: const Duration(milliseconds: 120),
        );
        final server = await host.start(
          displayName: 'G',
          hostName: 'H',
          port: 0,
        );

        final raw = RawClient('s-9', 'Ghost');
        await raw.connect(server.port);
        await raw.awaitMessage<JoinAcceptMessage>();
        // The raw client sends nothing further — the host must notice.

        final hostEvents = <HostSessionEvent>[];
        final sub = host.events.listen(hostEvents.add);
        await pumpUntil(
          () =>
              hostEvents.any((e) => e.type == HostSessionEventType.clientLeft),
          timeout: const Duration(seconds: 3),
        );
        expect(host.roster.map((p) => p.name), ['H']);
        await sub.cancel();
        await raw.close();
        await host.stop();
      },
    );

    test(
      'healthy clients are retained across many heartbeat intervals',
      () async {
        final host = HostSession(
          sessionId: 's-10',
          heartbeatInterval: const Duration(milliseconds: 20),
          heartbeatTimeout: const Duration(milliseconds: 500),
        );
        final server = await host.start(
          displayName: 'G',
          hostName: 'H',
          port: 0,
        );
        final client = ClientSession(
          sessionId: 's-10',
          playerName: 'A',
          heartbeatInterval: const Duration(milliseconds: 20),
          heartbeatTimeout: const Duration(milliseconds: 500),
        );
        final clientEvents = <ClientSessionEvent>[];
        final sub = client.events.listen(clientEvents.add);

        expect(
          (await client.join(
            hostAddress: '127.0.0.1',
            port: server.port,
          )).isAccepted,
          isTrue,
        );
        // Let many intervals pass — nothing may be dropped.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(client.isConnected, isTrue);
        expect(host.roster.length, 2);
        expect(
          clientEvents.where(
            (e) => e.type == ClientSessionEventType.connectionLost,
          ),
          isEmpty,
        );

        await client.disconnect();
        await sub.cancel();
        await host.stop();
      },
    );

    test('heartbeat frames are emitted on the wire', () async {
      final host = HostSession(
        sessionId: 's-11',
        heartbeatInterval: const Duration(milliseconds: 30),
        heartbeatTimeout: const Duration(seconds: 2),
      );
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final raw = RawClient('s-11', 'A');
      await raw.connect(server.port);
      await raw.awaitMessage<JoinAcceptMessage>();

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      var sawHeartbeat = false;
      while (DateTime.now().isBefore(deadline)) {
        for (final line in List.of(raw.received)) {
          try {
            if (codec.decode(line) is HeartbeatMessage) {
              sawHeartbeat = true;
            }
          } on Object {
            // Not every frame is a heartbeat.
          }
        }
        if (sawHeartbeat) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(sawHeartbeat, isTrue, reason: 'host should send heartbeats');

      await raw.close();
      await host.stop();
    });

    test('heartbeats stop after the host session is disposed', () async {
      final host = HostSession(
        sessionId: 's-12',
        heartbeatInterval: const Duration(milliseconds: 30),
        heartbeatTimeout: const Duration(seconds: 2),
      );
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final raw = RawClient('s-12', 'A');
      await raw.connect(server.port);
      await raw.awaitMessage<JoinAcceptMessage>();
      await pump();

      await host.stop();
      // A clean stop sends SESSION_END; wait until it has actually been
      // delivered before asserting nothing further arrives (avoids a race
      // where delivery lags stop() under parallel test load).
      await raw.awaitMessage<SessionEndMessage>();
      final countBefore = raw.received.length;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        raw.received.length,
        countBefore,
        reason: 'no frames may arrive after the host stops',
      );

      await raw.close();
    });
  });

  group('ClientSession failure paths (raw server)', () {
    test('connection refused surfaces a friendly failure', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();

      final client = ClientSession(sessionId: 's', playerName: 'A');
      final result = await client.join(
        hostAddress: '127.0.0.1',
        port: deadPort,
        connectTimeout: const Duration(seconds: 1),
      );
      expect(result.outcome, JoinOutcome.connectionFailed);
      expect(result.reason, contains('Could not reach the host'));
    });

    test('a host that never responds times out', () async {
      final server = RawServer();
      final port = await server.start();

      final client = ClientSession(sessionId: 's', playerName: 'A');
      final result = await client.join(
        hostAddress: '127.0.0.1',
        port: port,
        connectTimeout: const Duration(milliseconds: 300),
      );
      expect(result.outcome, JoinOutcome.timedOut);
      await server.close();
    });

    test('a malformed response is a protocol error', () async {
      final server = RawServer();
      final port = await server.start();
      final client = ClientSession(sessionId: 's', playerName: 'A');
      final joinFuture = client.join(hostAddress: '127.0.0.1', port: port);
      await pumpUntil(() => server.received.isNotEmpty);
      await server.sendRaw('definitely not json');
      final result = await joinFuture;
      expect(result.outcome, JoinOutcome.protocolError);
      await server.close();
    });

    test('an incompatible protocol version is a protocol error', () async {
      final server = RawServer();
      final port = await server.start();
      final client = ClientSession(sessionId: 's', playerName: 'A');
      final joinFuture = client.join(hostAddress: '127.0.0.1', port: port);
      await pumpUntil(() => server.received.isNotEmpty);
      await server.sendRaw(
        jsonEncode({
          'v': 99,
          'type': 'JOIN_ACCEPT',
          'seq': 1,
          'sessionId': 's',
          'body': {'playerId': 'x', 'color': 1, 'roster': []},
        }),
      );
      final result = await joinFuture;
      expect(result.outcome, JoinOutcome.protocolError);
      await server.close();
    });

    test('a host that ends the session during join reports it', () async {
      final server = RawServer();
      final port = await server.start();
      final client = ClientSession(sessionId: 's', playerName: 'A');
      final joinFuture = client.join(hostAddress: '127.0.0.1', port: port);
      await pumpUntil(() => server.received.isNotEmpty);
      await server.send(
        SessionEndMessage(seq: 1, sessionId: 's', reason: 'host-left'),
      );
      final result = await joinFuture;
      expect(result.outcome, JoinOutcome.sessionEnded);
      await server.close();
    });

    test('a dropped connection mid-lobby emits connectionLost', () async {
      final server = RawServer();
      final port = await server.start();
      final client = ClientSession(sessionId: 's-13', playerName: 'A');
      final joinFuture = client.join(hostAddress: '127.0.0.1', port: port);
      await pumpUntil(() => server.received.isNotEmpty);
      await server.send(
        JoinAcceptMessage(
          seq: 1,
          sessionId: 's-13',
          playerId: 'mp-1',
          color: 1,
          roster: const [],
        ),
      );
      final result = await joinFuture;
      expect(result.isAccepted, isTrue);

      final events = <ClientSessionEvent>[];
      final sub = client.events.listen(events.add);
      // Kill the connection without any DISCONNECT or SESSION_END: the
      // client must notice the lost connection on its own.
      server.socket!.destroy();
      await pumpUntil(
        () =>
            events.any((e) => e.type == ClientSessionEventType.connectionLost),
      );
      await sub.cancel();
      await server.close();
    });
  });

  group('privacy on the wire', () {
    test(
      'no frame crossing the wire contains card, deck, or save data',
      () async {
        final host = HostSession(sessionId: 'priv-1');
        final server = await host.start(
          displayName: 'G',
          hostName: 'H',
          port: 0,
        );

        // A raw client joins and records every single frame it receives
        // (join accept, roster updates, heartbeats, session end).
        final raw = RawClient('priv-1', 'A');
        await raw.connect(server.port);
        await raw.awaitMessage<JoinAcceptMessage>();

        // Second player joins to trigger a roster broadcast; first leaves.
        final second = ClientSession(sessionId: 'priv-1', playerName: 'B');
        await second.join(hostAddress: '127.0.0.1', port: server.port);
        await pumpUntil(() => host.roster.length == 3);
        await second.disconnect();
        await pumpUntil(() => host.roster.length == 2);

        await host.stop();
        await raw.closed.future.timeout(const Duration(seconds: 3));

        expect(
          raw.received,
          isNotEmpty,
          reason: 'the wire test must see frames',
        );
        const forbidden = [
          'rank',
          'suit',
          'hand',
          'hands',
          'deck',
          'remainingDeck',
          'cards',
          '_hands',
          '_deck',
        ];
        for (final line in raw.received) {
          expect(line, isNot(contains('"rank"')));
          expect(line, isNot(contains('"suit"')));
          expect(line, isNot(contains('"hand"')));
          expect(line, isNot(contains('"deck"')));
          expect(line, isNot(contains('"cards"')));
          // Roster entries carry only the approved identity fields.
          if (line.contains('"roster"')) {
            final decoded = jsonDecode(line) as Map<String, dynamic>;
            final body = decoded['body'] as Map<String, dynamic>;
            final roster = body['roster'] as List<dynamic>;
            for (final entry in roster) {
              final keys = (entry as Map<String, dynamic>).keys.toSet();
              expect(
                keys.difference({'id', 'name', 'color'}),
                isEmpty,
                reason: 'roster entry leaked fields: $keys',
              );
            }
          }
          // No field may appear anywhere (deep scan).
          void scan(Object? node) {
            if (node is Map) {
              for (final key in node.keys) {
                expect(forbidden, isNot(contains(key)));
                scan(node[key]);
              }
            } else if (node is List) {
              node.forEach(scan);
            }
          }

          scan(jsonDecode(line));
        }
        await raw.close();
        await host.dispose();
      },
    );

    test(
      'wire layers never reference GameState; the host routes through it',
      () {
        // Structural guard: the transport/protocol/codec layers deal in public
        // data only and must never import or name GameState. The host session
        // is the single legitimate exception (M18.4): it routes client actions
        // into the authoritative rules engine — but it must never touch the
        // engine's private internals (hands, deck) or serialize it.
        final sessionSource = File(
          'lib/multiplayer/session.dart',
        ).readAsStringSync();
        final protocolSource = File(
          'lib/multiplayer/protocol.dart',
        ).readAsStringSync();
        final codecSource = File(
          'lib/multiplayer/protocol_codec.dart',
        ).readAsStringSync();
        final tcpSource = File(
          'lib/multiplayer/tcp_transport.dart',
        ).readAsStringSync();
        for (final source in [protocolSource, codecSource, tcpSource]) {
          expect(source, isNot(contains('game_state.dart')));
          expect(source, isNot(contains('GameState')));
          expect(source, isNot(contains('handOf')));
          expect(source, isNot(contains('remainingDeck')));
        }
        // The host session may reference the authoritative engine, but never
        // its private internals, and never a save document type.
        expect(sessionSource, contains('game_state.dart'));
        expect(sessionSource, isNot(contains('handOf')));
        expect(sessionSource, isNot(contains('remainingDeck')));
        expect(sessionSource, isNot(contains('game_save.dart')));
        expect(sessionSource, isNot(contains('GameSaveStore')));
        expect(sessionSource, isNot(contains('SaveData')));
      },
    );
  });
}
