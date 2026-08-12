import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/tcp_transport.dart';
import 'package:turtle_king/multiplayer/transport.dart';

/// Small real-time settle so loopback socket events are delivered.
Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('TcpTransportServer', () {
    test('host starts and accepts one client', () async {
      final server = await TcpTransportServer.bind(port: 0);
      final accepted = <TransportConnection>[];
      final sub = server.connections.listen(accepted.add);
      final transport = TcpMultiplayerTransport();

      final client = await transport.connect(
        hostAddress: '127.0.0.1',
        sessionId: 's',
        port: server.port,
      );
      await pump();

      expect(server.port, greaterThan(0));
      expect(accepted, hasLength(1));
      expect(client.isOpen, isTrue);

      final received = <String>[];
      accepted.first.incoming.listen(received.add);
      await client.send('ping');
      await pump();
      expect(received, ['ping']);

      await client.close();
      await server.close();
      await sub.cancel();
      await transport.dispose();
    });

    test('multiple clients can connect simultaneously', () async {
      final server = await TcpTransportServer.bind(port: 0);
      final accepted = <TransportConnection>[];
      final sub = server.connections.listen(accepted.add);
      final transport = TcpMultiplayerTransport();

      final clients = [
        for (var i = 0; i < 3; i++)
          await transport.connect(
            hostAddress: '127.0.0.1',
            sessionId: 's',
            port: server.port,
          ),
      ];
      await pump();
      expect(accepted, hasLength(3));
      expect(clients.every((c) => c.isOpen), isTrue);

      // Each connection is independent and receives its own frames.
      final echoes = <int, List<String>>{};
      for (var i = 0; i < accepted.length; i++) {
        echoes[i] = [];
        accepted[i].incoming.listen(echoes[i]!.add);
      }
      for (var i = 0; i < clients.length; i++) {
        await clients[i].send('hello-$i');
      }
      await pump();
      for (var i = 0; i < accepted.length; i++) {
        expect(echoes[i], ['hello-$i']);
      }

      for (final client in clients) {
        await client.close();
      }
      await server.close();
      await sub.cancel();
      await transport.dispose();
    });

    test('clean disconnect delivers done to the server side', () async {
      final server = await TcpTransportServer.bind(port: 0);
      final done = Completer<void>();
      late TransportConnection connection;
      final sub = server.connections.listen((c) {
        connection = c;
        c.incoming.listen((_) {}, onDone: () => done.complete());
      });
      final transport = TcpMultiplayerTransport();
      final client = await transport.connect(
        hostAddress: '127.0.0.1',
        sessionId: 's',
        port: server.port,
      );
      await pump();

      await client.close();
      await done.future.timeout(const Duration(seconds: 2));
      expect(connection.isOpen, isFalse);

      await server.close();
      await sub.cancel();
      await transport.dispose();
    });

    test('disposal closes the server and every accepted socket', () async {
      final server = await TcpTransportServer.bind(port: 0);
      final accepted = <TransportConnection>[];
      final sub = server.connections.listen(accepted.add);
      final transport = TcpMultiplayerTransport();
      final client = await transport.connect(
        hostAddress: '127.0.0.1',
        sessionId: 's',
        port: server.port,
      );
      await pump();
      expect(accepted, hasLength(1));

      await server.close();
      await pump();
      expect(client.isOpen, isFalse);

      await sub.cancel();
      await transport.dispose();
    });

    test('framing splits newline-delimited JSON across writes', () async {
      final server = await TcpTransportServer.bind(port: 0);
      late TransportConnection connection;
      final sub = server.connections.listen((c) => connection = c);
      final socket = await Socket.connect('127.0.0.1', server.port);
      await pump();

      final frames = <String>[];
      connection.incoming.listen(frames.add);

      // Two messages in a single write plus one trailing partial.
      socket.write('{"a":1}\n{"b":2}\n');
      await socket.flush();
      await pump();
      expect(frames, ['{"a":1}', '{"b":2}']);

      await socket.close();
      await server.close();
      await sub.cancel();
    });

    test(
      'a connection refused to a closed port fails with a typed error',
      () async {
        // Bind and close a server to obtain a port nobody is listening on.
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final deadPort = probe.port;
        await probe.close();

        final transport = TcpMultiplayerTransport();
        await expectLater(
          transport.connect(
            hostAddress: '127.0.0.1',
            sessionId: 's',
            port: deadPort,
            connectTimeout: const Duration(seconds: 1),
          ),
          throwsA(isA<SocketException>()),
        );
        await transport.dispose();
      },
    );

    test(
      'an oversized frame ends the connection instead of buffering forever',
      () async {
        final server = await TcpTransportServer.bind(port: 0);
        late TransportConnection connection;
        final sub = server.connections.listen((c) => connection = c);
        final socket = await Socket.connect('127.0.0.1', server.port);
        await pump();

        final completed = Completer<void>();
        connection.incoming.listen((_) {}, onDone: () => completed.complete());

        // One giant line, well over the frame budget, with no newline.
        socket.write('x' * (kMaxFrameBytes + 64 * 1024));
        await socket.flush();
        await completed.future.timeout(const Duration(seconds: 3));

        await socket.close();
        await server.close();
        await sub.cancel();
      },
    );

    test('a malformed client frame does not kill the server', () async {
      final server = await TcpTransportServer.bind(port: 0);
      final accepted = <TransportConnection>[];
      final sub = server.connections.listen(accepted.add);
      final transport = TcpMultiplayerTransport();

      final bad = await Socket.connect('127.0.0.1', server.port);
      final good = await transport.connect(
        hostAddress: '127.0.0.1',
        sessionId: 's',
        port: server.port,
      );
      await pump();
      expect(accepted, hasLength(2));

      final goodFrames = <String>[];
      // Find the good connection and its frames by identity.
      for (final c in accepted) {
        c.incoming.listen(goodFrames.add);
      }
      // Garbage from the raw socket — the server must simply deliver it and
      // stay alive (the session layer decides what garbage means).
      bad.write('this is not json at all\n');
      await bad.flush();
      await good.send('{"fine":true}');
      await pump();

      expect(goodFrames, contains('{"fine":true}'));

      bad.destroy();
      await good.close();
      await server.close();
      await sub.cancel();
      await transport.dispose();
    });
  });

  group('discovery port constants', () {
    test('defaults are stable and non-trivial', () {
      expect(kDefaultGamePort, 41321);
      expect(kDiscoveryPort, 5354);
      expect(kMaxFrameBytes, 256 * 1024);
    });
  });
}
