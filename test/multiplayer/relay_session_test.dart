import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/join_payload.dart';
import 'package:turtle_king/multiplayer/protocol.dart';
import 'package:turtle_king/multiplayer/protocol_codec.dart';
import 'package:turtle_king/multiplayer/public_state.dart';
import 'package:turtle_king/multiplayer/relay_protocol.dart';
import 'package:turtle_king/multiplayer/relay_server.dart';
import 'package:turtle_king/multiplayer/relay_transport.dart';
import 'package:turtle_king/multiplayer/remote_driver.dart';
import 'package:turtle_king/multiplayer/session.dart';

import 'helpers.dart';

Future<void> pump([Duration duration = const Duration(milliseconds: 40)]) =>
    Future<void>.delayed(duration);

const Duration kSlow = Duration(seconds: 15);

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

GameState rosterGame(List<PublicPlayer> roster, {int seed = 7}) {
  return GameState(
    players: [
      for (final p in roster)
        testPlayer(roster.indexOf(p), id: p.id, name: p.name),
    ],
    random: Random(seed),
  );
}

/// A raw protocol-speaking WebSocket client for wire-level assertions: joins
/// through the relay and speaks the game protocol exactly as a real client
/// would, but lets the test inspect every frame.
class RawRelayClient {
  RawRelayClient({
    required this.relayUrl,
    required this.sessionId,
    required this.playerName,
  });

  final String relayUrl;
  final String sessionId;
  final String playerName;
  final MessageCodec codec = const MessageCodec();
  final List<String> received = [];
  final List<String> relayFrames = [];
  WebSocket? ws;
  int seq = 1;
  bool closed = false;

  Future<void> connect() async {
    ws = await WebSocket.connect(relayUrl);
    ws!.listen(
      (data) {
        if (data is! String) return;
        relayFrames.add(data);
        try {
          final frame = decodeRelayFrame(data);
          if (frame is RelayPeerFrame) received.add(frame.payload);
        } on Object {
          // ignore relay-level chatter while scanning protocol frames
        }
      },
      onDone: () => closed = true,
      onError: (_) => closed = true,
    );
    // Relay-level join handshake.
    await _sendRelay(RelayJoinFrame(sessionId: sessionId));
    await pumpUntil(() => _relayAck.isNotEmpty);
    // Game-level join request.
    await send(
      JoinRequestMessage(
        seq: seq++,
        sessionId: sessionId,
        playerName: playerName,
      ),
    );
  }

  List<RelayJoinAckFrame> get _relayAck {
    final acks = <RelayJoinAckFrame>[];
    for (final raw in relayFrames) {
      try {
        final frame = decodeRelayFrame(raw);
        if (frame is RelayJoinAckFrame) acks.add(frame);
      } on Object {
        // Ignore non-relay chatter while scanning for the join ack.
      }
    }
    return acks;
  }

  Future<void> _sendRelay(RelayFrame frame) async {
    ws!.add(frame.encode());
  }

  Future<void> send(MultiplayerMessage message) async {
    await _sendRelay(
      RelaySendFrame(
        sessionId: sessionId,
        to: kRelayHostMember,
        payload: codec.encode(message),
      ),
    );
  }

  List<MultiplayerMessage> get decoded {
    final result = <MultiplayerMessage>[];
    for (final raw in received) {
      try {
        result.add(codec.decode(raw));
      } on Object {
        // skip unparseable frames while scanning
      }
    }
    return result;
  }

