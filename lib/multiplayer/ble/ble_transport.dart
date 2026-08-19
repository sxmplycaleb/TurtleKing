import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../transport.dart';
import 'ble_adapter.dart';
import 'ble_framing.dart';
import 'plugin_ble_adapter.dart';

/// The Bluetooth Low Energy multiplayer transport: host = GATT peripheral,
/// clients = GATT centrals.
///
/// Implements the same [MultiplayerTransport] interface as the LAN TCP and
/// relay WebSocket transports, so the session layer (HostSession /
/// ClientSession), the protocol codec, and every privacy/authority rule are
/// reused **unchanged**. The only BLE-specific logic is the chunked framing
/// ([BleFrameAssembler]) that fits the existing newline-free JSON messages
/// into BLE MTU-sized notifications/writes.
///
/// Addressing: [MultiplayerTransport.connect]'s [hostAddress] carries the
/// peer's BLE identifier (exactly as the relay transport reinterprets it as
/// a URL); [port] is ignored (pass 0), like the relay.
class BleMultiplayerTransport implements MultiplayerTransport {
  BleMultiplayerTransport({BleAdapter? adapter})
    : _adapter = adapter ?? PluginBleAdapter();

  final BleAdapter _adapter;

  /// The underlying adapter (shared with discovery; exposed for tests).
  BleAdapter get adapter => _adapter;

  @override
  Future<TransportServer> startServer({
    required String sessionId,
    int port = kDefaultGamePort,
    String? joinCode,
    String? displayName,
  }) async {
    await _adapter.startHost(displayName: displayName ?? 'Turtle King Game');
    return BleTransportServer(_adapter);
  }

  @override
  Future<TransportConnection> connect({
    required String hostAddress,
    required String sessionId,
    int port = kDefaultGamePort,
    Duration connectTimeout = const Duration(seconds: 5),
  }) async {
    // Belt and braces: the plugin adapter also enforces [connectTimeout]
    // around its native connect (which can fail silently on Android), but
    // the transport guarantees it even for adapters that don't — a join
    // must never sit on "Connecting…" forever.
    final link = await _adapter
        .connect(hostAddress, timeout: connectTimeout)
        .timeout(connectTimeout);
    return BleClientTransportConnection(link);
  }

  @override
  Future<void> dispose() => _adapter.dispose();
}

/// Host side of a BLE session: one [TransportConnection] per connected
/// central, delivered over [TransportServer.connections].
///
/// The host's GATT server is a single service shared by every client, but
/// each central gets its own virtual connection (same shape as the relay's
/// [RelayTransportServer], which multiplexes per-member connections over one
/// socket) — the session layer above sees exactly what it sees with TCP.
class BleTransportServer implements TransportServer {
  BleTransportServer(this._adapter) {
    _eventsSub = _adapter.hostEvents.listen(_onHostEvent);
    _dataSub = _adapter.hostData.listen(_onHostData);
  }

  final BleAdapter _adapter;
  final StreamController<TransportConnection> _connections =
      StreamController<TransportConnection>();
  final Map<String, _HostBleConnection> _byPeer = {};
  StreamSubscription<BleHostEvent>? _eventsSub;
  StreamSubscription<BleHostData>? _dataSub;
  bool _closed = false;

  @override
  Stream<TransportConnection> get connections => _connections.stream;

  /// Meaningless for BLE (the host never binds a port).
  @override
  int get port => 0;

  void _onHostEvent(BleHostEvent event) {
    switch (event) {
      case BleHostConnected(:final peerId):
        unawaited(_admit(peerId));
      case BleHostDisconnected(:final peerId):
        _byPeer.remove(peerId)?.markClosed();
    }
  }

  Future<void> _admit(String peerId) async {
    if (_closed) return;
    final stale = _byPeer[peerId];
    if (stale != null) {
      // A reconnecting peer arrives while the host still tracks the OLD
      // (dead) link — Android can miss the peripheral disconnect event, so
      // BleHostDisconnected never fired and the stale entry survived. Skip-
      // ping here would silently drop the rejoin's JOIN_REQUEST (real-device
      // mid-game reconnect failure: GATT reconnect succeeds, then
      // "Connection failed"). Tear the old connection down so the session
      // layer frees the player seat, then admit the fresh link below. The
      // old connection's close() is guarded so it cannot dropPeer the new
      // link (they share the same peer id).
      _byPeer.remove(peerId);
      stale.markClosed();
    }
    final notifyChunkSize = await _adapter.hostNotifyChunkSize(peerId);
    if (_closed) return;
    late final _HostBleConnection connection;
    connection = _HostBleConnection(
      _adapter,
      peerId,
      notifyChunkSize,
      // Only the CURRENT connection may drop the peer's platform link: a
      // stale connection's close (after a reconnect replaced it) must not
      // tear down the fresh GATT link, which shares the same peer id.
      isCurrent: () => identical(_byPeer[peerId], connection),
    );
    _byPeer[peerId] = connection;
    if (!_connections.isClosed) _connections.add(connection);
  }

