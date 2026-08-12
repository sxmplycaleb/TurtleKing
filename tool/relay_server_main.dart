import 'dart:async';
import 'dart:io';

import 'package:turtle_king/multiplayer/relay_server.dart';

/// Standalone internet multiplayer relay.
///
/// Run locally for development:
///
///     dart run tool/relay_server_main.dart            # binds 0.0.0.0:8787
///     dart run tool/relay_server_main.dart --port 9000
///
/// Deploy to production on any host that supports WebSockets (VPS, Render,
/// Fly.io, …) and terminate TLS in front of it (Caddy/nginx) so the app can
/// reach it over `wss://`. The app connects with:
///
///     flutter run --dart-define=RELAY_URL=wss://your-relay.example.com
///
/// See docs/multiplayer/m18-architecture.md §8 for deployment details.
Future<void> main(List<String> args) async {
  var port = 8787;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') {
      port = int.parse(args[i + 1]);
    }
  }
  final relay = RelayServer();
  final bound = await relay.start(port: port);
  stdout.writeln('Turtle King relay listening on 0.0.0.0:$bound');
  stdout.writeln(
    'Configure the app with --dart-define=RELAY_URL=ws://<this-host>:$bound',
  );
  // Keep the process alive until terminated.
  await Completer<void>().future;
}
