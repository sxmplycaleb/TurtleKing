import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:turtle_king/multiplayer/relay_protocol.dart';

/// Standalone smoke test for a **live** relay process.
///
/// Exercises the full relay surface over real WebSockets against a running
/// relay (the compiled binary or `dart run tool/relay_server_main.dart`):
/// host registration, code lookup, client join, opaque frame routing in both
/// directions, and host-loss teardown.
///
/// Usage:
///
///     dart run tool/relay_server_main.dart --port 8787 &
///     dart run tool/relay_smoke_test.dart ws://127.0.0.1:8787
///
/// Prints PASS/FAIL and exits 0/1. This is intentionally protocol-level —
/// it talks raw relay frames, not the app's session layer.
Future<void> main(List<String> args) async {
  final relayUrl = args.isNotEmpty
      ? args.first
      : (Platform.environment['RELAY_URL'] ?? 'ws://127.0.0.1:8787');
  final random = Random.secure();
  final sessionId =
      'tk-smoke-${random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  final code =
      '${2 + random.nextInt(8)}'
      '${2 + random.nextInt(8)}'
      '${2 + random.nextInt(8)}'
      '${2 + random.nextInt(8)}'
      '${2 + random.nextInt(8)}'
      '${2 + random.nextInt(8)}';

  var failures = 0;
  Future<void> check(String name, bool ok) async {
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failures++;
  }

  final host = await WebSocket.connect(relayUrl);
  final hostFrames = <RelayFrame>[];
  host.listen(
    (data) {
      if (data is String) hostFrames.add(decodeRelayFrame(data));
    },
    onError: (_) {},
    cancelOnError: true,
  );

  Future<RelayFrame> expect(
    List<RelayFrame> from,
    Type type, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final frame in from) {
        if (frame.runtimeType == type) return frame;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw StateError('timed out waiting for $type');
  }

  // 1. Host registers a session.
  host.add(
    RelayHostFrame(
      sessionId: sessionId,
      joinCode: code,
      displayName: 'Smoke Test',
    ).encode(),
  );
  final registered =
      await expect(hostFrames, RelayRegisteredFrame) as RelayRegisteredFrame;
  await check(
    'host registers a session ($sessionId)',
    registered.sessionId == sessionId,
  );

  // 2. A code lookup resolves the fresh session.
  final looker = await WebSocket.connect(relayUrl);
  final lookerFrames = <RelayFrame>[];
  looker.listen((data) {
    if (data is String) lookerFrames.add(decodeRelayFrame(data));
  }, cancelOnError: true);
  looker.add(RelayLookupFrame(joinCode: code).encode());
  final ack =
      await expect(lookerFrames, RelayLookupAckFrame) as RelayLookupAckFrame;
  await check('code lookup resolves the session', ack.sessionId == sessionId);
  looker.add(RelayLookupFrame(joinCode: '999999').encode());
  final noMatch = await expect(lookerFrames, RelayLookupErrFrame);
  await check('wrong code lookup fails', noMatch is RelayLookupErrFrame);
  await looker.close();

  // 3. A client joins by session id.
  final client = await WebSocket.connect(relayUrl);
  final clientFrames = <RelayFrame>[];
  client.listen((data) {
    if (data is String) clientFrames.add(decodeRelayFrame(data));
  }, cancelOnError: true);
  client.add(RelayJoinFrame(sessionId: sessionId).encode());
  final joinAck =
      await expect(clientFrames, RelayJoinAckFrame) as RelayJoinAckFrame;
  await check('client joins the session', joinAck.sessionId == sessionId);
  await expect(hostFrames, RelayPeerJoinedFrame);

  // 4. Opaque frames route client → host and host → client.
  client.add(
    RelaySendFrame(
      sessionId: sessionId,
      to: kRelayHostMember,
      payload: '{"hello":"from-client"}',
    ).encode(),
  );
  final toHost = await expect(hostFrames, RelayPeerFrame) as RelayPeerFrame;
  await check('client frame reaches the host', toHost.payload.isNotEmpty);
  host.add(
    RelaySendFrame(
      sessionId: sessionId,
      to: joinAck.member,
      payload: '{"hello":"from-host"}',
    ).encode(),
  );
  final toClient = await expect(clientFrames, RelayPeerFrame) as RelayPeerFrame;
  await check('host frame reaches the client', toClient.payload.isNotEmpty);

  // 5. Host loss tears the session down: the client socket is closed.
  await host.close();
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  var hostLossOk = false;
  while (DateTime.now().isBefore(deadline) && !hostLossOk) {
    hostLossOk = client.readyState == WebSocket.closed;
    if (!hostLossOk) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  await check('host loss closes the member socket', hostLossOk);

  await client.close();
  stdout.writeln(
    failures == 0
        ? 'SMOKE TEST PASSED against $relayUrl'
        : 'SMOKE TEST FAILED: $failures check(s) failed against $relayUrl',
  );
  exit(failures == 0 ? 0 : 1);
}
