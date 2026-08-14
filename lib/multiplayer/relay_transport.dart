import 'dart:async';
import 'dart:io';

import '../player_colors.dart';
import 'errors.dart';
import 'relay_protocol.dart';
import 'transport.dart';

/// Thrown when the relay refuses a join/registration (no such session,
/// session full, host not connected, session already hosted, …). Carries a
/// user-facing-ish reason; the session layer maps it to a typed
/// [JoinResult].
class RelayJoinException implements Exception {
  const RelayJoinException(this.reason);

  final String reason;

  @override
  String toString() => 'RelayJoinException: $reason';
}

/// The outcome of resolving a typed 6-digit code against the relay (the
/// internet replacement for the old UDP-beacon code resolution).
sealed class RelayLookupResult {
  const RelayLookupResult();
}

/// The code resolved to a live session.
class RelayLookupFound extends RelayLookupResult {
  const RelayLookupFound({required this.sessionId, required this.displayName});

  final String sessionId;
  final String displayName;
}

/// No session advertises that code (wrong code, or the host is not on the
/// relay right now).
class RelayLookupNotFound extends RelayLookupResult {
  const RelayLookupNotFound();
}

/// The relay itself could not be reached or misbehaved.
class RelayLookupUnavailable extends RelayLookupResult {
  const RelayLookupUnavailable([this.reason]);

  final String? reason;
}

/// Low-level WebSocket wrapper used by both sides of the relay.
///
/// Handles the strict request/response handshakes (HOST→REGISTERED,
/// JOIN→JOIN_ACK, LOOKUP→LOOKUP_ACK) and then routes the asynchronous
/// frames (PEER / PEER_JOINED / PEER_LEFT / ERR) to the [frames] stream.
///
/// This is an internal building block of the relay transport — not part of
/// the app-facing API.
class RelaySocket {
  RelaySocket(this.ws);

  final WebSocket ws;
  final StreamController<RelayFrame> _frames =
      StreamController<RelayFrame>.broadcast();
  final List<Completer<RelayFrame>> _exchanges = [];
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;

  Stream<RelayFrame> get frames => _frames.stream;

  bool get isOpen => !_closed && ws.readyState == WebSocket.open;

  void start() {
    _sub = ws.listen(
      (data) {
        if (data is! String) return;
        final RelayFrame frame;
        try {
          frame = decodeRelayFrame(data);
        } on MultiplayerProtocolException {
          return; // malformed relay frame: ignore
        }
        if (frame is RelayPingFrame) {
          // Relay liveness probe: answer immediately and keep the ping out
          // of the app-facing flow (handshakes must not see it).
          try {
            ws.add(const RelayPongFrame().encode());
          } catch (_) {
            // The socket is closing; the relay's heartbeat will drop us.
          }
          return;
        }
        if (_exchanges.isNotEmpty) {
          final completer = _exchanges.removeAt(0);
          completer.complete(frame);
        } else if (!_frames.isClosed) {
          _frames.add(frame);
        }
      },
      onError: (_) => _teardown(),
      onDone: _teardown,
      cancelOnError: true,
    );
  }

  /// Sends [frame] and completes with the next incoming frame (strict
  /// request/response for setup handshakes). Throws if the connection dies
  /// or the handshake times out.
  Future<RelayFrame> exchange(
    RelayFrame frame, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    if (_closed) throw StateError('relay connection closed');
    final completer = Completer<RelayFrame>();
    _exchanges.add(completer);
    try {
      ws.add(frame.encode());
    } catch (_) {
      _exchanges.remove(completer);
      _teardown();
      rethrow;
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _exchanges.remove(completer);
        throw TimeoutException('relay handshake timed out');
      },
    );
  }

  void send(RelayFrame frame) {
    if (_closed) throw StateError('relay connection closed');
    ws.add(frame.encode());
  }

  void _teardown() {
    if (_closed) return;
    _closed = true;
    for (final completer in List.of(_exchanges)) {
      if (!completer.isCompleted) {
        completer.completeError(
          const RelayJoinException('relay connection lost'),
        );
      }
    }
    _exchanges.clear();
    if (!_frames.isClosed) unawaited(_frames.close());
    _sub?.cancel();
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      await ws.close();
    } catch (_) {}
    _teardown();
  }
}

