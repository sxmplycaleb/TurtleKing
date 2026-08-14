import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/relay_server.dart';
import 'package:turtle_king/multiplayer/relay_transport.dart';
import 'package:turtle_king/multiplayer/session.dart';
import 'package:turtle_king/multiplayer/transport.dart';

/// How a flaky first attempt fails.
enum _FailWith { timeout, socket, connectionLost, rejected }

/// A [RelayMultiplayerTransport] that can fail its first [failuresBeforeSuccess]
/// connect calls (simulating a cold-starting public relay) and optionally
/// hold a connect on a [gate] so tests can observe an in-flight join/retry.
class _FlakyRelayTransport extends RelayMultiplayerTransport {
  _FlakyRelayTransport({
    required super.relayUrl,
    this.failuresBeforeSuccess = 0,
    this.failure,
    this.gate,
  });

  /// Connect calls that throw [failure] before a real connect is attempted.
  int failuresBeforeSuccess;

  _FailWith? failure;

  /// When set, every surviving connect awaits this before proceeding (lets
  /// tests hold a join in flight mid-retry).
  Completer<void>? gate;

  int connectCalls = 0;

  @override
  Future<TransportConnection> connect({
    required String hostAddress,
    required String sessionId,
    int port = kDefaultGamePort,
    Duration connectTimeout = const Duration(seconds: 5),
  }) async {
    connectCalls++;
    if (connectCalls <= failuresBeforeSuccess) {
      switch (failure) {
        case _FailWith.timeout:
          throw TimeoutException('relay waking');
        case _FailWith.socket:
          throw const SocketException('connection refused');
        case _FailWith.connectionLost:
          throw const RelayJoinException('relay connection lost');
        case _FailWith.rejected:
          throw const RelayJoinException('no such session');
        case null:
          break;
      }
    }
    if (gate != null) await gate!.future;
    return super.connect(
      hostAddress: hostAddress,
      sessionId: sessionId,
      port: port,
      connectTimeout: connectTimeout,
    );
  }
}