  void _onHostData(BleHostData data) {
    _byPeer[data.peerId]?.receive(data.bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _eventsSub?.cancel();
    await _dataSub?.cancel();
    for (final connection in List.of(_byPeer.values)) {
      connection.markClosed();
    }
    _byPeer.clear();
    await _adapter.stopHost();
    if (!_connections.isClosed) await _connections.close();
  }
}

/// One connected client on the host, presented as a [TransportConnection].
///
/// Sends are **serialized** through a per-connection queue: the session layer
/// fires messages unawaited, and interleaving two chunked messages would
/// corrupt framing (the TCP/relay transports serialize the same way).
class _HostBleConnection implements TransportConnection {
  _HostBleConnection(
    this._adapter,
    this.peerId,
    this.notifyChunkSize, {
    required this.isCurrent,
  });

  final BleAdapter _adapter;
  final String peerId;
  final int notifyChunkSize;

  /// Whether this connection is still the one the server tracks for its
  /// peer id (false after a reconnect replaced it).
  final bool Function() isCurrent;
  final StreamController<String> _incoming = StreamController<String>();
  final BleFrameAssembler _assembler = BleFrameAssembler();
  Future<void> _sendQueue = Future.value();
  bool _closed = false;

  void receive(Uint8List bytes) {
    if (_closed) return;
    try {
      for (final message in _assembler.feed(bytes)) {
        if (!_incoming.isClosed) {
          _incoming.add(utf8.decode(message));
        }
      }
    } on FormatException {
      // Malformed framing = protocol violation: drop this peer's link so
      // the client sees the disconnect (same as a TCP server closing the
      // socket on garbage).
      unawaited(close());
    }
  }

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  bool get isOpen => !_closed;

  @override
  Future<void> send(String message) {
    // Chain onto the previous send so chunks of one message are never
    // interleaved with chunks of another.
    final next = _sendQueue.then((_) async {
      if (_closed) return;
      for (final chunk in encodeBleString(message, notifyChunkSize)) {
        await _adapter.sendToHostPeer(peerId, chunk);
      }
    });
    _sendQueue = next.catchError((_) {});
    return next;
  }

  void markClosed() {
    if (_closed) return;
    _closed = true;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    markClosed();
    // Only tear down the platform link if this is still the live connection
    // for the peer. A stale connection replaced by a reconnect must not
    // dropPeer the new link (same peer id) — the new GATT connection is the
    // one the client is using now.
    if (isCurrent()) {
      await _adapter.dropPeer(peerId);
    }
  }
}

/// Client side of a BLE session: a byte link plus chunked framing.
class BleClientTransportConnection implements TransportConnection {
  BleClientTransportConnection(this._link) {
    _dataSub = _link.data.listen(
      (bytes) {
        try {
          for (final message in _assembler.feed(bytes)) {
            if (!_incoming.isClosed) {
              _incoming.add(utf8.decode(message));
            }
          }
        } on FormatException {
          markClosed();
        }
      },
      onError: (_) => markClosed(),
      onDone: markClosed,
    );
    _discSub = _link.disconnected.listen((_) => markClosed());
  }

  final BleCentralConnection _link;
  final StreamController<String> _incoming = StreamController<String>();
  final BleFrameAssembler _assembler = BleFrameAssembler();
  Future<void> _sendQueue = Future.value();
  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<void>? _discSub;
  bool _closed = false;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  bool get isOpen => !_closed;

  @override
  Future<void> send(String message) {
    // Serialize like the host side (and the TCP/relay transports) so two
    // unawaited sends cannot interleave their chunks.
    final next = _sendQueue.then((_) async {
      if (_closed) return;
      for (final chunk in encodeBleString(message, _link.writeChunkSize)) {
        await _link.send(chunk);
      }
    });
    _sendQueue = next.catchError((_) {});
    return next;
  }

  void markClosed() {
    if (_closed) return;
    _closed = true;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    markClosed();
    await _dataSub?.cancel();
    await _discSub?.cancel();
    await _link.close();
  }
}
