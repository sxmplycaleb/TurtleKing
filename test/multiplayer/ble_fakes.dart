// Test-only fake: deliberately exposes the internal fake connection types
// to the transport tests (they drive the in-memory network directly).
// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:typed_data';

import 'package:turtle_king/multiplayer/ble/ble_adapter.dart';

/// An in-memory simulation of a room of Bluetooth phones.
///
/// A [FakeBleAdapter] acting as a host registers itself in the network; a
/// [FakeBleAdapter] acting as a client scans, discovers registered hosts,
/// and connects. Data flows through the shared network exactly like GATT
/// notifications/writes: client → host via [BleAdapter.hostData], host →
/// client via [BleAdapter.sendToHostPeer] routed to the right link.
///
/// Tests drive the REAL [BleMultiplayerTransport], [BleTransportServer],
/// [BleSessionDiscovery], framing, and the real HostSession/ClientSession
/// over this fake — the only thing not exercised is the platform plugin
/// itself (which requires physical hardware).
class FakeBleNetwork {
  final Map<String, _FakeHostEntry> _hosts = {};
  final Map<String, _ForeignAdvertiser> _foreign = {};
  final Map<String, _FakeCentralConnection> _links = {};
  int _hostSeq = 0;
  int _clientSeq = 0;

  Iterable<_FakeHostEntry> get hosts => _hosts.values;

  String registerHost(FakeBleAdapter adapter, String displayName) {
    final id = 'fake-host-${_hostSeq++}';
    _hosts[id] = _FakeHostEntry(id, displayName, adapter);
    return id;
  }

  /// A nearby BLE device that is NOT a Turtle King host (it advertises a
  /// different service UUID). `startScan` reports it like any other
  /// advertiser — the discovery layer must filter it out (defense in depth
  /// against platforms that return unrelated advertisers).
  void registerForeignAdvertiser(String id, String displayName) {
    _foreign[id] = _ForeignAdvertiser(id, displayName);
  }

  /// Graceful host teardown: removes the host and drops its links.
  void unregisterHost(String hostId) {
    _hosts.remove(hostId);
    for (final link in List.of(_links.values)) {
      if (link.hostId == hostId) link.forceDrop();
    }
  }

  /// Abrupt host loss (app killed / out of range): drops every client link
  /// without a host-side close — the client must detect it via its own
  /// disconnect stream.
  void simulateHostLoss(String hostId) {
    for (final link in List.of(_links.values)) {
      if (link.hostId == hostId) link.forceDrop();
    }
  }

  /// Drops one client link WITHOUT notifying the host (`BleHostDisconnected`
  /// is never delivered) — simulating a platform that misses the peripheral
  /// disconnect event. The host's `_byPeer` keeps the stale entry; a
  /// reconnecting client must still be re-admitted, or its JOIN_REQUEST is
  /// silently dropped (the real-device mid-game reconnect failure).
  void simulateClientLinkSilentDrop(String clientId) {
    _links[clientId]?.silentDrop();
  }

  String nextClientId() => 'fake-client-${_clientSeq++}';

  void track(_FakeCentralConnection link) => _links[link.clientId] = link;

  void untrack(String clientId) => _links.remove(clientId);

  void deliverToClient(String clientId, Uint8List bytes) {
    _links[clientId]?.deliver(bytes);
  }
}

class _FakeHostEntry {
  _FakeHostEntry(this.id, this.displayName, this.adapter);

  final String id;
  final String displayName;
  final FakeBleAdapter adapter;
}

class _ForeignAdvertiser {
  _ForeignAdvertiser(this.id, this.displayName);

  final String id;
  final String displayName;
}

/// A simulated Bluetooth adapter. Configure [status] for permission/adapter
/// state tests, [chunkSize] for MTU-boundary tests, and [connectGate] to
/// hold connects open (duplicate-join / timeout tests).
class FakeBleAdapter implements BleAdapter {
  FakeBleAdapter(
    this.network, {
    this.status = BleAdapterStatus.poweredOn,
    this.chunkSize = 180,
  });

  final FakeBleNetwork network;

  @override
  BleAdapterStatus status;

  /// Largest single chunk (notification / write) this link accepts.
  int chunkSize;

  /// When set, [connect] awaits it before completing — lets tests hold a
  /// join in flight (duplicate join, cancellation, timeout).
  Completer<void>? connectGate;

