import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/relay_protocol.dart';
import 'package:turtle_king/multiplayer/relay_server_app.dart';

import 'helpers.dart' show RelayTestPeer;

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

void main() {
  group('RelayServerApp configuration', () {
    test('defaults apply when nothing is configured', () {
      final app = RelayServerApp.fromArgs(const [], environment: const {});
      expect(app.config.port, isNull);
      expect(app.config.bindAddress, isNull);
      expect(app.config.maxSessions, isNull);
      expect(app.config.sessionTtl, isNull);
    });

    test('environment variables configure the relay', () {
      final app = RelayServerApp.fromArgs(
        const [],
        environment: const {
          'RELAY_PORT': '9001',
          'RELAY_BIND_ADDRESS': '127.0.0.1',
          'RELAY_MAX_SESSIONS': '10',
          'RELAY_SESSION_TTL_MINUTES': '5',
        },
      );
      expect(app.config.port, 9001);
      expect(app.config.bindAddress, '127.0.0.1');
      expect(app.config.maxSessions, 10);
      expect(app.config.sessionTtl, const Duration(minutes: 5));
    });

    test('CLI flags override environment variables', () {
      final app = RelayServerApp.fromArgs(
        const ['--port', '9090', '--bind', '10.0.0.5'],
        environment: const {
          'RELAY_PORT': '9001',
          'RELAY_BIND_ADDRESS': '127.0.0.1',
        },
      );
      expect(app.config.port, 9090);
      expect(app.config.bindAddress, '10.0.0.5');
    });

    test('Render PORT is honored when RELAY_PORT is not set', () {
      final app = RelayServerApp.fromArgs(
        const [],
        environment: const {'PORT': '9123'},
      );
      expect(app.config.port, 9123);
    });

    test('RELAY_PORT takes precedence over Render PORT', () {
      final app = RelayServerApp.fromArgs(
        const [],
        environment: const {'RELAY_PORT': '9001', 'PORT': '9123'},
      );
      expect(app.config.port, 9001);
    });

    test('CLI --port overrides both RELAY_PORT and Render PORT', () {
      final app = RelayServerApp.fromArgs(
        const ['--port', '9090'],
        environment: const {'RELAY_PORT': '9001', 'PORT': '9123'},
      );
      expect(app.config.port, 9090);
    });

    test('an invalid bind address is rejected at run time', () async {
      final app = RelayServerApp.fromArgs(const [
        '--bind',
        'not-an-ip',
      ], environment: const {});
      await expectLater(app.run(), throwsArgumentError);
    });
  });

  group('RelayServerApp lifecycle', () {
    test('app binds the Render PORT end to end', () async {
      // PORT 0 → ephemeral port, proving the env value flows into the bind.
      final app = RelayServerApp.fromArgs(
        const [],
        environment: const {'PORT': '0'},
      );
      final runFuture = app.run();
      await pumpUntil(() => app.boundPort != null);
      expect(app.boundPort, isNotNull);
      app.requestShutdown();
      await runFuture;
    });

    test(
      'run() serves the relay and shuts down gracefully on request',
      () async {
        final logs = <String>[];
        final app = RelayServerApp(
          config: const RelayServerConfig(port: 0),
          logger: logs.add,
        );
        final runFuture = app.run();
        await pumpUntil(() => app.boundPort != null);
        final url = 'ws://127.0.0.1:${app.boundPort}';

        // The running relay serves a real session.
        final h = await RelayTestPeer.connect(url);
        final registered = await h.exchange(
          const RelayHostFrame(
            sessionId: 'tk-app',
            joinCode: '483729',
            displayName: 'G',
          ),
        );
        expect(registered, isA<RelayRegisteredFrame>());
        expect(app.server!.sessionCount, 1);

        // Graceful shutdown: the session's sockets are closed, run() returns
        // the bound port, and the server is released.
        app.requestShutdown();
        final bound = await runFuture;
        expect(bound, app.boundPort);
        expect(app.server, isNull);
        expect(logs.any((l) => l.contains('listening')), isTrue);
        expect(logs.any((l) => l.contains('shutting down')), isTrue);
        await pumpUntil(() => h.closed);
        expect(h.closed, isTrue, reason: 'socket closed during graceful stop');
        await h.close();
      },
    );
  });
}
