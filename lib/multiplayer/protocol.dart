import 'private_state.dart';
import 'public_state.dart';

/// The protocol version this build speaks. The codec rejects any other value.
const int kProtocolVersion = 1;

/// The five authoritative gameplay actions a client may request.
///
/// Mirrors the `GameDriver` surface — never the rules themselves. Serialized
/// by [GameAction.name].
enum GameAction {
  revealCurrentPlayer,
  passToNextPlayer,
  holdOut,
  callYamada,
  startNextRound,
}

/// A strongly typed protocol message (see docs/multiplayer/m18-architecture.md
/// §10).
///
/// Every message carries the envelope fields — protocol [kProtocolVersion],
/// its [type], a per-sender monotonically increasing [seq], and the
/// [sessionId] — plus a typed [body]. Messages are immutable data only: no
/// gameplay logic, no state, and no authoritative-state reference live here.
///
/// Serialization is deterministic ([MessageCodec.encode] emits canonical
/// JSON) and deserialization is strict: unknown types, wrong versions,
/// malformed or missing fields, and unknown enum values are all rejected with
/// [MultiplayerProtocolException].
sealed class MultiplayerMessage {
  const MultiplayerMessage({required this.seq, required this.sessionId});

  /// The per-sender sequence number (idempotency + ordering).
  final int seq;

  /// The session this message belongs to.
  final String sessionId;

  /// The wire type name, e.g. `ACTION_REQUEST`.
  String get type;

  /// The typed body, serialized deterministically by the codec.
  Map<String, Object?> body();
}

/// Client asks the host for a seat (M18.1 §10 #2).
class JoinRequestMessage extends MultiplayerMessage {
  const JoinRequestMessage({
    required super.seq,
    required super.sessionId,
    required this.playerName,
  });

  final String playerName;

  @override
  String get type => 'JOIN_REQUEST';

  @override
  Map<String, Object?> body() => {'playerName': playerName};
}

/// Host grants a seat: the client's identity, its assigned color, and the
/// current roster (M18.1 §10 #3).
class JoinAcceptMessage extends MultiplayerMessage {
  const JoinAcceptMessage({
    required super.seq,
    required super.sessionId,
    required this.playerId,
    required this.color,
    required this.roster,
  });

  final String playerId;
  final int color;
  final List<PublicPlayer> roster;

  @override
  String get type => 'JOIN_ACCEPT';

  @override
  Map<String, Object?> body() => {
    'playerId': playerId,
    'color': color,
    'roster': [for (final p in roster) p.toJson()],
  };
}

/// Host refuses a seat (name taken / full / locked), M18.1 §10 #4.
class JoinRejectMessage extends MultiplayerMessage {
  const JoinRejectMessage({
    required super.seq,
    required super.sessionId,
    required this.reason,
  });

  final String reason;

  @override
  String get type => 'JOIN_REJECT';

  @override
  Map<String, Object?> body() => {'reason': reason};
}

/// Host broadcasts the roster (M18.1 §10 #5).
class RosterUpdateMessage extends MultiplayerMessage {
  const RosterUpdateMessage({
    required super.seq,
    required super.sessionId,
    required this.roster,
  });

  final List<PublicPlayer> roster;

  @override
  String get type => 'ROSTER_UPDATE';

  @override
  Map<String, Object?> body() => {
    'roster': [for (final p in roster) p.toJson()],
  };
}

/// Host tells everyone the game is starting (M18.1 §10 #6).
class GameStartMessage extends MultiplayerMessage {
  const GameStartMessage({
    required super.seq,
    required super.sessionId,
    required this.gameId,
    required this.publicState,
  });

  final String gameId;
  final PublicStateView publicState;

  @override
  String get type => 'GAME_START';

  @override
  Map<String, Object?> body() => {
    'gameId': gameId,
    'publicState': publicState.toJson(),
  };
}

/// Client proposes a gameplay action (M18.1 §10 #7).
class ActionRequestMessage extends MultiplayerMessage {
  const ActionRequestMessage({
    required super.seq,
    required super.sessionId,
    required this.action,
    required this.playerId,
  });

  final GameAction action;
  final String playerId;

  @override
  String get type => 'ACTION_REQUEST';

  @override
  Map<String, Object?> body() => {'action': action.name, 'playerId': playerId};
}