  /// When true, [connect] never completes and never throws — simulates a
  /// platform connect that fails silently (Android `connectGatt` without a
  /// callback). The transport-level timeout must still surface a typed
  /// failure instead of hanging.
  bool hangConnect = false;

  String? _hostId;
  bool _hosting = false;
  bool _scanning = false;
  bool _disposed = false;

  /// The adapter's most recent client link (for tests that need to drop a
  /// specific client link without the host observing the disconnect).
  _FakeCentralConnection? _lastClientLink;

  /// The client connection id of this adapter's most recent join, when it
  /// joined as a client. Test accessor.
  String? get lastClientLinkId => _lastClientLink?.clientId;

  /// The network id this adapter advertises as, once hosting (null until
  /// [startHost]). Test accessor — the id is opaque on the wire.
  String? get hostId => _hostId;

  /// The adapter this host advertises with, when hosting. Test accessor.
  bool get isHosting => _hosting;

  /// Whether a client scan is currently active. Test accessor.
  bool get isScanning => _scanning;

  StreamController<BleHostEvent>? _hostEvents;
  StreamController<BleHostData>? _hostData;
  StreamController<BleDiscoveredPeer>? _discovered;

  @override
  Future<bool> ensureAuthorized() async =>
      status != BleAdapterStatus.unauthorized;

  @override
  Future<void> showAppSettings() async {}

  // -------------------------------------------------------------------
  // Host side
  // -------------------------------------------------------------------

  @override
  Future<void> startHost({required String displayName}) async {
    if (_hosting || _disposed) return;
    _hosting = true;
    _hostEvents = StreamController<BleHostEvent>.broadcast();
    _hostData = StreamController<BleHostData>.broadcast();
    _hostId = network.registerHost(this, displayName);
  }

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> stopHost() async {
    if (!_hosting) return;
    _hosting = false;
    final id = _hostId;
    _hostId = null;
    if (id != null) network.unregisterHost(id);
    final events = _hostEvents;
    final data = _hostData;
    _hostEvents = null;
    _hostData = null;
    if (events != null && !events.isClosed) await events.close();
    if (data != null && !data.isClosed) await data.close();
  }

  @override
  Stream<BleHostEvent> get hostEvents =>
      _hostEvents?.stream ?? const Stream.empty();

  @override
  Stream<BleHostData> get hostData => _hostData?.stream ?? const Stream.empty();

  @override
  Future<int> hostNotifyChunkSize(String peerId) async => chunkSize;

  @override
  Future<void> sendToHostPeer(String peerId, Uint8List bytes) async {
    network.deliverToClient(peerId, bytes);
  }

  @override
  Future<void> dropPeer(String peerId) async {
    network._links[peerId]?.forceDrop();
  }

  // -------------------------------------------------------------------
  // Client side
  // -------------------------------------------------------------------

  @override
  Future<void> startScan() async {
    if (_scanning || _disposed) return;
    _scanning = true;
    _discovered ??= StreamController<BleDiscoveredPeer>.broadcast();
    // Let the listener attach before emitting (one microtask hop).
    await Future<void>.delayed(Duration.zero);
    for (final host in network.hosts) {
      if (_disposed || _discovered!.isClosed) return;
      _discovered!.add(
        BleDiscoveredPeer(
          id: host.id,
          displayName: host.displayName,
          rssi: -50,
          serviceUuids: {kTurtleKingBleServiceUuidString},
        ),
      );
    }
    // Unrelated advertisers: reported by the platform (simulated), the
    // discovery layer must reject them.
    for (final foreign in network._foreign.values) {
      if (_disposed || _discovered!.isClosed) return;
      _discovered!.add(
        BleDiscoveredPeer(
          id: foreign.id,
          displayName: foreign.displayName,
          rssi: -70,
          serviceUuids: {'0000abcd-0000-1000-8000-00805f9b34fb'},
        ),
      );
    }
  }

  /// Test hook: pushes a scan result directly into the discovered stream,
  /// simulating the platform reporting an advertiser after the scan has
  /// started — used for malformed/duplicate advertisement tests.
  void emitScanResult(BleDiscoveredPeer peer) {
    final ctrl = _discovered ??=
        StreamController<BleDiscoveredPeer>.broadcast();
    if (!ctrl.isClosed) ctrl.add(peer);
  }

