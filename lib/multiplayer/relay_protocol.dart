import 'dart:convert';

import 'errors.dart';
import 'join_code.dart';
import 'json_util.dart';

/// The relay wire-protocol version.
const int kRelayProtocolVersion = 1;

/// The maximum size of one relay frame. Bounds the memory a misbehaving
/// device can force the relay (or a peer) to buffer.
const int kMaxRelayFrameBytes = 256 * 1024;

/// The relay member id assigned to a session's host.
const String kRelayHostMember = 'host';

/// The relay broadcast target inside a session: send to every other member.
const String kRelayBroadcastTarget = '*';

/// Whether [url] is a valid WebSocket relay URL (`ws:`/`wss:` scheme with a
/// non-empty host).
bool isValidRelayUrl(String url) {
  final trimmed = url.trim();
  if (!(trimmed.startsWith('ws://') || trimmed.startsWith('wss://'))) {
    return false;
  }
  try {
    final uri = Uri.parse(trimmed);
    return (uri.scheme == 'ws' || uri.scheme == 'wss') && uri.host.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// One relay frame.
///
/// The relay is deliberately a dumb frame router: `payload` fields are
/// **opaque** — the relay never parses game-protocol content, so the
/// existing privacy guarantees hold end-to-end. Only session membership and
/// routing metadata are interpreted here.
sealed class RelayFrame {
  const RelayFrame();

  /// The wire type tag (e.g. `HOST`, `JOIN`).
  String get type;

  /// The frame body (without the envelope `v`/`t` fields).
  Map<String, dynamic> body();

  /// Encodes this frame as canonical JSON.
  String encode() =>
      canonicalJson({'v': kRelayProtocolVersion, 't': type, ...body()});
}

// ---------------------------------------------------------------------------
// Device → relay
// ---------------------------------------------------------------------------

/// Host registers a new session (the host's WebSocket becomes the session's
/// host endpoint). Carries the 6-digit join code so clients can resolve a
/// typed code to this session, and the player limit so the relay can reject
/// over-full sessions before they reach the host.
class RelayHostFrame extends RelayFrame {
  const RelayHostFrame({
    required this.sessionId,
    required this.joinCode,
    required this.displayName,
    this.maxPlayers = 10,
  });

  final String sessionId;
  final String joinCode;
  final String displayName;
  final int maxPlayers;

  @override
  String get type => 'HOST';

  @override
  Map<String, dynamic> body() => {
    'sid': sessionId,
    'code': joinCode,
    'name': displayName,
    'max': maxPlayers,
  };
}

/// Client asks the relay to resolve a typed 6-digit code to a session.
class RelayLookupFrame extends RelayFrame {
  const RelayLookupFrame({required this.joinCode});

  final String joinCode;

  @override
  String get type => 'LOOKUP';

  @override
  Map<String, dynamic> body() => {'code': joinCode};
}

/// Client joins an existing session by its id (the QR path).
class RelayJoinFrame extends RelayFrame {
  const RelayJoinFrame({required this.sessionId});

  final String sessionId;

  @override
  String get type => 'JOIN';

  @override
  Map<String, dynamic> body() => {'sid': sessionId};
}

/// Routes one opaque game-protocol frame. [to] is `*` (every member except
/// the sender), `host` (the session host), or a member id.
class RelaySendFrame extends RelayFrame {
  const RelaySendFrame({
    required this.sessionId,
    required this.to,
    required this.payload,
  });

  final String sessionId;
  final String to;
  final String payload;

  @override
  String get type => 'SEND';

  @override
  Map<String, dynamic> body() => {
    'sid': sessionId,
    'to': to,
    'payload': payload,
  };
}

/// Host asks the relay to drop a member (host-initiated disconnect).
class RelayKickFrame extends RelayFrame {
  const RelayKickFrame({required this.sessionId, required this.member});

  final String sessionId;
  final String member;

  @override
  String get type => 'KICK';

  @override
  Map<String, dynamic> body() => {'sid': sessionId, 'member': member};
}

/// Device detaches from its session cleanly (the WebSocket may also simply
/// close; LEAVE is the polite form).
class RelayLeaveFrame extends RelayFrame {
  const RelayLeaveFrame();

  @override
  String get type => 'LEAVE';

  @override
  Map<String, dynamic> body() => const {};
}

// ---------------------------------------------------------------------------
// Relay → device
// ---------------------------------------------------------------------------

/// The host's session was created; [member] is the host's member id.
class RelayRegisteredFrame extends RelayFrame {
  const RelayRegisteredFrame({required this.sessionId, required this.member});

  final String sessionId;
  final String member;

  @override
  String get type => 'REGISTERED';

  @override
  Map<String, dynamic> body() => {'sid': sessionId, 'member': member};
}

/// A code lookup succeeded.
class RelayLookupAckFrame extends RelayFrame {
  const RelayLookupAckFrame({
    required this.sessionId,
    required this.displayName,
  });

  final String sessionId;
  final String displayName;

  @override
  String get type => 'LOOKUP_ACK';

  @override
  Map<String, dynamic> body() => {'sid': sessionId, 'name': displayName};
}

/// A code lookup failed (no session advertises that code).
class RelayLookupErrFrame extends RelayFrame {
  const RelayLookupErrFrame({required this.reason});

  final String reason;

  @override
  String get type => 'LOOKUP_ERR';

  @override
  Map<String, dynamic> body() => {'reason': reason};
}

/// A join succeeded; [member] is the relay member id used for routing.
class RelayJoinAckFrame extends RelayFrame {
  const RelayJoinAckFrame({required this.sessionId, required this.member});

  final String sessionId;
  final String member;

  @override
  String get type => 'JOIN_ACK';

  @override
  Map<String, dynamic> body() => {'sid': sessionId, 'member': member};
}

/// A join failed. Reasons are coarse, relay-level guards only: the host
/// performs the authoritative join validation afterwards via the game
/// protocol (name taken, game started, etc.).
class RelayJoinErrFrame extends RelayFrame {
  const RelayJoinErrFrame({required this.reason});

  final String reason;

  @override
  String get type => 'JOIN_ERR';

  @override
  Map<String, dynamic> body() => {'reason': reason};
}

/// Delivers one opaque frame from member [from].
class RelayPeerFrame extends RelayFrame {
  const RelayPeerFrame({
    required this.sessionId,
    required this.from,
    required this.payload,
  });

  final String sessionId;
  final String from;
  final String payload;

  @override
  String get type => 'PEER';

  @override
  Map<String, dynamic> body() => {
    'sid': sessionId,
    'from': from,
    'payload': payload,
  };
}

/// A new member connected to the host's session (relay member id [member]).
class RelayPeerJoinedFrame extends RelayFrame {
  const RelayPeerJoinedFrame({required this.sessionId, required this.member});

  final String sessionId;
  final String member;

  @override
  String get type => 'PEER_JOINED';

  @override
  Map<String, dynamic> body() => {'sid': sessionId, 'member': member};
}

/// A member left the host's session (left / kicked / connection lost).
class RelayPeerLeftFrame extends RelayFrame {
  const RelayPeerLeftFrame({
    required this.sessionId,
    required this.member,
    required this.reason,
  });

  final String sessionId;
  final String member;
  final String reason;

  @override
  String get type => 'PEER_LEFT';

  @override
  Map<String, dynamic> body() => {
    'sid': sessionId,
    'member': member,
    'reason': reason,
  };
}

/// A protocol-level error (wrong session, not a member, malformed frame).
class RelayErrFrame extends RelayFrame {
  const RelayErrFrame({required this.reason});

  final String reason;

  @override
  String get type => 'ERR';

  @override
  Map<String, dynamic> body() => {'reason': reason};
}

/// Strictly decodes one relay frame.
///
/// Throws [MultiplayerProtocolException] (never crashes) for malformed JSON,
/// an unknown version, an unknown frame type, or structurally invalid
/// fields. A rejected frame is dropped by the relay and must never take the
/// server or a peer down.
RelayFrame decodeRelayFrame(String raw) {
  if (raw.length > kMaxRelayFrameBytes) {
    throw MultiplayerProtocolException('relay frame too large');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    throw MultiplayerProtocolException(
      'malformed relay JSON: ${error.message}',
    );
  }
  final root = requireMap(decoded, 'relay frame root');
  final version = requireInt(root['v'], 'relay frame version');
  if (version != kRelayProtocolVersion) {
    throw MultiplayerProtocolException(
      'unsupported relay version $version (expected $kRelayProtocolVersion)',
    );
  }
  final type = requireString(root['t'], 'relay frame type');
  final f = root;

  String requireSessionId() {
    final sid = requireString(f['sid'], 'relay sessionId');
    if (sid.isEmpty) {
      throw MultiplayerProtocolException('relay sessionId must not be empty');
    }
    return sid;
  }

  String requireCode() {
    final code = requireString(f['code'], 'relay join code');
    if (!isValidJoinCode(code)) {
      throw MultiplayerProtocolException('invalid relay join code');
    }
    return code;
  }

  return switch (type) {
    'HOST' => RelayHostFrame(
      sessionId: requireSessionId(),
      joinCode: requireCode(),
      displayName: requireString(f['name'], 'relay display name'),
      maxPlayers: requireInt(f['max'], 'relay max players'),
    ),
    'LOOKUP' => RelayLookupFrame(joinCode: requireCode()),
    'JOIN' => RelayJoinFrame(sessionId: requireSessionId()),
    'SEND' => RelaySendFrame(
      sessionId: requireSessionId(),
      to: requireString(f['to'], 'relay target'),
      payload: requireString(f['payload'], 'relay payload'),
    ),
    'KICK' => RelayKickFrame(
      sessionId: requireSessionId(),
      member: requireString(f['member'], 'relay member'),
    ),
    'LEAVE' => const RelayLeaveFrame(),
    'REGISTERED' => RelayRegisteredFrame(
      sessionId: requireSessionId(),
      member: requireString(f['member'], 'relay member'),
    ),
    'LOOKUP_ACK' => RelayLookupAckFrame(
      sessionId: requireSessionId(),
      displayName: requireString(f['name'], 'relay display name'),
    ),
    'LOOKUP_ERR' => RelayLookupErrFrame(
      reason: requireString(f['reason'], 'relay lookup reason'),
    ),
    'JOIN_ACK' => RelayJoinAckFrame(
      sessionId: requireSessionId(),
      member: requireString(f['member'], 'relay member'),
    ),
    'JOIN_ERR' => RelayJoinErrFrame(
      reason: requireString(f['reason'], 'relay join reason'),
    ),
    'PEER' => RelayPeerFrame(
      sessionId: requireSessionId(),
      from: requireString(f['from'], 'relay sender'),
      payload: requireString(f['payload'], 'relay payload'),
    ),
    'PEER_JOINED' => RelayPeerJoinedFrame(
      sessionId: requireSessionId(),
      member: requireString(f['member'], 'relay member'),
    ),
    'PEER_LEFT' => RelayPeerLeftFrame(
      sessionId: requireSessionId(),
      member: requireString(f['member'], 'relay member'),
      reason: requireString(f['reason'], 'relay leave reason'),
    ),
    'ERR' => RelayErrFrame(
      reason: requireString(f['reason'], 'relay error reason'),
    ),
    _ => throw MultiplayerProtocolException('unknown relay frame type "$type"'),
  };
}
