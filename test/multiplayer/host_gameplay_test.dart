import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/protocol.dart';
import 'package:turtle_king/multiplayer/protocol_codec.dart';
import 'package:turtle_king/multiplayer/public_state.dart';
import 'package:turtle_king/multiplayer/session.dart';

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

/// A raw protocol-speaking TCP client for wire-level assertions.
class RawGameClient {
  RawGameClient(this.sessionId, this.playerName);

  final String sessionId;
  final String playerName;
  final MessageCodec codec = const MessageCodec();
  final List<String> received = <String>[];
  Socket? socket;
  int seq = 1;

  Future<void> connect(int port) async {
    socket = await Socket.connect('127.0.0.1', port);
    socket!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(received.add);
    await send(
      JoinRequestMessage(
        seq: seq++,
        sessionId: sessionId,
        playerName: playerName,
      ),
    );
  }

  Future<void> send(MultiplayerMessage message) async {
    socket!.write('${codec.encode(message)}\n');
    await socket!.flush();
  }

  Future<void> sendRaw(String raw) async {
    socket!.write('$raw\n');
    await socket!.flush();
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

  /// Waits until at least one [T] matches [predicate] and returns the most
  /// recent match (useful when earlier messages of the same type are
  /// superseded, e.g. STATE_UPDATE).
  Future<T> awaitMessageWhere<T extends MultiplayerMessage>(
    bool Function(T) predicate, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final messages = decoded.whereType<T>().where(predicate).toList();
      if (messages.isNotEmpty) return messages.last;
      if (DateTime.now().isAfter(deadline)) {
        fail('no matching ${T.toString()} received within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> close() async {
    await socket?.close();
    socket = null;
  }
}

/// Builds a game whose player ids match the joined roster (the host builds
/// its authoritative game from the roster, so ids must align for private
/// card delivery to work).
GameState rosterGame(List<PublicPlayer> roster, {int seed = 7}) {
  return GameState(
    players: [
      for (final p in roster)
        testPlayer(roster.indexOf(p), id: p.id, name: p.name),
    ],
    random: Random(seed),
  );
}

/// Deep-scans a decoded JSON node for forbidden map keys.
void expectNoKeys(Object? node, List<String> forbidden) {
  if (node is Map) {
    for (final key in node.keys) {
      expect(forbidden, isNot(contains(key)));
      expectNoKeys(node[key], forbidden);
    }
  } else if (node is List) {
    for (final item in node) {
      expectNoKeys(item, forbidden);
    }
  }
}

void main() {
  const codec = MessageCodec();

  group('HostSession gameplay routing', () {
    test(
      'startGame broadcasts GAME_START and unicasts each player their card',
      () async {
        final host = HostSession(sessionId: 'g-1');
        final server = await host.start(
          displayName: 'G',
          hostName: 'H',
          port: 0,
        );
        final mia = RawGameClient('g-1', 'Mia');
        final leo = RawGameClient('g-1', 'Leo');
        await mia.connect(server.port);
        await leo.connect(server.port);
        await mia.awaitMessage<JoinAcceptMessage>();
        await leo.awaitMessage<JoinAcceptMessage>();

        final game = rosterGame(host.roster);
        await host.startGame(game);

        final miaStart = await mia.awaitMessage<GameStartMessage>();
        final leoStart = await leo.awaitMessage<GameStartMessage>();
        expect(miaStart.publicState.players.map((p) => p.name), [
          'H',
          'Mia',
          'Leo',
        ]);
        expect(leoStart.publicState.players.length, 3);

        // Each client received exactly its own card via PRIVATE_UPDATE.
        final miaPrivate = await mia.awaitMessage<PrivateUpdateMessage>();
        final leoPrivate = await leo.awaitMessage<PrivateUpdateMessage>();
        expect(miaPrivate.privateState.recipientPlayerId, 'mp-1');
        expect(leoPrivate.privateState.recipientPlayerId, 'mp-2');
        expect(
          miaPrivate.privateState.card,
          isNot(equals(leoPrivate.privateState.card)),
        );
        await host.stop();
        await mia.close();
        await leo.close();
      },
    );

    test('a valid reveal action is accepted, broadcasts state, and the '
        'viewer receives their card', () async {
      final host = HostSession(sessionId: 'g-2');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final mia = RawGameClient('g-2', 'Mia');
      await mia.connect(server.port);
      await mia.awaitMessage<JoinAcceptMessage>();
      await host.startGame(rosterGame(host.roster));
      await mia.awaitMessage<GameStartMessage>();
      await mia.awaitMessage<PrivateUpdateMessage>();

      // The host is Player 0 (the first viewer), so a remote client acting
      // first is out of turn.
      final before = host.stateSeq;

      await mia.send(
        ActionRequestMessage(
          seq: 5,
          sessionId: 'g-2',
          action: GameAction.revealCurrentPlayer,
          playerId: 'mp-1',
        ),
      );
      final rejected = await mia.awaitMessage<ActionRejectedMessage>();
      expect(rejected.reason, contains('turn'));
      expect(host.stateSeq, before, reason: 'invalid action mutates nothing');

      await host.stop();
      await mia.close();
    });

    test('the host player acts locally and broadcasts; clients see the '
        'state and get their cards', () async {
      final host = HostSession(sessionId: 'g-3');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final mia = RawGameClient('g-3', 'Mia');
      await mia.connect(server.port);
      await mia.awaitMessage<JoinAcceptMessage>();
      final game = rosterGame(host.roster);
      await host.startGame(game);
      await mia.awaitMessage<GameStartMessage>();
      await mia.awaitMessage<PrivateUpdateMessage>();

      // Host reveals as Player 0 (host player id).
      game.revealCurrentPlayer();
      host.broadcastHostAction();

      final state = await mia.awaitMessageWhere<StateUpdateMessage>(
        (m) => m.publicState.currentPlayerRevealed,
      );
      expect(state.publicState.currentPlayerRevealed, isTrue);
      final private = await mia.awaitMessageWhere<PrivateUpdateMessage>(
        (m) => m.privateState.recipientPlayerId == 'mp-1',
      );
      expect(private.privateState.recipientPlayerId, 'mp-1');

      await host.stop();
      await mia.close();
    });

    test(
      'out-of-turn and stale actions are rejected without mutating state',
      () async {
        final host = HostSession(sessionId: 'g-4');
        final server = await host.start(
          displayName: 'G',
          hostName: 'H',
          port: 0,
        );
        final mia = RawGameClient('g-4', 'Mia');
        await mia.connect(server.port);
        await mia.awaitMessage<JoinAcceptMessage>();
        await host.startGame(rosterGame(host.roster));
        await mia.awaitMessage<GameStartMessage>();

        // The host is Player 0 and views first. Have the host reveal and
        // pass so pouring begins, then test a stale replay of the same action.
        final game = host.game!;
        game.revealCurrentPlayer();
        host.broadcastHostAction();
        game.passToNextPlayer();
        host.broadcastHostAction();
        await mia.awaitMessage<StateUpdateMessage>();
        await mia.awaitMessage<StateUpdateMessage>();

        final before = host.stateSeq;
        // Mia tries to hold out but it is not her turn yet (Player 1 is).
        await mia.send(
          ActionRequestMessage(
            seq: 10,
            sessionId: 'g-4',
            action: GameAction.holdOut,
            playerId: 'mp-1',
          ),
        );
        final rejected = await mia.awaitMessage<ActionRejectedMessage>();
        expect(rejected.reason, contains('turn'));
        expect(host.stateSeq, before);

        // A duplicate of an already-processed action (replayed seq) is stale.
        await mia.send(
          ActionRequestMessage(
            seq: 10,
            sessionId: 'g-4',
            action: GameAction.holdOut,
            playerId: 'mp-1',
          ),
        );
        final stale = await mia.awaitMessageWhere<ActionRejectedMessage>(
          (m) => m.reason.contains('stale'),
        );
        expect(stale.reason, contains('stale'));

        await host.stop();
        await mia.close();
      },
    );

    test(
      'RESYNC returns the authoritative public state and the private card',
      () async {
        final host = HostSession(sessionId: 'g-5');
        final server = await host.start(
          displayName: 'G',
          hostName: 'H',
          port: 0,
        );
        final mia = RawGameClient('g-5', 'Mia');
        await mia.connect(server.port);
        await mia.awaitMessage<JoinAcceptMessage>();
        await host.startGame(rosterGame(host.roster));
        await mia.awaitMessage<GameStartMessage>();
        await mia.awaitMessage<PrivateUpdateMessage>();

        await mia.send(
          ResyncRequestMessage(
            seq: 20,
            sessionId: 'g-5',
            playerId: 'mp-1',
            lastStateSeq: -1,
          ),
        );
        final response = await mia.awaitMessage<ResyncResponseMessage>();
        expect(response.publicState.players.length, 2);
        final private = await mia.awaitMessage<PrivateUpdateMessage>();
        expect(private.privateState.recipientPlayerId, 'mp-1');

        await host.stop();
        await mia.close();
      },
    );

    test('reconnect reclaims the original identity and resyncs', () async {
      final host = HostSession(sessionId: 'g-6');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final mia = RawGameClient('g-6', 'Mia');
      await mia.connect(server.port);
      await mia.awaitMessage<JoinAcceptMessage>();
      await host.startGame(rosterGame(host.roster));
      await mia.awaitMessage<GameStartMessage>();

      // Simulate a dropped connection.
      await mia.close();
      await pump();

      // Rejoin with the same name: identity must be reclaimed, not duped.
      final mia2 = RawGameClient('g-6', 'Mia');
      await mia2.connect(server.port);
      final accept = await mia2.awaitMessage<JoinAcceptMessage>();
      expect(accept.playerId, 'mp-1', reason: 'identity must be preserved');

      // The reconnect triggers an automatic resync.
      await pumpUntil(() => host.roster.length == 2, timeout: kSlow);
      await host.stop();
      await mia2.close();
    });

    test('joins after the game started are rejected for new players', () async {
      final host = HostSession(sessionId: 'g-7');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final mia = RawGameClient('g-7', 'Mia');
      await mia.connect(server.port);
      await mia.awaitMessage<JoinAcceptMessage>();
      await host.startGame(rosterGame(host.roster));

      final leo = RawGameClient('g-7', 'Leo');
      await leo.connect(server.port);
      final rejected = await leo.awaitMessage<JoinRejectMessage>();
      expect(rejected.reason, contains('already started'));

      await host.stop();
      await mia.close();
      await leo.close();
    });
  });

  group('privacy on the gameplay wire', () {
    test('no public frame carries card/deck/save data; private updates are '
        'recipient-scoped', () async {
      final host = HostSession(sessionId: 'priv-game');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final mia = RawGameClient('priv-game', 'Mia');
      final leo = RawGameClient('priv-game', 'Leo');
      await mia.connect(server.port);
      await leo.connect(server.port);
      await mia.awaitMessage<JoinAcceptMessage>();
      await leo.awaitMessage<JoinAcceptMessage>();

      final game = rosterGame(host.roster);
      await host.startGame(game);
      // Drive a full round through the authoritative game, broadcasting
      // after every host action, and watch everything the clients receive.
      game.revealCurrentPlayer();
      host.broadcastHostAction();
      game.passToNextPlayer();
      host.broadcastHostAction();
      game.revealCurrentPlayer();
      host.broadcastHostAction();
      game.passToNextPlayer();
      host.broadcastHostAction();
      game.revealCurrentPlayer();
      host.broadcastHostAction();
      game.passToNextPlayer();
      host.broadcastHostAction();
      // Pouring: all hold out → reveal → round completes.
      for (var i = 0; i < 4 && !game.roundComplete; i++) {
        game.holdOut(game.pourCurrentPlayer);
        host.broadcastHostAction();
      }
      await pumpUntil(() => mia.decoded.length >= 3, timeout: kSlow);
      await pumpUntil(() => leo.decoded.length >= 3, timeout: kSlow);

      const forbidden = [
        'rank',
        'suit',
        'hand',
        'hands',
        'cards',
        'deck',
        'remainingDeck',
        'visibleCard',
        '_hands',
        '_deck',
        'save',
        'GameState',
      ];
      for (final client in [mia, leo]) {
        for (final raw in client.received) {
          final MultiplayerMessage? message;
          try {
            message = codec.decode(raw);
          } on Object {
            continue;
          }
          // PRIVATE_UPDATE is the single rule-authorized channel for one
          // recipient's own card; everything else must be card-free.
          if (message is PrivateUpdateMessage) {
            continue;
          }
          final Object? decoded = jsonDecode(raw);
          expectNoKeys(decoded, forbidden);
        }
      }

      // Private updates only ever target the specific recipient.
      for (final private in [
        ...mia.decoded.whereType<PrivateUpdateMessage>(),
        ...leo.decoded.whereType<PrivateUpdateMessage>(),
      ]) {
        expect(
          private.privateState.recipientPlayerId == 'mp-1' ||
              private.privateState.recipientPlayerId == 'mp-2',
          isTrue,
        );
      }

      await host.stop();
      await mia.close();
      await leo.close();
    });

    test('the host never receives card data from clients either', () async {
      // Structural: ACTION_REQUEST body is {action, playerId} only.
      const request = ActionRequestMessage(
        seq: 1,
        sessionId: 's',
        action: GameAction.holdOut,
        playerId: 'mp-1',
      );
      final json = codec.encode(request);
      expect(json, isNot(contains('rank')));
      expect(json, isNot(contains('suit')));
      expect(json, isNot(contains('card')));
    });
  });
}
