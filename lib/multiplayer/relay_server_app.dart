import 'dart:async';
import 'dart:io';

import 'relay_server.dart';

/// Parsed configuration for the standalone relay process.
///
/// Sources, in increasing precedence:
/// 1. built-in defaults,
/// 2. environment variables (`RELAY_BIND_ADDRESS`, `RELAY_PORT`,
///    `RELAY_MAX_SESSIONS`, `RELAY_SESSION_TTL_MINUTES`), plus the
///    platform-standard `PORT` (Render injects this) used only when
///    `RELAY_PORT` is absent,
/// 3. command-line flags (`--bind`, `--port`, `--max-sessions`,
///    `--session-ttl-minutes`).
class RelayServerConfig {
  const RelayServerConfig({
    this.bindAddress,
    this.port,
    this.maxSessions,
    this.sessionTtl,
  });

  /// Bind address (null → all IPv4 interfaces, like `0.0.0.0`).
  final String? bindAddress;

  /// Listen port (null → default 8787; 0 → ephemeral, for tests).
  final int? port;

  /// Hard cap on concurrent sessions.
  final int? maxSessions;

  /// Idle session lifetime.
  final Duration? sessionTtl;
}

/// The standalone relay process: reads configuration, starts a [RelayServer],
/// installs SIGINT/SIGTERM handlers, and shuts down gracefully when the
/// process is asked to stop.
///
/// Kept in `lib/` (not `tool/`) so it is covered by the normal test suite;
/// `tool/relay_server_main.dart` is a two-line wrapper around it.
class RelayServerApp {
  RelayServerApp({this.config = const RelayServerConfig(), this.logger});

  final RelayServerConfig config;

  /// Where lifecycle log lines go. Defaults to stdout with a timestamp;
  /// tests inject a capture. Log lines never contain join codes or
  /// game-protocol payloads (see [RelayServer.onLog]).
  final void Function(String message)? logger;

  RelayServer? _server;
  int? _boundPort;
  Completer<void>? _shutdown;

  /// The bound port once [run] has started (valid for tests with port 0).
  int? get boundPort => _boundPort;

  /// The running relay (tests inspect session counts).
  RelayServer? get server => _server;

  static RelayServerApp fromArgs(
    List<String> args, {
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final parsed = _parse(args, env);
    return RelayServerApp(config: parsed);
  }

  static RelayServerConfig _parse(List<String> args, Map<String, String> env) {
    String? bindAddress;
    int? port;
    int? maxSessions;
    Duration? sessionTtl;

    String? read(String name) {
      final value = env[name];
      return (value == null || value.isEmpty) ? null : value;
    }

    final envAddress = read('RELAY_BIND_ADDRESS');
    if (envAddress != null) bindAddress = envAddress;
    // Render supplies a platform-chosen `PORT`; it is used only when the
    // explicit `RELAY_PORT` is absent. CLI `--port` still wins over both.
    final envPort = read('RELAY_PORT') ?? read('PORT');
    if (envPort != null) port = int.parse(envPort);
    final envMax = read('RELAY_MAX_SESSIONS');
    if (envMax != null) maxSessions = int.parse(envMax);
    final envTtl = read('RELAY_SESSION_TTL_MINUTES');
    if (envTtl != null) sessionTtl = Duration(minutes: int.parse(envTtl));

    // CLI flags win over environment.
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--bind':
        case '--address':
          bindAddress = args[++i];
          break;
        case '--port':
          port = int.parse(args[++i]);
          break;
        case '--max-sessions':
          maxSessions = int.parse(args[++i]);
          break;
        case '--session-ttl-minutes':
          sessionTtl = Duration(minutes: int.parse(args[++i]));
          break;
        default:
          break;
      }
    }
    return RelayServerConfig(
      bindAddress: bindAddress,
      port: port,
      maxSessions: maxSessions,
      sessionTtl: sessionTtl,
    );
  }

  /// Starts the relay and blocks until the process is asked to stop
  /// (SIGINT/SIGTERM, or [requestShutdown] in tests). Returns the bound
  /// port. Always stops the relay before returning.
  Future<int> run() async {
    final relay = RelayServer(
      onLog: logger ?? _defaultLogger,
      maxSessions: config.maxSessions ?? 64,
      sessionTtl: config.sessionTtl ?? const Duration(minutes: 30),
    );
    _server = relay;
    final address = config.bindAddress == null
        ? null
        : InternetAddress.tryParse(config.bindAddress!);
    if (config.bindAddress != null && address == null) {
      throw ArgumentError.value(
        config.bindAddress,
        'bindAddress',
        'not a valid IP address',
      );
    }
    _boundPort = await relay.start(port: config.port ?? 8787, address: address);
    _log(
      'Turtle King relay listening on '
      '${config.bindAddress ?? '0.0.0.0'}:$_boundPort',
    );
    _log(
      'app: build with --dart-define=RELAY_URL=ws://<this-host>:$_boundPort '
      '(use wss:// when TLS terminates in front of this relay)',
    );
    final shutdown = Completer<void>();
    _shutdown = shutdown;
    // Watching a signal keeps the event loop alive for as long as the
    // subscription is open, so the subscriptions must be cancelled once
    // shutdown is requested — otherwise the process would never exit after
    // [run] returns (SIGTERM/SIGINT in a container would only hang it).
    final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
    for (final signal in const [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signalSubscriptions.add(
        signal.watch().listen(
          (_) {
            if (!shutdown.isCompleted) shutdown.complete();
          },
          onError: (_) {
            // Signal not supported or not delivered on this platform
            // (e.g. SIGTERM on Windows) — nothing to watch.
          },
        ),
      );
    }
    await shutdown.future;
    for (final subscription in signalSubscriptions) {
      await subscription.cancel();
    }
    _log('shutting down');
    await relay.stop();
    _server = null;
    return _boundPort!;
  }

  /// Completes the shutdown future so [run] stops the relay and returns
  /// (tests; also the handler behind SIGINT/SIGTERM).
  void requestShutdown() {
    _shutdown?.complete();
  }

  void _log(String message) {
    (logger ?? _defaultLogger)(message);
  }

  static void _defaultLogger(String message) {
    final now = DateTime.now();
    final stamp = [
      now.year.toString().padLeft(4, '0'),
      now.month.toString().padLeft(2, '0'),
      now.day.toString().padLeft(2, '0'),
    ].join('-');
    final time = [
      now.hour.toString().padLeft(2, '0'),
      now.minute.toString().padLeft(2, '0'),
      now.second.toString().padLeft(2, '0'),
    ].join(':');
    stdout.writeln('[$stamp $time] $message');
  }
}