/// The host side of a relay session.
///
/// Presents one virtual [TransportConnection] per joined client, multiplexed
/// over the host's single WebSocket. The relay reports peer join/leave via
/// PEER_JOINED/PEER_LEFT, and PEER frames are routed to the matching virtual
/// connection — so the session layer above sees exactly what it saw with
/// direct TCP connections and needs **zero** changes.
class RelayTransportServer implements TransportServer {
  RelayTransportServer(this._socket, this.sessionId) {
    _sub = _socket.frames.listen(
      _onFrame,
      onDone: () {
        for (final connection in List.of(_byMember.values)) {
          connection.markClosed();
        }
        _byMember.clear();
      },
    );
  }

  final RelaySocket _socket;
  final String sessionId;
  final StreamController<TransportConnection> _connections =
      StreamController<TransportConnection>.broadcast();
  final Map<String, _HostVirtualConnection> _byMember = {};
  StreamSubscription<RelayFrame>? _sub;
  bool _closed = false;

  @override
  Stream<TransportConnection> get connections => _connections.stream;

  /// Meaningless for a relay (the host never accepts inbound connections).
  @override
  int get port => 0;

  void _onFrame(RelayFrame frame) {
    switch (frame) {
      case RelayPeerJoinedFrame(:final member):
        final connection = _HostVirtualConnection(_socket, sessionId, member);
        _byMember[member] = connection;
        if (!_connections.isClosed) _connections.add(connection);
      case RelayPeerLeftFrame(:final member):
        _byMember.remove(member)?.markClosed();
      case RelayPeerFrame(:final from, :final payload):
        _byMember[from]?.receive(payload);
      case RelayErrFrame():
        // The relay ended the session or dropped us: every client is gone.
        for (final connection in List.of(_byMember.values)) {
          connection.markClosed();
        }
        _byMember.clear();
      default:
        break;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    for (final connection in List.of(_byMember.values)) {
      connection.markClosed();
    }
    _byMember.clear();
    if (!_connections.isClosed) unawaited(_connections.close());
    await _socket.close();
  }
}

/// One client's virtual connection on the host, multiplexed over the host's
/// single relay WebSocket.
class _HostVirtualConnection implements TransportConnection {
  _HostVirtualConnection(this._socket, this._sessionId, this.member);

  final RelaySocket _socket;
  final String _sessionId;
  final String member;
  final StreamController<String> _incoming = StreamController<String>();
  bool _closed = false;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  bool get isOpen => !_closed && _socket.isOpen;

  void receive(String payload) {
    if (_closed || _incoming.isClosed) return;
    _incoming.add(payload);
  }

  void markClosed() {
    if (_closed) return;
    _closed = true;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  Future<void> send(String message) async {
    _socket.send(
      RelaySendFrame(sessionId: _sessionId, to: member, payload: message),
    );
  }

  @override
  Future<void> close() async {
    // Host-initiated close: ask the relay to drop this member.
    if (!_closed) {
      try {
        _socket.send(RelayKickFrame(sessionId: _sessionId, member: member));
      } catch (_) {}
      markClosed();
    }
  }
}

/// The client side of a relay session: one WebSocket carrying every frame
/// from the host.
class RelayTransportConnection implements TransportConnection {
  RelayTransportConnection(this._socket, this._sessionId) {
    _sub = _socket.frames.listen(
      _onFrame,
      onDone: () {
        if (!_incoming.isClosed) unawaited(_incoming.close());
      },
    );
  }

  final RelaySocket _socket;
  final String _sessionId;
  final StreamController<String> _incoming = StreamController<String>();
  StreamSubscription<RelayFrame>? _sub;
  bool _closed = false;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  bool get isOpen => !_closed && _socket.isOpen;

  void _onFrame(RelayFrame frame) {
    switch (frame) {
      case RelayPeerFrame(:final payload):
        if (!_incoming.isClosed) _incoming.add(payload);
      case RelayErrFrame():
        _closed = true;
        if (!_incoming.isClosed) unawaited(_incoming.close());
      default:
        break;
    }
  }