void main() {
  late RelayServer relay;
  late HostSession host;
  late String relayUrl;

  Future<void> startHost(String sessionId, [String code = '483729']) async {
    relay = RelayServer();
    await relay.start(port: 0);
    relayUrl = 'ws://127.0.0.1:${relay.port}';
    host = HostSession(
      sessionId: sessionId,
      joinCode: code,
      transport: RelayMultiplayerTransport(relayUrl: relayUrl),
    );
    await host.start(displayName: 'G', hostName: 'H', port: 0);
  }

  tearDown(() async {
    await host.stop();
    await relay.stop();
  });

  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not met within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  group('relay join retry (cold-start resilience)', () {
    test('a warm relay join succeeds in one attempt', () async {
      await startHost('warm');
      final transport = _FlakyRelayTransport(relayUrl: relayUrl);
      final client = ClientSession(
        sessionId: 'warm',
        playerName: 'Mia',
        transport: transport,
      );
      final result = await client.joinRelay(
        relayUrl: relayUrl,
        connectTimeout: const Duration(seconds: 5),
      );
      expect(result.isAccepted, isTrue);
      expect(transport.connectCalls, 1, reason: 'warm join needs no retry');
      await client.disconnect();
    });

    test(
      'a relay that wakes within the timeout succeeds on the retry',
      () async {
        await startHost('slow');
        final transport = _FlakyRelayTransport(
          relayUrl: relayUrl,
          failuresBeforeSuccess: 1,
          failure: _FailWith.timeout,
        );
        final client = ClientSession(
          sessionId: 'slow',
          playerName: 'Mia',
          transport: transport,
        );
        final result = await client.joinRelay(
          relayUrl: relayUrl,
          connectTimeout: const Duration(seconds: 5),
        );
        expect(result.isAccepted, isTrue);
        expect(
          transport.connectCalls,
          2,
          reason: 'exactly one retry after the transient timeout',
        );
        await client.disconnect();
      },
    );

    test('a socket failure followed by success also retries once', () async {
      await startHost('socket');
      final transport = _FlakyRelayTransport(
        relayUrl: relayUrl,
        failuresBeforeSuccess: 1,
        failure: _FailWith.socket,
      );
      final client = ClientSession(
        sessionId: 'socket',
        playerName: 'Mia',
        transport: transport,
      );
      final result = await client.joinRelay(
        relayUrl: relayUrl,
        connectTimeout: const Duration(seconds: 5),
      );
      expect(result.isAccepted, isTrue);
      expect(transport.connectCalls, 2);
      await client.disconnect();
    });

    test('a connection lost mid-handshake is treated as transient', () async {
      await startHost('lost');
      final transport = _FlakyRelayTransport(
        relayUrl: relayUrl,
        failuresBeforeSuccess: 1,
        failure: _FailWith.connectionLost,
      );
      final client = ClientSession(
        sessionId: 'lost',
        playerName: 'Mia',
        transport: transport,
      );
      final result = await client.joinRelay(
        relayUrl: relayUrl,
        connectTimeout: const Duration(seconds: 5),
      );
      expect(result.isAccepted, isTrue);
      expect(transport.connectCalls, 2);
      await client.disconnect();
    });

    test(
      'both attempts failing yields the friendly error with one retry',
      () async {
        await startHost('bothfail');
        final transport = _FlakyRelayTransport(
          relayUrl: relayUrl,
          failuresBeforeSuccess: 2,
          failure: _FailWith.timeout,
        );
        final client = ClientSession(
          sessionId: 'bothfail',
          playerName: 'Mia',
          transport: transport,
        );
        final result = await client.joinRelay(
          relayUrl: relayUrl,
          connectTimeout: const Duration(seconds: 5),
        );
        expect(result.isAccepted, isFalse);
        expect(result.outcome, JoinOutcome.connectionFailed);
        expect(
          transport.connectCalls,
          2,
          reason: 'at most one retry regardless of outcome',
        );
        expect(result.reason, isNotNull);
        await client.disconnect();
      },
    );

    test('an expired/unavailable session is never retried', () async {
      await startHost('gone');
      final transport = _FlakyRelayTransport(
        relayUrl: relayUrl,
        failuresBeforeSuccess: 99,
        failure: _FailWith.rejected,
      );
      final client = ClientSession(
        sessionId: 'gone',
        playerName: 'Mia',
        transport: transport,
      );
      final result = await client.joinRelay(relayUrl: relayUrl);
      expect(result.isAccepted, isFalse);
      expect(
        result.outcome,
        JoinOutcome.sessionEnded,
        reason: 'no such session maps to the friendly session-ended outcome',
      );
      expect(
        transport.connectCalls,
        1,
        reason: 'permanent rejection is not retried',
      );
      await client.disconnect();
    });

    test('a host rejection (name taken) is not retried', () async {
      await startHost('nametaken');
      final first = ClientSession(
        sessionId: 'nametaken',
        playerName: 'Mia',
        transport: RelayMultiplayerTransport(relayUrl: relayUrl),
      );
      expect((await first.joinRelay(relayUrl: relayUrl)).isAccepted, isTrue);

      final transport = _FlakyRelayTransport(relayUrl: relayUrl);
      final second = ClientSession(
        sessionId: 'nametaken',
        playerName: 'Mia', // duplicate name: the host rejects the join
        transport: transport,
      );
      final result = await second.joinRelay(relayUrl: relayUrl);
      expect(result.isAccepted, isFalse);
      expect(result.outcome, JoinOutcome.rejected);
      expect(result.reason, contains('taken'));
      expect(
        transport.connectCalls,
        1,
        reason: 'a host rejection is not retried',
      );
      await first.disconnect();
      await second.disconnect();
    });

    test(
      'duplicate join attempts are blocked while one is in flight',
      () async {
        await startHost('dup');
        final gate = Completer<void>();
        final transport = _FlakyRelayTransport(relayUrl: relayUrl, gate: gate);
        final client = ClientSession(
          sessionId: 'dup',
          playerName: 'Mia',
          transport: transport,
        );
        final future = client.joinRelay(
          relayUrl: relayUrl,
          connectTimeout: const Duration(seconds: 5),
        );
        expect(
          () => client.joinRelay(relayUrl: relayUrl),
          throwsStateError,
          reason: 'a second join while one is in flight must be rejected',
        );
        gate.complete();
        final result = await future;
        expect(result.isAccepted, isTrue);
        await client.disconnect();
      },
    );

    test(
      'the join stays in flight during the retry and blocks duplicates',
      () async {
        await startHost('retryhold');
        final gate = Completer<void>();
        final transport = _FlakyRelayTransport(
          relayUrl: relayUrl,
          failuresBeforeSuccess: 1,
          failure: _FailWith.timeout,
          gate: gate,
        );
        final client = ClientSession(
          sessionId: 'retryhold',
          playerName: 'Mia',
          transport: transport,
        );
        final future = client.joinRelay(
          relayUrl: relayUrl,
          connectTimeout: const Duration(seconds: 5),
        );
        // Attempt 1 fails fast (timeout); the retry is now held on the gate —
        // the join is still in flight, so a duplicate attempt stays blocked.
        await pumpUntil(() => transport.connectCalls == 2);
        expect(
          () => client.joinRelay(relayUrl: relayUrl),
          throwsStateError,
          reason: 'duplicate blocked while the retry is in flight',
        );
        gate.complete();
        final result = await future;
        expect(result.isAccepted, isTrue);
        expect(transport.connectCalls, 2);
        await client.disconnect();
      },
    );
  });
}
