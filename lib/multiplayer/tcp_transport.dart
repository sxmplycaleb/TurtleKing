import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'transport.dart';

/// The maximum size of one framed message. Bounds the memory a misbehaving
/// peer can force us to buffer before it is disconnected.
const int kMaxFrameBytes = 256 * 1024;

/// Splits a UTF-8 string stream into newline-delimited frames.
///
/// Frames larger than [maxChars] terminate the stream (the connection is
/// treated as dead) instead of buffering unbounded input. Trailing `\r` is
/// stripped so `\r\n` line endings are accepted. Never emits errors — an
/// oversized frame simply ends the stream, which the connection converts
/// into a socket close.
class _BoundedLineSplitter implements StreamTransformer<String, String> {
  const _BoundedLineSplitter(this.maxChars);

  final int maxChars;

  @override
  Stream<String> bind(Stream<String> stream) async* {
    var buffer = StringBuffer();
    await for (final chunk in stream) {
      buffer.write(chunk);
      final text = buffer.toString();
      var start = 0;
      while (true) {
        final newline = text.indexOf('\n', start);
        if (newline < 0) break;
        final line = text.substring(start, newline);
        if (line.isNotEmpty) {
          yield line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
        }
        start = newline + 1;
      }
      buffer = StringBuffer(start < text.length ? text.substring(start) : '');
      if (buffer.length > maxChars) return;
    }
    final tail = buffer.toString();
    if (tail.isNotEmpty && tail.length <= maxChars) yield tail;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() => StreamTransformer.castFrom(this);
}

/// One newline-delimited JSON message channel over a TCP [Socket].
class TcpTransportConnection implements TransportConnection {
  TcpTransportConnection(this._socket) {
    _subscription = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const _BoundedLineSplitter(kMaxFrameBytes))
        .listen(
          _controller.add,
          onError: (_) => _teardown(),
          onDone: _teardown,
          cancelOnError: true,
        );
  }

  final Socket _socket;
  final StreamController<String> _controller = StreamController<String>();
  StreamSubscription<String>? _subscription;
  bool _closed = false;

  /// Serializes writes and flushes so concurrent senders never overlap
  /// `flush()` calls on the same socket. Overlapping flushes fail on some
  /// platforms with `StreamSink is bound to a stream`, silently dropping
  /// a frame (observed as a lost ROSTER_UPDATE right after a JOIN_ACCEPT).
  Future<void> _writeQueue = Future<void>.value();

  @override
  Stream<String> get incoming => _controller.stream;

  @override
  bool get isOpen => !_closed;

  @override
  Future<void> send(String message) {
    // Chain this send after every previous one. Each caller still receives
    // its own success/failure; a failed send does not poison the queue.
    final result = _writeQueue.then((_) => _sendNow(message));
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _sendNow(String message) async {
    if (_closed) {
      throw StateError('connection closed');
    }
    _socket.write(message);
    _socket.write('\n');
    await _socket.flush();
  }

  void _teardown() {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    if (!_controller.isClosed) {
      // Not awaited: the done event is delivered to the active listener.
      unawaited(_controller.close());
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Destroy the socket BEFORE cancelling the subscription: on some
    // platforms cancelling a live socket stream subscription can hang
    // indefinitely. destroy() is synchronous; the resulting onDone/onError
    // is handled by [_teardown] (which is a no-op now that we are closed).
    _socket.destroy();
    await _subscription?.cancel();
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }
}

/// The host side of a LAN session: accepts clients over TCP.
class TcpTransportServer implements TransportServer {
  TcpTransportServer._(this._server);

  final ServerSocket _server;
  final StreamController<TransportConnection> _controller =
      StreamController<TransportConnection>();
  final List<TransportConnection> _connections = [];
  bool _closed = false;

  /// Binds a server on [port] (0 for an ephemeral port) and starts accepting.
  static Future<TcpTransportServer> bind({required int port}) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    final result = TcpTransportServer._(server);
    server.listen(result._onSocket, onError: (_) {});
    return result;
  }

  void _onSocket(Socket socket) {
    final connection = TcpTransportConnection(socket);
    _connections.add(connection);
    _controller.add(connection);
  }

  @override
  Stream<TransportConnection> get connections => _controller.stream;

  @override
  int get port => _server.port;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close();
    for (final connection in List.of(_connections)) {
      await connection.close();
    }
    _connections.clear();
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }
}

/// The concrete LAN transport: `dart:io` TCP sockets.
///
/// Hosts sessions with [startServer] and connects clients with [connect];
/// both speak newline-delimited JSON through [TcpTransportConnection] and
/// reuse the [MessageCodec] at the session layer. No authoritative state or
/// gameplay data ever enters this layer.
class TcpMultiplayerTransport implements MultiplayerTransport {
  final List<TcpTransportServer> _servers = [];
  bool _disposed = false;

  @override
  Future<TransportServer> startServer({
    required String sessionId,
    int port = kDefaultGamePort,
    String? joinCode,
    String? displayName,
  }) async {
    // LAN mode: join code and display name are carried by the UDP discovery
    // beacons (UdpBeaconDiscovery.advertise), not by the TCP server.
    final server = await TcpTransportServer.bind(port: port);
    _servers.add(server);
    return server;
  }

  @override
  Future<TransportConnection> connect({
    required String hostAddress,
    required String sessionId,
    int port = kDefaultGamePort,
    Duration connectTimeout = const Duration(seconds: 5),
  }) async {
    final socket = await Socket.connect(
      hostAddress,
      port,
      timeout: connectTimeout,
    );
    return TcpTransportConnection(socket);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final server in _servers) {
      await server.close();
    }
    _servers.clear();
  }
}
