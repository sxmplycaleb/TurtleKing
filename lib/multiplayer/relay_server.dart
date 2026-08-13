import 'dart:async';
import 'dart:io';

import 'errors.dart';
import 'relay_protocol.dart';

/// One session on the relay: the host's WebSocket plus the connected member
/// WebSockets, with routing metadata.
///
/// The relay stores **no game data** — only routing state (session id, the
/// human join code, a display name, the player limit, and live sockets).
/// Everything else (game-protocol frames) is opaque and forwarded verbatim.
class _RelaySession {
  _RelaySession({
    required this.id,
    required this.code,
    required this.name,
    required this.maxPlayers,
    required this.host,
  });

  final String id;
  final String code;
  final String name;
  final int maxPlayers;
  final WebSocket host;

  /// Relay member id → live member socket (the host is never in this map).
  final Map<String, WebSocket> members = {};

  DateTime lastActivity = DateTime.now();
  int _nextMember = 1;

  String nextMemberId() => 'm${_nextMember++}';

  bool get isFull => members.length >= maxPlayers - 1;

  void touch() => lastActivity = DateTime.now();
}

/// The state of one device connection to the relay.
class _RelayConnection {
  _RelayConnection(this.ws);

  final WebSocket ws;

  /// The session this connection is bound to, once it registers/joins.
  String? sessionId;

  /// The member id within that session ('host' for the host).
  String? member;

  bool get isBound => sessionId != null;
}

/// A minimal, dumb WebSocket relay that lets two or more devices play
/// together over the internet.
///
/// **Why a relay:** a phone on a private network cannot accept inbound TCP
/// connections from another network (no port forwarding, CGNAT, etc.). The
/// relay inverts the model — every device opens one **outbound** WebSocket
/// to a reachable server, so any mix of Wi-Fi/mobile-data networks works.
///
/// **What the relay does:** the host registers a session (id + 6-digit
/// code + player limit); clients join by session id (QR) or resolve a code
/// (typed entry); the relay then routes opaque frames between members
/// (broadcast to the host, or unicast by member id) and reports peer
/// join/leave so the host's session layer can mirror per-client connections.
///
/// **What the relay never does:** it never parses game-protocol payloads,
/// never stores game state, and never sees cards/hands/deck/save data — the
/// frames it forwards are already the sanitized public state and
/// recipient-specific private cards, and the session/authority/privacy
/// rules all still live on the host.
///
/// Pure `dart:io` — no packages — so the same file runs inside tests
/// (in-process, loopback) and as a standalone server (`dart run
/// tool/relay_server_main.dart`).
class RelayServer {
  RelayServer({
    this.sessionTtl = const Duration(minutes: 30),
    this.maxSessions = 64,
    this.sweepInterval = const Duration(seconds: 30),
    this.onLog,
  });

  /// Sessions are removed after this long without any activity.
  final Duration sessionTtl;

  /// Hard cap on concurrent sessions (bounds memory on a small host).
  final int maxSessions;

  final Duration sweepInterval;

  /// Optional lifecycle logger (wired to stdout by the standalone runner).
  ///
  /// Emits **routing metadata only** — connection open/close, session
  /// register/close, member join/leave. Never the join code, never any
  /// game-protocol payload, never card/private-state content: the relay
  /// cannot log what it never inspects. Null disables logging entirely
  /// (tests stay silent).
  final void Function(String message)? onLog;

  HttpServer? _server;
  final Map<String, _RelaySession> _sessions = {};
  final Map<WebSocket, _RelayConnection> _connections = {};
  Timer? _sweepTimer;
  bool _stopped = false;

  void _log(String message) {
    onLog?.call(message);
  }

  /// The bound port (valid after [start]; useful for ephemeral port 0).
  int? get port => _server?.port;

  /// Number of live sessions (tests).
  int get sessionCount => _sessions.length;

  /// Starts the relay. Binds [port] (0 → ephemeral) and returns the port.
  Future<int> start({int port = 0, InternetAddress? address}) async {
    _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen(_onHttpRequest);
    _sweepTimer = Timer.periodic(sweepInterval, (_) => _sweep());
    return _server!.port;
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    for (final session in List.of(_sessions.values)) {
      _closeSession(session, reason: 'relay stopped');
    }
    _sessions.clear();
    for (final connection in List.of(_connections.values)) {
      _safeClose(connection.ws);
    }
    _connections.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _onHttpRequest(HttpRequest request) async {
    // Ops liveness probe for container platforms (Render, etc.): a static
    // body that leaks nothing — no sessions, join codes, players, or game
    // data. Everything else non-WebSocket keeps the 426 rejection below.
    if (request.method == 'GET' && request.uri.path == '/health') {
      final response = request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json;
      response.write('{"status":"ok"}');
      await response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.upgradeRequired;
      await request.response.close();
      return;
    }
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      return;
    }
    final peer = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    _handleSocket(ws, peer);
  }

