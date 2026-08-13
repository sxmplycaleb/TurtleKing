import 'dart:convert';

import 'errors.dart';
import 'json_util.dart';
import 'private_state.dart';
import 'protocol.dart';
import 'public_state.dart';

/// Encodes and decodes [MultiplayerMessage]s over JSON.
///
/// * **Deterministic**: [encode] emits canonical JSON (sorted keys), so equal
///   messages always produce byte-identical output.
/// * **Strict**: [decode] rejects malformed JSON, unknown message types, the
///   wrong protocol version, missing/invalid session ids, bad sequence
///   numbers, and unknown enum values — always via
///   [MultiplayerProtocolException], never by crashing or guessing.
/// * **Typed**: the public API only ever accepts or returns typed
///   [MultiplayerMessage] objects. There is no generic "raw body" escape
///   hatch, so an authoritative state or save document cannot accidentally
///   be serialized through this codec.
class MessageCodec {
  const MessageCodec();

  /// Encodes [message] as canonical JSON.
  String encode(MultiplayerMessage message) {
    return canonicalJson({
      'v': kProtocolVersion,
      'type': message.type,
      'seq': message.seq,
      'sessionId': message.sessionId,
      'body': message.body(),
    });
  }

  /// Strictly decodes [raw] into the matching typed message.
  ///
  /// Throws [MultiplayerProtocolException] for anything malformed; never
  /// returns a partial or misinterpreted message.
  MultiplayerMessage decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw MultiplayerProtocolException('malformed JSON: ${error.message}');
    }
    final root = requireMap(decoded, 'message root');

    final version = requireInt(root['v'], 'message version');
    if (version != kProtocolVersion) {
      throw MultiplayerProtocolException(
        'unsupported protocol version $version (expected $kProtocolVersion)',
      );
    }

    final seq = requireInt(root['seq'], 'message seq');
    if (seq < 0) {
      throw MultiplayerProtocolException('message seq must be >= 0');
    }

    final sessionId = requireString(root['sessionId'], 'message sessionId');
    if (sessionId.isEmpty) {
      throw MultiplayerProtocolException('message sessionId must not be empty');
    }

    final type = requireString(root['type'], 'message type');
    final body = requireMap(root['body'], 'message body');

    return switch (type) {
      'JOIN_REQUEST' => JoinRequestMessage(
        seq: seq,
        sessionId: sessionId,
        playerName: requireString(body['playerName'], 'playerName'),
      ),
      'JOIN_ACCEPT' => JoinAcceptMessage(
        seq: seq,
        sessionId: sessionId,
        playerId: requireString(body['playerId'], 'playerId'),
        color: requireInt(body['color'], 'color'),
        roster: [
          for (final p in requireList(body['roster'], 'roster'))
            PublicPlayer.fromJson(p),
        ],
      ),
      'JOIN_REJECT' => JoinRejectMessage(
        seq: seq,
        sessionId: sessionId,
        reason: requireString(body['reason'], 'reason'),
      ),
      'ROSTER_UPDATE' => RosterUpdateMessage(
        seq: seq,
        sessionId: sessionId,
        roster: [
          for (final p in requireList(body['roster'], 'roster'))
            PublicPlayer.fromJson(p),
        ],
      ),
      'GAME_START' => GameStartMessage(
        seq: seq,
        sessionId: sessionId,
        gameId: requireString(body['gameId'], 'gameId'),
        publicState: PublicStateView.fromJson(body['publicState']),
      ),
      'ACTION_REQUEST' => ActionRequestMessage(
        seq: seq,
        sessionId: sessionId,
        action: requireEnum(GameAction.values, body['action'], 'action'),
        playerId: requireString(body['playerId'], 'playerId'),
      ),
      'ACTION_ACCEPTED' => ActionAcceptedMessage(
        seq: seq,
        sessionId: sessionId,
        action: requireEnum(GameAction.values, body['action'], 'action'),
        requestSeq: requireInt(body['requestSeq'], 'requestSeq'),
        stateSeq: requireInt(body['stateSeq'], 'stateSeq'),
      ),
      'ACTION_REJECTED' => ActionRejectedMessage(
        seq: seq,
        sessionId: sessionId,
        action: requireEnum(GameAction.values, body['action'], 'action'),
        requestSeq: requireInt(body['requestSeq'], 'requestSeq'),
        reason: requireString(body['reason'], 'reason'),
      ),
      'STATE_UPDATE' => StateUpdateMessage(
        seq: seq,
        sessionId: sessionId,
        stateSeq: requireInt(body['stateSeq'], 'stateSeq'),
        publicState: PublicStateView.fromJson(body['publicState']),
      ),
      'PRIVATE_UPDATE' => PrivateUpdateMessage(
        seq: seq,
        sessionId: sessionId,
        stateSeq: requireInt(body['stateSeq'], 'stateSeq'),
        privateState: PrivateStateView.fromJson(body['privateState']),
      ),
      'RESYNC_REQUEST' => ResyncRequestMessage(
        seq: seq,
        sessionId: sessionId,
        playerId: requireString(body['playerId'], 'playerId'),
        lastStateSeq: requireInt(body['lastStateSeq'], 'lastStateSeq'),
      ),
      'RESYNC_RESPONSE' => ResyncResponseMessage(
        seq: seq,
        sessionId: sessionId,
        stateSeq: requireInt(body['stateSeq'], 'stateSeq'),
        publicState: PublicStateView.fromJson(body['publicState']),
      ),
      'HEARTBEAT' => HeartbeatMessage(seq: seq, sessionId: sessionId),
      'DISCONNECT' => DisconnectMessage(
        seq: seq,
        sessionId: sessionId,
        playerId: requireString(body['playerId'], 'playerId'),
        reason: requireString(body['reason'], 'reason'),
      ),
      'SESSION_END' => SessionEndMessage(
        seq: seq,
        sessionId: sessionId,
        reason: requireString(body['reason'], 'reason'),
      ),
      _ => throw MultiplayerProtocolException('unknown message type "$type"'),
    };
  }
}
