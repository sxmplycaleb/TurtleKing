import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/transport.dart';

/// A minimal in-memory [TransportConnection] pair: whatever one side sends
/// arrives on the other's [incoming] stream. Exercises the interface contract
/// without any real network.
class _MemoryPipe implements TransportConnection {
  _MemoryPipe();

  _MemoryPipe? _peer;
  final StreamController<String> _controller = StreamController<String>();
  bool _closed = false;

  /// Connects this pipe's send side to [other]'s incoming stream.
  void link(_MemoryPipe other) => _peer = other;

  @override
  Stream<String> get incoming => _controller.stream;

  @override
  bool get isOpen => !_closed;

  @override
  Future<void> send(String message) async {
    if (_closed) throw StateError('connection closed');
    _peer?._controller.add(message);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _peer?._closed = true;
    // A single-subscription controller only delivers its done event once a
    // listener exists, so awaiting close() could hang. The interface only
    // requires close() to complete; deliver the done event lazily.
    unawaited(_controller.close());
  }
}

void main() {
  group('TransportConnection contract', () {
    test('delivers messages from one end to the other in order', () async {
      final a = _MemoryPipe();
      final b = _MemoryPipe();
      a.link(b);
      b.link(a);

      final received = <String>[];
      final sub = b.incoming.listen(received.add);

      await a.send('{"type":"HEARTBEAT","seq":1}');
      await a.send('{"type":"HEARTBEAT","seq":2}');
      await Future<void>.delayed(Duration.zero);

      expect(received, [
        '{"type":"HEARTBEAT","seq":1}',
        '{"type":"HEARTBEAT","seq":2}',
      ]);
      await sub.cancel();
    });

    test('close is idempotent and flips isOpen on both ends', () async {
      final a = _MemoryPipe();
      final b = _MemoryPipe();
      a.link(b);
      b.link(a);

      expect(a.isOpen, isTrue);
      await a.close();
      expect(a.isOpen, isFalse);
      expect(b.isOpen, isFalse);
      // Closing again must not throw.
      await a.close();
      expect(a.isOpen, isFalse);
    });

    test('sending after close throws instead of silently dropping', () async {
      final a = _MemoryPipe();
      await a.close();
      expect(() => a.send('anything'), throwsStateError);
    });
  });

  group('transport interface shape', () {
    test('declares the host/client/discovery surface the LAN plan needs', () {
      // Compile-time contract: the interfaces exist with the documented
      // methods; a future dart:io implementation will satisfy them.
      expect(MultiplayerTransport, isA<Type>());
      expect(TransportServer, isA<Type>());
      expect(TransportConnection, isA<Type>());
      expect(SessionDiscovery, isA<Type>());
      final discovered = DiscoveredSession(
        sessionId: 's',
        displayName: 'Caleb\'s game',
        hostAddress: '192.168.1.20',
      );
      expect(discovered.sessionId, 's');
      expect(discovered.displayName, 'Caleb\'s game');
      expect(discovered.hostAddress, '192.168.1.20');
    });
  });
}