  void _handleSocket(WebSocket ws, String peer) {
    final connection = _RelayConnection(ws);
    _connections[ws] = connection;
    _log('connect $peer');
    ws.listen(
      (data) => _onFrame(connection, data),
      onError: (_) => _drop(connection, reason: 'disconnected'),
      onDone: () => _drop(connection, reason: 'disconnected'),
      cancelOnError: true,
    );
  }

  void _onFrame(_RelayConnection connection, Object? data) {
    if (data is! String) return; // binary frames are ignored
    final RelayFrame frame;
    try {
      frame = decodeRelayFrame(data);
    } on MultiplayerProtocolException catch (error) {
      _send(connection.ws, RelayErrFrame(reason: error.reason));
      return;
    }
    try {
      switch (frame) {
        case RelayHostFrame(
          :final sessionId,
          :final joinCode,
          :final displayName,
          :final maxPlayers,
        ):
          _onHost(connection, sessionId, joinCode, displayName, maxPlayers);
        case RelayLookupFrame(:final joinCode):
          _onLookup(connection, joinCode);
        case RelayJoinFrame(:final sessionId):
          _onJoin(connection, sessionId);
        case RelaySendFrame(:final sessionId, :final to, :final payload):
          _onSend(connection, sessionId, to, payload);
        case RelayKickFrame(:final sessionId, :final member):
          _onKick(connection, sessionId, member);
        case RelayLeaveFrame():
          _onLeave(connection);
        default:
          _send(connection.ws, const RelayErrFrame(reason: 'not allowed'));
      }
    } catch (_) {
      // A handler must never take the relay down.
      _send(connection.ws, const RelayErrFrame(reason: 'internal error'));
    }
  }

  void _onHost(
    _RelayConnection connection,
    String sessionId,
    String joinCode,
    String displayName,
    int maxPlayers,
  ) {
    if (connection.isBound) {
      _send(connection.ws, const RelayErrFrame(reason: 'already bound'));
      return;
    }
    if (maxPlayers < 2 || maxPlayers > 50) {
      _send(connection.ws, const RelayErrFrame(reason: 'invalid player limit'));
      return;
    }
    if (_sessions.length >= maxSessions) {
      _send(connection.ws, const RelayErrFrame(reason: 'relay is full'));
      return;
    }
    final existing = _sessions[sessionId];
    if (existing != null) {
      _send(
        connection.ws,
        const RelayErrFrame(reason: 'session already hosted'),
      );
      return;
    }
    final session = _RelaySession(
      id: sessionId,
      code: joinCode,
      name: displayName,
      maxPlayers: maxPlayers,
      host: connection.ws,
    );
    _sessions[sessionId] = session;
    connection.sessionId = sessionId;
    connection.member = kRelayHostMember;
    // Routing metadata only: no join code, no display name, no payload.
    _log('session $sessionId registered');
    _send(
      connection.ws,
      RelayRegisteredFrame(sessionId: sessionId, member: kRelayHostMember),
    );
  }

  void _onLookup(_RelayConnection connection, String joinCode) {
    for (final session in _sessions.values) {
      if (session.code == joinCode) {
        _send(
          connection.ws,
          RelayLookupAckFrame(sessionId: session.id, displayName: session.name),
        );
        return;
      }
    }
    _send(
      connection.ws,
      const RelayLookupErrFrame(reason: 'no game found with this code'),
    );
  }