  @override
  Future<void> stopScan() async => _scanning = false;

  @override
  Stream<BleDiscoveredPeer> get discovered {
    // MUST stay lazy (create the controller on first access): the real
    // PluginBleAdapter.discovered does the same, and BleSessionDiscovery
    // subscribes here *before* startScan() creates the controller — a
    // non-lazy getter returns an empty stream and silently drops every
    // discovered host on real devices (regression guarded here + on-device).
    _discovered ??= StreamController<BleDiscoveredPeer>.broadcast();
    return _discovered!.stream;
  }

  @override
  Future<BleCentralConnection> connect(
    String peerId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final host = network._hosts[peerId];
    if (host == null) {
      throw Exception('The host is no longer visible. Search again.');
    }
    if (hangConnect) {
      // Never completes, never throws — a silent platform failure.
      await Completer<void>().future;
    }
    final gate = connectGate;
    if (gate != null) {
      try {
        await gate.future.timeout(
          timeout,
          onTimeout: () => throw TimeoutException('connection timed out'),
        );
      } on TimeoutException {
        throw Exception('Connection timed out.');
      }
    }
    // A real device reconnects with the SAME BLE address (the peer id is
    // the MAC-derived UUID), so a reconnecting client reuses its previous
    // client id — this is what exercises the host's stale-admit path.
    final previous = _lastClientLink;
    final clientId = previous != null && previous.isClosed
        ? previous.clientId
        : network.nextClientId();
    final link = _FakeCentralConnection(clientId, host, network, chunkSize);
    network.track(link);
    _lastClientLink = link;
    // Admit the peer on the host BEFORE returning: the host's server admits
    // on this event, so the client's first JOIN_REQUEST lands on a live
    // connection.
    host.adapter._hostEvents?.add(BleHostConnected(clientId));
    await Future<void>.delayed(Duration.zero);
    return link;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopScan();
    await stopHost();
  }
}

/// One client-side link, wired through the shared network.
class _FakeCentralConnection implements BleCentralConnection {
  _FakeCentralConnection(
    this.clientId,
    this.host,
    this.network,
    this.chunkSize,
  );

  final String clientId;
  final _FakeHostEntry host;
  final FakeBleNetwork network;
  final int chunkSize;

  String get hostId => host.id;

  @override
  int get writeChunkSize => chunkSize;

  final StreamController<Uint8List> _data =
      StreamController<Uint8List>.broadcast();
  final StreamController<void> _disconnected =
      StreamController<void>.broadcast();
  bool _closed = false;

  @override
  Stream<Uint8List> get data => _data.stream;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  void deliver(Uint8List bytes) {
    if (!_closed && !_data.isClosed) _data.add(bytes);
  }

  @override
  Future<void> send(Uint8List bytes) async {
    if (_closed) return;
    host.adapter._hostData?.add(BleHostData(peerId: clientId, bytes: bytes));
  }

  /// Abrupt drop: fires the client's disconnect stream and closes the data
  /// stream, and notifies the host (Android's peripheral reports dropped
  /// connections via `connectionStateChanged`), so a live host removes the
  /// peer while the client itself detects the drop via its own stream.
  /// Whether this link has been dropped/closed (the client id may be
  /// reused by a reconnecting client, like a real device's stable address).
  bool get isClosed => _closed;

  void forceDrop() {
    if (_closed) return;
    _closed = true;
    network.untrack(clientId);
    host.adapter._hostEvents?.add(BleHostDisconnected(clientId));
    if (!_data.isClosed) unawaited(_data.close());
    if (!_disconnected.isClosed) unawaited(_disconnected.close());
  }

  /// Drops the link from the client's perspective only: the client sees its
  /// disconnect stream fire, but the host is never told (the peripheral
  /// disconnect event is lost — a real platform behavior). The host keeps
  /// its `_byPeer` entry for this client.
  void silentDrop() {
    if (_closed) return;
    _closed = true;
    network.untrack(clientId);
    if (!_data.isClosed) unawaited(_data.close());
    if (!_disconnected.isClosed) unawaited(_disconnected.close());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    network.untrack(clientId);
    // Graceful leave: the host sees a disconnect event.
    host.adapter._hostEvents?.add(BleHostDisconnected(clientId));
    if (!_data.isClosed) unawaited(_data.close());
    if (!_disconnected.isClosed) unawaited(_disconnected.close());
  }
}
