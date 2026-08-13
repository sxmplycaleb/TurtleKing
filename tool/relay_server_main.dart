import 'dart:io';

import 'package:turtle_king/multiplayer/relay_server_app.dart';

/// Standalone internet multiplayer relay.
///
/// Compile and run:
///
///     dart compile exe tool/relay_server_main.dart -o build/relay_server
///     ./build/relay_server
///
/// or run from source:
///
///     dart run tool/relay_server_main.dart
///
/// Configuration (defaults → environment → CLI flags):
///
/// | Setting        | Env var                    | Flag                 | Default |
/// | -------------- | -------------------------- | -------------------- | ------- |
/// | bind address   | `RELAY_BIND_ADDRESS`       | `--bind <addr>`      | `0.0.0.0` |
/// | port           | `RELAY_PORT`               | `--port <n>`         | `8787` |
/// | max sessions   | `RELAY_MAX_SESSIONS`       | `--max-sessions <n>` | `64` |
/// | session TTL    | `RELAY_SESSION_TTL_MINUTES`| `--session-ttl-minutes <n>` | `30` |
///
/// The relay terminates TLS at a reverse proxy (Caddy/nginx) so the app can
/// reach it over `wss://`. See docs/multiplayer/m18-relay-deployment.md.
Future<void> main(List<String> args) async {
  final app = RelayServerApp.fromArgs(args);
  try {
    await app.run();
  } on ArgumentError catch (error) {
    stderr.writeln('relay: ${error.message}');
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('relay: fatal: $error');
    exitCode = 1;
  }
}