  void _onJoin(_RelayConnection connection, String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      _send(connection.ws, const RelayJoinErrFrame(reason: 'no such session'));
      return;
    }
    final hostState = session.host.readyState;
    if (hostState == WebSocket.closing || hostState == WebSocket.closed) {
      _send(
        connection.ws,
        const RelayJoinErrFrame(reason: 'host not connected'),
      );
      return;
    }
    if (session.isFull) {
      _send(connection.ws, const RelayJoinErrFrame(reason: 'session full'));
      return;
    }
    if (connection.isBound) {
      _send(
        connection.ws,
        const RelayJoinErrFrame(reason: 'already in session'),
      );
      return;
    }
    final member = session.nextMemberId();
    session.members[member] = connection.ws;
    session.touch();
    connection.sessionId = sessionId;
    connection.member = member;
    _log('member $member joined $sessionId');
    _send(
      connection.ws,
      RelayJoinAckFrame(sessionId: sessionId, member: member),
    );
    _send(
      session.host,
      RelayPeerJoinedFrame(sessionId: sessionId, member: member),
    );
  }

  void _onSend(
    _RelayConnection connection,
    String sessionId,
    String to,
    String payload,
  ) {
    final session = _sessions[sessionId];
    if (session == null ||
        connection.sessionId != sessionId ||
        connection.member == null) {
      _send(connection.ws, const RelayErrFrame(reason: 'not in session'));
      return;
    }
    session.touch();
    final from = connection.member!;
    switch (to) {
      case kRelayBroadcastTarget:
        // Every member except the sender.
        for (final entry in session.members.entries) {
          if (entry.key != from) {
            _send(
              entry.value,
              RelayPeerFrame(
                sessionId: sessionId,
                from: from,
                payload: payload,
              ),
            );
          }
        }
        if (from != kRelayHostMember) {
          _send(
            session.host,
            RelayPeerFrame(sessionId: sessionId, from: from, payload: payload),
          );
        }
      case kRelayHostMember:
        if (from == kRelayHostMember) {
          _send(
            connection.ws,
            const RelayErrFrame(reason: 'cannot target self'),
          );
          return;
        }
        _send(
          session.host,
          RelayPeerFrame(sessionId: sessionId, from: from, payload: payload),
        );
      default:
        final target = session.members[to];
        if (target == null) {
          _send(connection.ws, const RelayErrFrame(reason: 'unknown target'));
          return;
        }
        _send(
          target,
          RelayPeerFrame(sessionId: sessionId, from: from, payload: payload),
        );
    }
  }

  void _onKick(_RelayConnection connection, String sessionId, String member) {
    final session = _sessions[sessionId];
    if (session == null ||
        connection.sessionId != sessionId ||
        connection.member != kRelayHostMember) {
      _send(connection.ws, const RelayErrFrame(reason: 'not allowed'));
      return;
    }
    final target = session.members.remove(member);
    if (target == null) {
      _send(connection.ws, const RelayErrFrame(reason: 'unknown member'));
      return;
    }
    session.touch();
    final targetConnection = _connections[target];
    if (targetConnection != null) {
      _drop(targetConnection, reason: 'kicked');
      // A kicked member's socket is still open — close it so the client sees
      // the session is over instead of waiting on a silent connection.
      _safeClose(target);
    }
  }

  void _onLeave(_RelayConnection connection) {
    if (!connection.isBound) return;
    final session = _sessions[connection.sessionId];
    final member = connection.member;
    connection.sessionId = null;
    connection.member = null;
    if (session == null) return;
    if (member == kRelayHostMember) {
      _closeSession(session, reason: 'host left');
      return;
    }
    if (member != null) {
      session.members.remove(member);
      session.touch();
      _log('member $member left ${session.id} (left)');
      _send(
        session.host,
        RelayPeerLeftFrame(
          sessionId: session.id,
          member: member,
          reason: 'left',
        ),
      );
    }
  }

  /// Removes a connection that closed or errored, notifying the host.
  void _drop(_RelayConnection connection, {required String reason}) {
    final sessionId = connection.sessionId;
    final member = connection.member;
    final wasHost = member == kRelayHostMember;
    connection.sessionId = null;
    connection.member = null;
    _connections.remove(connection.ws);
    if (sessionId == null) return;
    final session = _sessions[sessionId];
    if (session == null) return;
    if (wasHost) {
      // Host loss: the session is over for everyone.
      _closeSession(session, reason: 'host disconnected');
      return;
    }
    if (member != null) {
      session.members.remove(member);
      session.touch();
      _log('member $member left $sessionId ($reason)');
      _send(
        session.host,
        RelayPeerLeftFrame(
          sessionId: sessionId,
          member: member,
          reason: reason,
        ),
      );
    }
  }

  void _closeSession(_RelaySession session, {required String reason}) {
    _sessions.remove(session.id);
    _log('session ${session.id} closed ($reason)');
    for (final ws in session.members.values) {
      _send(ws, RelayErrFrame(reason: reason));
      _safeClose(ws);
    }
    session.members.clear();
    _safeClose(session.host);
  }

  void _sweep() {
    final now = DateTime.now();
    for (final session in List.of(_sessions.values)) {
      if (now.difference(session.lastActivity) > sessionTtl) {
        _closeSession(session, reason: 'session expired');
      }
    }
  }

  /// Number of live device connections (tests/ops).
  int get connectionCount => _connections.length;

  void _send(WebSocket ws, RelayFrame frame) {
    try {
      ws.add(frame.encode());
    } catch (_) {
      // A dead socket is cleaned up by its close handler.
    }
  }

  void _safeClose(WebSocket ws) {
    try {
      ws.close();
    } catch (_) {}
  }
}
