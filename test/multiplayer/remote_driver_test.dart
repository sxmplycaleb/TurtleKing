import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/private_state.dart';
import 'package:turtle_king/multiplayer/protocol.dart';
import 'package:turtle_king/multiplayer/protocol_codec.dart';
import 'package:turtle_king/multiplayer/public_state.dart';
import 'package:turtle_king/multiplayer/remote_driver.dart';

import 'helpers.dart';

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 60));

const Duration kSlow = Duration(seconds: 12);

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

/// A minimal raw server that accepts one client and records what it sends.
class ScriptedServer {
  final MessageCodec codec = const MessageCodec();
  final List<String> received = <String>[];
  final List<MultiplayerMessage> replies = [];
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

  Future<void> close() async {
    await server?.close();
    await socket?.close();
  }
}

void main() {
  group('RemoteDriver join + lobby', () {
    test('join drives status from connecting to inLobby', () async {
      final server = ScriptedServer();
      final port = await server.start();

      final driver = RemoteDriver(sessionId: 's', playerName: 'Mia');
      final statuses = <RemoteGameStatus>[];
      final sub = driver.events.listen((e) => statuses.add(e.status));

      final joinFuture = driver.join(hostAddress: '127.0.0.1', port: port);
      await pumpUntil(() => server.received.isNotEmpty);
      await server.send(
        JoinAcceptMessage(
          seq: 1,
          sessionId: 's',
          playerId: 'mp-1',
          color: 1,
          roster: const [],
        ),
      );
      await joinFuture;
      expect(driver.status, RemoteGameStatus.inLobby);
      expect(statuses, contains(RemoteGameStatus.connecting));
      // Broadcast-stream delivery is asynchronous: poll for the event rather
      // than asserting immediately (the status field is already settled).
      await pumpUntil(() => statuses.contains(RemoteGameStatus.inLobby));
      expect(driver.view.players, isEmpty);

      await driver.dispose();
      await server.close();
      await sub.cancel();
    });

    test('join failure surfaces connectionFailed without throwing', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();

      final driver = RemoteDriver(sessionId: 's', playerName: 'Mia');
      final result = await driver.join(
        hostAddress: '127.0.0.1',
        port: deadPort,
      );
      expect(result.isAccepted, isFalse);
      expect(driver.status, RemoteGameStatus.connectionFailed);

      await driver.dispose();
    });
  });

  group('RemoteDriver gameplay', () {
    test('gameStarted builds the view; state updates replace it', () async {
      final server = ScriptedServer();
      final port = await server.start();
      final driver = RemoteDriver(sessionId: 's', playerName: 'Mia');
      final joinFuture = driver.join(hostAddress: '127.0.0.1', port: port);
      await pumpUntil(() => server.received.isNotEmpty);
      await server.send(
        JoinAcceptMessage(
          seq: 1,
          sessionId: 's',
          playerId: 'mp-1',
          color: 1,
          roster: const [
            PublicPlayer(id: 'host', name: 'H', color: 1),
            PublicPlayer(id: 'mp-1', name: 'Mia', color: 2),
          ],
        ),
      );
      await joinFuture;

      final game = testGame(2);
      final public = PublicStateView.fromGame(game);
      await server.send(
        GameStartMessage(
          seq: 2,
          sessionId: 's',
          gameId: 'g',
          publicState: public,
        ),
      );
      await pumpUntil(() => driver.status == RemoteGameStatus.playing);
      expect(driver.view.players.map((p) => p.id), ['p0', 'p1']);

      // A later state update replaces the view.
      await server.send(
        StateUpdateMessage(
          seq: 3,
          sessionId: 's',
          stateSeq: 1,
          publicState: public,
        ),
      );
      await pumpUntil(() => driver.view.publicState.roundNumber == 1);
      expect(driver.view.publicState, isNotNull);

      await driver.dispose();
      await server.close();
    });

    test(
      'actions send ACTION_REQUEST and never execute rules locally',
      () async {
        final server = ScriptedServer();
        final port = await server.start();
        final driver = RemoteDriver(sessionId: 's', playerName: 'Mia');
        final joinFuture = driver.join(hostAddress: '127.0.0.1', port: port);
        await pumpUntil(() => server.received.isNotEmpty);
        await server.send(
          JoinAcceptMessage(
            seq: 1,
            sessionId: 's',
            playerId: 'mp-1',
            color: 1,
            roster: const [
              PublicPlayer(id: 'host', name: 'H', color: 1),
              PublicPlayer(id: 'mp-1', name: 'Mia', color: 2),
            ],
          ),
        );
        await joinFuture;
        await server.send(
          GameStartMessage(
            seq: 2,
            sessionId: 's',
            gameId: 'g',
            publicState: PublicStateView.fromGame(testGame(2)),
          ),
        );
        await pumpUntil(() => driver.status == RemoteGameStatus.playing);

        driver.revealCurrentPlayer();
        driver.callYamada();
        await pumpUntil(() => server.received.length >= 2);

        final requests = server.received
            .map((raw) => server.codec.decode(raw))
            .whereType<ActionRequestMessage>()
            .toList();
        expect(requests, hasLength(2));
        expect(requests[0].action, GameAction.revealCurrentPlayer);
        expect(requests[1].action, GameAction.callYamada);
        expect(requests[0].playerId, 'mp-1');

        await driver.dispose();
        await server.close();
      },
    );

    test('action rejection surfaces as a rejection event', () async {
      final server = ScriptedServer();
      final port = await server.start();
      final driver = RemoteDriver(sessionId: 's', playerName: 'Mia');
      final joinFuture = driver.join(hostAddress: '127.0.0.1', port: port);
      await pumpUntil(() => server.received.isNotEmpty);
      await server.send(
        JoinAcceptMessage(
          seq: 1,
          sessionId: 's',
          playerId: 'mp-1',
          color: 1,
          roster: const [
            PublicPlayer(id: 'host', name: 'H', color: 1),
            PublicPlayer(id: 'mp-1', name: 'Mia', color: 2),
          ],
        ),
      );
      await joinFuture;
      await server.send(
        GameStartMessage(
          seq: 2,
          sessionId: 's',
          gameId: 'g',
          publicState: PublicStateView.fromGame(testGame(2)),
        ),
      );
      await pumpUntil(() => driver.status == RemoteGameStatus.playing);

      String? rejection;
      final sub = driver.events.listen((e) => rejection ??= e.rejection);
      driver.revealCurrentPlayer();
      await server.send(
        ActionRejectedMessage(
          seq: 3,
          sessionId: 's',
          action: GameAction.revealCurrentPlayer,
          requestSeq: 0,
          reason: 'not your turn',
        ),
      );
      await pumpUntil(() => rejection != null);
      expect(rejection, contains('not your turn'));

      await sub.cancel();
      await driver.dispose();
      await server.close();
    });

    test('actions are blocked when disconnected', () async {
      final server = ScriptedServer();
      await server.start();
      final driver = RemoteDriver(sessionId: 's', playerName: 'Mia');
      // Never joined: actions must be no-ops.
      driver.revealCurrentPlayer();
      driver.holdOut();
      await pump();
      expect(server.received, isEmpty);

      await driver.dispose();
      await server.close();
    });
  });

  group('RemoteDriver private card + privacy', () {
    test('only the client\'s own card is retained in the view', () async {
      final server = ScriptedServer();
      final port = await server.start();
      final driver = RemoteDriver(sessionId: 's', playerName: 'Mia');
      final joinFuture = driver.join(hostAddress: '127.0.0.1', port: port);
      await pumpUntil(() => server.received.isNotEmpty);
      await server.send(
        JoinAcceptMessage(
          seq: 1,
          sessionId: 's',
          playerId: 'mp-1',
          color: 1,
          roster: const [
            PublicPlayer(id: 'host', name: 'H', color: 1),
            PublicPlayer(id: 'mp-1', name: 'Mia', color: 2),
          ],
        ),
      );
      await joinFuture;
      await server.send(
        GameStartMessage(
          seq: 2,
          sessionId: 's',
          gameId: 'g',
          publicState: PublicStateView.fromGame(testGame(2)),
        ),
      );
      await pumpUntil(() => driver.status == RemoteGameStatus.playing);

      // Deliver this client's card.
      await server.send(
        PrivateUpdateMessage(
          seq: 3,
          sessionId: 's',
          stateSeq: 1,
          privateState: PrivateStateView(
            recipientPlayerId: 'mp-1',
            round: 1,
            card: const PrivateCard(suit: 'hearts', rank: 'ace'),
          ),
        ),
      );
      await pumpUntil(() => driver.view.myCard != null);
      expect(driver.view.myCard!.rank, 'ace');

      // A card addressed to someone else must be ignored.
      await server.send(
        PrivateUpdateMessage(
          seq: 4,
          sessionId: 's',
          stateSeq: 1,
          privateState: PrivateStateView(
            recipientPlayerId: 'mp-2',
            round: 1,
            card: const PrivateCard(suit: 'spades', rank: 'king'),
          ),
        ),
      );
      await pump();
      expect(driver.view.myCard!.rank, 'ace');

      await driver.dispose();
      await server.close();
    });
  });

  group('RemoteDriver reconnection', () {
    test('connection loss starts a bounded reconnect and resync', () async {
      final server = ScriptedServer();
      final port = await server.start();
      final driver = RemoteDriver(
        sessionId: 's',
        playerName: 'Mia',
        reconnectAttempts: 2,
        reconnectBaseDelay: const Duration(milliseconds: 50),
      );
      final joinFuture = driver.join(hostAddress: '127.0.0.1', port: port);
      await pumpUntil(() => server.received.isNotEmpty);
      await server.send(
        JoinAcceptMessage(
          seq: 1,
          sessionId: 's',
          playerId: 'mp-1',
          color: 1,
          roster: const [
            PublicPlayer(id: 'host', name: 'H', color: 1),
            PublicPlayer(id: 'mp-1', name: 'Mia', color: 2),
          ],
        ),
      );
      await joinFuture;

      final statuses = <RemoteGameStatus>[];
      final sub = driver.events.listen((e) => statuses.add(e.status));

      // Kill the connection: the driver should begin reconnecting.
      server.socket?.destroy();
      await pumpUntil(
        () => statuses.contains(RemoteGameStatus.reconnecting),
        timeout: kSlow,
      );
      expect(statuses, contains(RemoteGameStatus.reconnecting));

      await sub.cancel();
      await driver.dispose();
      await server.close();
    });
  });
}
