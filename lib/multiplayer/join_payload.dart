import 'dart:convert';

import 'errors.dart';
import 'join_code.dart';
import 'json_util.dart';
import 'relay_protocol.dart';

/// The QR join payload protocol version.
const int kJoinPayloadVersion = 2;

/// The QR payload message type name.
const String kJoinPayloadType = 'TKJOIN';

/// The connection information needed to join an internet multiplayer
/// session, as encoded in the host's QR code.
///
/// This is a **locator only** — it deliberately contains nothing private:
///
/// * no `GameState`, cards, ranks, suits, hands, or deck data;
/// * no save documents, history, or player identity;
/// * no LAN IP address or port (v1 carried the host's local IPv4, which is
///   only reachable on the same Wi-Fi network).
///
/// The three fields are exactly what a client needs to reach the session
/// through the internet relay: the session identifier, the relay endpoint,
/// and the 6-digit join code (for humans who prefer to type it — see
/// [join_code.dart]).
class JoinPayload {
  const JoinPayload({
    required this.sessionId,
    required this.joinCode,
    required this.relayUrl,
  });

  /// Parses and strictly validates a QR payload string.
  ///
  /// Returns null (never throws) for malformed JSON, an unknown version, a
  /// wrong message type, an empty session id, an invalid join code, or an
  /// invalid relay endpoint.
  static JoinPayload? parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    try {
      final map = requireMap(decoded, 'join payload');
      final version = requireInt(map['v'], 'join payload version');
      if (version != kJoinPayloadVersion) return null;
      if (requireString(map['t'], 'join payload type') != kJoinPayloadType) {
        return null;
      }
      final sessionId = requireString(map['sid'], 'join payload sessionId');
      if (sessionId.isEmpty) return null;
      final code = requireString(map['code'], 'join payload code');
      if (!isValidJoinCode(code)) return null;
      final relay = requireString(map['relay'], 'join payload relay');
      if (!isValidRelayUrl(relay)) return null;
      return JoinPayload(sessionId: sessionId, joinCode: code, relayUrl: relay);
    } on MultiplayerProtocolException {
      return null;
    }
  }

  final String sessionId;

  /// The 6-digit human-friendly join code (a locator, never a credential).
  final String joinCode;

  /// The internet relay endpoint (`ws://` / `wss://`) the host registered
  /// this session on. Clients connect here instead of to a LAN address.
  final String relayUrl;

  /// Encodes this payload as canonical JSON for the QR code.
  String encode() => canonicalJson({
    'v': kJoinPayloadVersion,
    't': kJoinPayloadType,
    'sid': sessionId,
    'code': joinCode,
    'relay': relayUrl,
  });
}