/// Host confirms the action and reports the new public state version
/// (M18.1 §10 #8). [requestSeq] echoes the client's sequence for correlation.
class ActionAcceptedMessage extends MultiplayerMessage {
  const ActionAcceptedMessage({
    required super.seq,
    required super.sessionId,
    required this.action,
    required this.requestSeq,
    required this.stateSeq,
  });

  final GameAction action;
  final int requestSeq;
  final int stateSeq;

  @override
  String get type => 'ACTION_ACCEPTED';

  @override
  Map<String, Object?> body() => {
    'action': action.name,
    'requestSeq': requestSeq,
    'stateSeq': stateSeq,
  };
}

/// Host rejects the action with the authoritative reason (M18.1 §10 #9).
class ActionRejectedMessage extends MultiplayerMessage {
  const ActionRejectedMessage({
    required super.seq,
    required super.sessionId,
    required this.action,
    required this.requestSeq,
    required this.reason,
  });

  final GameAction action;
  final int requestSeq;
  final String reason;

  @override
  String get type => 'ACTION_REJECTED';

  @override
  Map<String, Object?> body() => {
    'action': action.name,
    'requestSeq': requestSeq,
    'reason': reason,
  };
}

/// Host broadcasts the sanitized public state (M18.1 §10 #10).
class StateUpdateMessage extends MultiplayerMessage {
  const StateUpdateMessage({
    required super.seq,
    required super.sessionId,
    required this.stateSeq,
    required this.publicState,
  });

  final int stateSeq;
  final PublicStateView publicState;

  @override
  String get type => 'STATE_UPDATE';

  @override
  Map<String, Object?> body() => {
    'stateSeq': stateSeq,
    'publicState': publicState.toJson(),
  };
}

/// Host delivers exactly one rule-authorized card to exactly one player
/// (M18.1 §10 #11). The only private message in the protocol.
class PrivateUpdateMessage extends MultiplayerMessage {
  const PrivateUpdateMessage({
    required super.seq,
    required super.sessionId,
    required this.stateSeq,
    required this.privateState,
  });

  final int stateSeq;
  final PrivateStateView privateState;

  @override
  String get type => 'PRIVATE_UPDATE';

  @override
  Map<String, Object?> body() => {
    'stateSeq': stateSeq,
    'privateState': privateState.toJson(),
  };
}

/// Client asks the host to resend the current public state after a reconnect
/// or missed messages (M18.1 §10 #12).
class ResyncRequestMessage extends MultiplayerMessage {
  const ResyncRequestMessage({
    required super.seq,
    required super.sessionId,
    required this.playerId,
    required this.lastStateSeq,
  });

  final String playerId;
  final int lastStateSeq;

  @override
  String get type => 'RESYNC_REQUEST';

  @override
  Map<String, Object?> body() => {
    'playerId': playerId,
    'lastStateSeq': lastStateSeq,
  };
}

/// Host answers a resync with the full sanitized snapshot (M18.1 §10 #13).
class ResyncResponseMessage extends MultiplayerMessage {
  const ResyncResponseMessage({
    required super.seq,
    required super.sessionId,
    required this.stateSeq,
    required this.publicState,
  });

  final int stateSeq;
  final PublicStateView publicState;

  @override
  String get type => 'RESYNC_RESPONSE';

  @override
  Map<String, Object?> body() => {
    'stateSeq': stateSeq,
    'publicState': publicState.toJson(),
  };
}

/// Keepalive / liveness (M18.1 §10 #14).
class HeartbeatMessage extends MultiplayerMessage {
  const HeartbeatMessage({required super.seq, required super.sessionId});

  @override
  String get type => 'HEARTBEAT';

  @override
  Map<String, Object?> body() => const {};
}

/// Either side announces it is leaving (M18.1 §10 #15).
class DisconnectMessage extends MultiplayerMessage {
  const DisconnectMessage({
    required super.seq,
    required super.sessionId,
    required this.playerId,
    required this.reason,
  });

  final String playerId;
  final String reason;

  @override
  String get type => 'DISCONNECT';

  @override
  Map<String, Object?> body() => {'playerId': playerId, 'reason': reason};
}

/// Host terminates the session (M18.1 §10 #16).
class SessionEndMessage extends MultiplayerMessage {
  const SessionEndMessage({
    required super.seq,
    required super.sessionId,
    required this.reason,
  });

  final String reason;

  @override
  String get type => 'SESSION_END';

  @override
  Map<String, Object?> body() => {'reason': reason};
}