  @override
  Future<void> send(String message) async {
    _socket.send(
      RelaySendFrame(
        sessionId: _sessionId,
        to: kRelayHostMember,
        payload: message,
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _socket.send(const RelayLeaveFrame());
    } catch (_) {}
    await _socket.close();
    await _sub?.cancel();
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }
}

/// The internet multiplayer transport: every device opens one outbound
/// WebSocket to the relay, so no inbound ports, no LAN address, no same
/// Wi-Fi requirement.
///
/// Implements the same [MultiplayerTransport] interface as the LAN
/// [TcpMultiplayerTransport] — the session layer is transport-agnostic, so
/// host authority, protocol, privacy, and reconnect semantics are shared.
class RelayMultiplayerTransport implements MultiplayerTransport {
  RelayMultiplayerTransport({
    required this.relayUrl,
    this.connectTimeout = const Duration(seconds: 5),
  });

  /// The relay endpoint (`ws://…` / `wss://…`).
  final String relayUrl;

  final Duration connectTimeout;

  Future<WebSocket> _open() async {
    return WebSocket.connect(relayUrl).timeout(connectTimeout);
  }

  @override
  Future<TransportServer> startServer({
    required String sessionId,
    int port = kDefaultGamePort,
    String? joinCode,
    String? displayName,
  }) async {
    final socket = RelaySocket(await _open());
    socket.start();
    final response = await socket.exchange(
      RelayHostFrame(
        sessionId: sessionId,
        joinCode: joinCode ?? '',
        displayName: displayName ?? 'Turtle King Game',
        maxPlayers: PlayerColors.maxPlayers,
      ),
      timeout: connectTimeout,
    );
    if (response is RelayErrFrame) {
      await socket.close();
      throw RelayJoinException(response.reason);
    }
    if (response is! RelayRegisteredFrame || response.sessionId != sessionId) {
      await socket.close();
      throw RelayJoinException('unexpected relay response');
    }
    return RelayTransportServer(socket, sessionId);
  }

  @override
  Future<TransportConnection> connect({
    required String hostAddress,
    required String sessionId,
    int port = kDefaultGamePort,
    Duration connectTimeout = const Duration(seconds: 5),
  }) async {
    final socket = RelaySocket(await _open());
    socket.start();
    final response = await socket.exchange(
      RelayJoinFrame(sessionId: sessionId),
      timeout: connectTimeout,
    );
    if (response is RelayJoinErrFrame) {
      await socket.close();
      throw RelayJoinException(response.reason);
    }
    if (response is! RelayJoinAckFrame || response.sessionId != sessionId) {
      await socket.close();
      throw RelayJoinException('unexpected relay response');
    }
    return RelayTransportConnection(socket, sessionId);
  }

  @override
  Future<void> dispose() async {}
}

/// Resolves a typed 6-digit [code] against the relay — the internet
/// replacement for the old UDP-beacon `resolveJoinCode`.
///
/// Never throws; always returns a typed [RelayLookupResult] within the
/// bounded [timeout].
Future<RelayLookupResult> lookupJoinCodeOnRelay(
  String relayUrl,
  String code, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    final socket = RelaySocket(
      await WebSocket.connect(relayUrl).timeout(timeout),
    );
    socket.start();
    final response = await socket.exchange(
      RelayLookupFrame(joinCode: code),
      timeout: timeout,
    );
    await socket.close();
    return switch (response) {
      RelayLookupAckFrame(:final sessionId, :final displayName) =>
        RelayLookupFound(sessionId: sessionId, displayName: displayName),
      RelayLookupErrFrame() => const RelayLookupNotFound(),
      _ => const RelayLookupUnavailable('unexpected relay response'),
    };
  } on TimeoutException {
    return const RelayLookupUnavailable('relay timed out');
  } on SocketException {
    return const RelayLookupUnavailable('relay unreachable');
  } catch (_) {
    return const RelayLookupUnavailable('relay unavailable');
  }
}
