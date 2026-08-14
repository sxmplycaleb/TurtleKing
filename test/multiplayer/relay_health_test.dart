import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/relay_protocol.dart';
import 'package:turtle_king/multiplayer/relay_server.dart';

import 'helpers.dart' show RelayTestPeer;

Future<String> _getHealth(int port) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/health'),
    );
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

void main() {
  group('RelayServer /health endpoint', () {
    late RelayServer relay;
    late int port;

    setUp(() async {
      relay = RelayServer();
      port = await relay.start(port: 0);
    });

    tearDown(() async {
      await relay.stop();
    });

    test('GET /health returns 200 with {"status":"ok"}', () async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/health'),
        );
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers.contentType?.mimeType, 'application/json');
        final body = await response.transform(utf8.decoder).join();
        expect(body, '{"status":"ok"}');
      } finally {
        client.close();
      }
    });

    test('health stays static with an active session — no codes or session '
        'ids leak', () async {
      final peer = await RelayTestPeer.connect('ws://127.0.0.1:$port');
      final registered = await peer.exchange(
        const RelayHostFrame(
          sessionId: 'health-session',
          joinCode: '483729',
          displayName: 'Game',
        ),
      );
      expect(registered, isA<RelayRegisteredFrame>());
      expect(relay.sessionCount, 1);

      final body = await _getHealth(port);
      expect(body, '{"status":"ok"}');
      expect(
        body.contains('483729'),
        isFalse,
        reason: 'join code must never appear in health output',
      );
      expect(
        body.contains('health-session'),
        isFalse,
        reason: 'session ids must never appear in health output',
      );
      expect(
        body.contains('Game'),
        isFalse,
        reason: 'display names must never appear in health output',
      );

      await peer.close();
    });

    test('non-WebSocket requests to other paths stay rejected', () async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/other'),
        );
        final response = await request.close();
        expect(response.statusCode, HttpStatus.upgradeRequired);
        await response.drain<void>();
      } finally {
        client.close();
      }
    });
  });
}