  Future<T> awaitMessage<T extends MultiplayerMessage>({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      for (final message in decoded) {
        if (message is T) return message;
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('no ${T.toString()} received within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> close() async {
    try {
      await ws?.close();
    } catch (_) {}
  }
}

void main() {
  late RelayServer relay;
  late String relayUrl;

  setUp(() async {
    relay = RelayServer();
    final port = await relay.start(port: 0);
    relayUrl = 'ws://127.0.0.1:$port';
  });

  tearDown(() async {
    await relay.stop();
  });

  Future<HostSession> startHost(String sessionId, {String code = '483729'}) {
    final host = HostSession(
      sessionId: sessionId,
      joinCode: code,
      transport: RelayMultiplayerTransport(relayUrl: relayUrl),
    );
    return host
        .start(displayName: 'G', hostName: 'H', port: 0)
        .then((_) => host);
  }

  group('session over the relay', () {
    test('join + roster synchronize through the relay', () async {
      final host = await startHost('tk-s1');
      final mia = ClientSession(sessionId: 'tk-s1', playerName: 'Mia');
      final leo = ClientSession(sessionId: 'tk-s1', playerName: 'Leo');

      final miaJoin = await mia.joinRelay(relayUrl: relayUrl);
      final leoJoin = await leo.joinRelay(relayUrl: relayUrl);
      expect(miaJoin.isAccepted, isTrue);
      expect(leoJoin.isAccepted, isTrue);
      await pumpUntil(() => host.roster.length == 3, timeout: kSlow);
      expect(host.roster.map((p) => p.name), containsAll(['H', 'Mia', 'Leo']));
      expect(mia.self?.id, 'mp-1');
      expect(leo.self?.id, 'mp-2');

      await mia.disconnect();
      await leo.disconnect();
      await host.stop();
    });

    test(
      'full round gameplay: actions, state broadcasts, private cards',
      () async {
        final host = await startHost('tk-s2');
        final miaDriver = RemoteDriver(
          sessionId: 'tk-s2',
          playerName: 'Mia',
          relayUrl: relayUrl,
        );
        final leoDriver = RemoteDriver(
          sessionId: 'tk-s2',
          playerName: 'Leo',
          relayUrl: relayUrl,
        );
        final miaJoin = await miaDriver.joinRelay(relayUrl: relayUrl);
        final leoJoin = await leoDriver.joinRelay(relayUrl: relayUrl);
        expect(miaJoin.isAccepted, isTrue);
        expect(leoJoin.isAccepted, isTrue);
        await pumpUntil(() => host.roster.length == 3, timeout: kSlow);

        final game = rosterGame(host.roster, seed: 11);
        await host.startGame(game);
        await pumpUntil(
          () =>
              miaDriver.status == RemoteGameStatus.playing &&
              leoDriver.status == RemoteGameStatus.playing,
          timeout: kSlow,
        );
        expect(miaDriver.view.players.map((p) => p.name), ['H', 'Mia', 'Leo']);

        // Private cards are delivered per recipient.
        await pumpUntil(() => miaDriver.view.myCard != null, timeout: kSlow);
        await pumpUntil(() => leoDriver.view.myCard != null, timeout: kSlow);
        final miaCard = miaDriver.view.myCard!;
        final leoCard = leoDriver.view.myCard!;
        expect(miaCard, isNot(leoCard));

        // Viewing phase through the host.
        game.revealCurrentPlayer();
        host.broadcastHostAction();
        game.passToNextPlayer();
        host.broadcastHostAction();
        await pumpUntil(() => miaDriver.view.isMyTurn, timeout: kSlow);
        miaDriver.revealCurrentPlayer();
        await pumpUntil(
          () => miaDriver.view.currentPlayerRevealed,
          timeout: kSlow,
        );
        miaDriver.passToNextPlayer();
        await pumpUntil(() => leoDriver.view.isMyTurn, timeout: kSlow);
        leoDriver.revealCurrentPlayer();
        await pumpUntil(
          () => leoDriver.view.currentPlayerRevealed,
          timeout: kSlow,
        );
        leoDriver.passToNextPlayer();
        await pumpUntil(() => game.allPlayersViewed, timeout: kSlow);
        await pumpUntil(() => miaDriver.view.pouringStarted, timeout: kSlow);

        // Pouring completes the round.
        game.holdOut(game.players[0]);
        host.broadcastHostAction();
        await pumpUntil(() => miaDriver.view.isMyTurn, timeout: kSlow);
        miaDriver.holdOut();
        await pumpUntil(() => leoDriver.view.isMyTurn, timeout: kSlow);
        leoDriver.holdOut();
        await pumpUntil(() => game.roundComplete, timeout: kSlow);
        await pumpUntil(() => miaDriver.view.roundComplete, timeout: kSlow);

        // The host starts the next round; clients track the new round.
        game.startNextRound();
        host.broadcastHostAction();
        await pumpUntil(
          () => miaDriver.view.publicState.roundNumber == 2,
          timeout: kSlow,
        );
        expect(leoDriver.view.publicState.roundNumber, 2);

        await leoDriver.dispose();
        await miaDriver.dispose();
        await host.stop();
      },
    );

    test(
      'a client that reconnects reclaims its identity and resyncs',
      () async {
        final host = await startHost('tk-s3');
        final client = ClientSession(sessionId: 'tk-s3', playerName: 'Mia');
        final firstJoin = await client.joinRelay(relayUrl: relayUrl);
        expect(firstJoin.isAccepted, isTrue);
        expect(firstJoin.self?.id, 'mp-1');
        await pumpUntil(() => host.roster.length == 2, timeout: kSlow);

        // Drop the connection and rejoin with the same name: the host must
        // hand back the same identity instead of creating a duplicate.
        await client.disconnect();
        await pumpUntil(() => host.roster.length == 1, timeout: kSlow);
        final client2 = ClientSession(sessionId: 'tk-s3', playerName: 'Mia');
        final secondJoin = await client2.joinRelay(relayUrl: relayUrl);
        expect(secondJoin.isAccepted, isTrue);
        expect(secondJoin.self?.id, 'mp-1', reason: 'identity is reclaimed');
        await pumpUntil(() => host.roster.length == 2, timeout: kSlow);
        final mias = host.roster.where((p) => p.name == 'Mia');
        expect(mias.length, 1, reason: 'reconnect must not duplicate a player');

        await client2.disconnect();
        await host.stop();
      },
    );

    test('host loss maps to the friendly session-ended outcome', () async {
      final host = await startHost('tk-s4');
      final client = ClientSession(sessionId: 'tk-s4', playerName: 'Mia');
      expect((await client.joinRelay(relayUrl: relayUrl)).isAccepted, isTrue);
      await client.disconnect();

      await host.stop(); // host vanishes

      final lateClient = ClientSession(sessionId: 'tk-s4', playerName: 'Leo');
      final result = await lateClient.joinRelay(relayUrl: relayUrl);
      expect(result.isAccepted, isFalse);
      expect(result.outcome, JoinOutcome.sessionEnded);
      expect(result.reason, contains('no longer exists'));
      await lateClient.disconnect();
    });

    test(
      'stale duplicate actions are rejected by the host over the relay',
      () async {
        final host = await startHost('tk-s5');
        final client = RawRelayClient(
          relayUrl: relayUrl,
          sessionId: 'tk-s5',
          playerName: 'Mia',
        );
        await client.connect();
        await client.awaitMessage<JoinAcceptMessage>();

        final game = rosterGame(host.roster, seed: 5);
        await host.startGame(game);
        await client.awaitMessage<GameStartMessage>();

        // The host is the current viewer after startGame; move the turn to
        // Mia (mp-1) so her action is the valid one to duplicate.
        game.revealCurrentPlayer();
        host.broadcastHostAction();
        game.passToNextPlayer();
        host.broadcastHostAction();

        // Send the same action twice with the same sequence number: the first
        // is accepted, the duplicate is stale and must be rejected.
        final action = ActionRequestMessage(
          seq: 5,
          sessionId: 'tk-s5',
          action: GameAction.revealCurrentPlayer,
          playerId: 'mp-1',
        );
        await client.send(action);
        await client.awaitMessage<ActionAcceptedMessage>();
        await client.send(action);
        final rejection = await client.awaitMessage<ActionRejectedMessage>();
        expect(rejection.reason, contains('stale'));

        await client.close();
        await host.stop();
      },
    );
  });

  group('relay wire-level privacy', () {
    test(
      'public frames never carry card data; private updates are unicast',
      () async {
        final host = await startHost('tk-p1');
        final miaClient = RawRelayClient(
          relayUrl: relayUrl,
          sessionId: 'tk-p1',
          playerName: 'Mia',
        );
        final leoClient = RawRelayClient(
          relayUrl: relayUrl,
          sessionId: 'tk-p1',
          playerName: 'Leo',
        );
        await miaClient.connect();
        await leoClient.connect();
        await pumpUntil(() => host.roster.length == 3, timeout: kSlow);

        final game = rosterGame(host.roster, seed: 3);
        await host.startGame(game);
        await pumpUntil(
          () =>
              miaClient.decoded.whereType<GameStartMessage>().isNotEmpty &&
              leoClient.decoded.whereType<GameStartMessage>().isNotEmpty,
          timeout: kSlow,
        );

        // Wire-level scan: every frame the relay forwarded to EACH client.
        // The ONLY card-bearing channel is PRIVATE_UPDATE, which the relay
        // routes unicast to exactly one recipient (asserted below); every
        // other frame must be card-free.
        const forbidden = [
          'rank',
          'suit',
          'hand',
          'cards',
          'deck',
          'save',
          'GameState',
        ];
        for (final client in [miaClient, leoClient]) {
          for (final raw in client.received) {
            final decoded = jsonDecode(raw);
            if (decoded is Map && decoded['type'] == 'PRIVATE_UPDATE') {
              continue; // the authorized recipient-specific card channel
            }
            expectNoForbiddenKeys(decoded, forbidden);
          }
          // Relay routing frames themselves carry only session/member
          // metadata; the game payloads they embed are scanned above.
          for (final frame in client.relayFrames) {
            final relayFrame = decodeRelayFrame(frame);
            final encoded = relayFrame.encode();
            // The routing envelope must never itself contain card keys.
            expect(
              encoded,
              isNot(contains('"rank"')),
              reason: 'relay routing frame must not carry card data',
            );
            expect(
              encoded,
              isNot(contains('"suit"')),
              reason: 'relay routing frame must not carry card data',
            );
          }
        }

        // Private updates are unicast: Mia's PRIVATE_UPDATE arrives only at
        // Mia, Leo's only at Leo.
        await pumpUntil(
          () => miaClient.decoded.whereType<PrivateUpdateMessage>().isNotEmpty,
          timeout: kSlow,
        );
        await pumpUntil(
          () => leoClient.decoded.whereType<PrivateUpdateMessage>().isNotEmpty,
          timeout: kSlow,
        );
        final miaPrivate = miaClient.decoded
            .whereType<PrivateUpdateMessage>()
            .last;
        final leoPrivate = leoClient.decoded
            .whereType<PrivateUpdateMessage>()
            .last;
        expect(miaPrivate.privateState.recipientPlayerId, 'mp-1');
        expect(leoPrivate.privateState.recipientPlayerId, 'mp-2');
        // Leo never saw Mia's card and vice versa.
        expect(
          leoPrivate.privateState.card,
          isNot(miaPrivate.privateState.card),
        );

        await leoClient.close();
        await miaClient.close();
        await host.stop();
      },
    );

    test('the QR payload never assumes a LAN address', () {
      // The QR payload addresses the relay endpoint only: no local IPv4, no
      // LAN port, no multicast/discovery information.
      final payload = JoinPayload(
        sessionId: 'tk-x',
        joinCode: '483729',
        relayUrl: 'wss://relay.example.com',
      ).encode();
      expect(payload, isNot(contains('192.168')));
      expect(payload, isNot(contains('host')));
      expect(payload, isNot(contains('port')));
      expect(payload, contains('wss://relay.example.com'));
    });
  });
}
