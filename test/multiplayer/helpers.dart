import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/relay_protocol.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

/// Builds a player with a stable id/name/color from [PlayerColors.palette].
Player testPlayer(int index, {String? id, String? name}) => Player(
  id: id ?? 'p$index',
  name: name ?? 'Player $index',
  color: PlayerColors.palette[index % PlayerColors.palette.length],
);

/// Builds a fresh game with [count] players and a deterministic seed.
GameState testGame(int count, {int seed = 7}) {
  return GameState(
    players: [for (var i = 0; i < count; i++) testPlayer(i)],
    random: Random(seed),
  );
}

/// Drives [game] through the entire private viewing phase so that pouring
/// begins (all players have revealed and passed).
GameState viewThrough(GameState game) {
  while (!game.allPlayersViewed && !game.pouringStarted) {
    if (!game.currentPlayerRevealed) {
      game.revealCurrentPlayer();
    } else {
      game.passToNextPlayer();
    }
  }
  return game;
}

/// Recursively asserts that [node] (a decoded JSON value) contains none of
/// [forbidden] as map keys.
void expectNoForbiddenKeys(Object? node, List<String> forbidden) {
  if (node is Map) {
    for (final key in node.keys) {
      expect(
        forbidden,
        isNot(contains(key)),
        reason: 'forbidden key "$key" appeared in public payload',
      );
      expectNoForbiddenKeys(node[key], forbidden);
    }
  } else if (node is List) {
    for (final item in node) {
      expectNoForbiddenKeys(item, forbidden);
    }
  }
}

/// A raw WebSocket peer for driving the relay protocol directly (no session
/// layer involved — relay-level tests target the relay itself).
///
/// Automatically answers the relay's heartbeat ([RelayPingFrame]) with a
/// pong so a live peer is never mistaken for a dead one; pass
/// `respondToPings: false` to simulate a peer that goes silent (which the
/// relay's heartbeat then reaps). Ping/pong frames never surface through
/// [exchange] or [received].
class RelayTestPeer {
  RelayTestPeer(this.ws);

  final WebSocket ws;
  final List<RelayFrame> received = [];
  final List<Completer<RelayFrame>> _pending = [];
  StreamSubscription<dynamic>? _sub;
  bool closed = false;

  static Future<RelayTestPeer> connect(
    String url, {
    bool respondToPings = true,
  }) async {
    final peer = RelayTestPeer(await WebSocket.connect(url));
    peer._sub = peer.ws.listen(
      (data) {
        if (data is! String) return;
        final frame = decodeRelayFrame(data);
        if (frame is RelayPingFrame) {
          if (respondToPings) {
            try {
              peer.ws.add(const RelayPongFrame().encode());
            } catch (_) {}
          }
          return;
        }
        if (peer._pending.isNotEmpty) {
          peer._pending.removeAt(0).complete(frame);
        } else {
          peer.received.add(frame);
        }
      },
      onError: (_) => peer.closed = true,
      onDone: () => peer.closed = true,
    );
    return peer;
  }

  /// Sends [frame] and returns the next relay frame from the relay
  /// (strict request/response for handshakes).
  Future<RelayFrame> exchange(
    RelayFrame frame, {
    Duration timeout = const Duration(seconds: 4),
  }) {
    final completer = Completer<RelayFrame>();
    _pending.add(completer);
    ws.add(frame.encode());
    return completer.future.timeout(timeout);
  }

  Future<void> close() async {
    try {
      await ws.close();
    } catch (_) {}
    await _sub?.cancel();
  }
}
