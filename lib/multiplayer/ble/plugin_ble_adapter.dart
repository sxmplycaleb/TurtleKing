import 'dart:async';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

import 'ble_adapter.dart';

/// The Turtle King BLE service UUID (vendor range 0xFC00). Built from the
/// canonical string constant so advertising, the client scan filter, and
/// the discovery-layer verification all agree on one value.
final UUID kTurtleKingBleServiceUuid = UUID.fromString(
  kTurtleKingBleServiceUuidString,
);

/// Client → host data characteristic (writes).
final UUID kBleWriteCharacteristicUuid = UUID.fromString('FC01');

/// Host → client data characteristic (notifications).
final UUID kBleNotifyCharacteristicUuid = UUID.fromString('FC02');

/// Thrown when a BLE operation cannot proceed (adapter off, permission
/// denied, connect timeout, device gone). The session layer maps this to a
/// friendly join error — never to the user raw.
class BleConnectException implements Exception {
  const BleConnectException(this.reason);

  final String reason;

  @override
  String toString() => 'BleConnectException: $reason';
}

/// The production [BleAdapter], backed by the `bluetooth_low_energy` plugin.
///
/// Host role: publishes one primary GATT service with two characteristics —
/// a write characteristic (clients → host, `withResponse` writes) and a
/// notify characteristic (host → clients, subscriptions). The host
/// advertises the service UUID only (no name — Android's plugin implements
/// an advertised name by renaming the device, which hangs repeat hosts and
/// renames the user's phone; see [startHost]), and a client is admitted as
/// soon as it subscribes to notifications (a cross-platform "I'm here"
/// signal — Android additionally reports connect/disconnect via
/// `connectionStateChanged`, which iOS does not expose from the peripheral
/// side; the session heartbeat covers silent peers there).
///
/// Client role: scans filtered to the service UUID, connects, discovers
/// GATT, requests a larger MTU (Android), subscribes to notifications, and
/// returns a byte link. Reads/writes are raw chunks; framing/reassembly
/// lives in `ble_framing.dart` one layer up.
///
/// Platform-specific APIs that throw [UnsupportedError] (authorize on iOS,
/// requestMTU on iOS, peripheral-side connection events on iOS) are guarded
/// so the same Dart code runs on both platforms.
class PluginBleAdapter implements BleAdapter {
  PluginBleAdapter()
    : _central = CentralManager(),
      _peripheral = PeripheralManager();

  final CentralManager _central;
  final PeripheralManager _peripheral;

  // --- client (central) side ---
  final Map<String, Peripheral> _peripherals = {};
  StreamController<BleDiscoveredPeer>? _discoveredCtrl;
  StreamSubscription<DiscoveredEventArgs>? _scanSub;
  bool _scanning = false;

  // --- host (peripheral) side ---
  final Map<String, Central> _centrals = {};
  StreamController<BleHostEvent>? _hostEventsCtrl;
  StreamController<BleHostData>? _hostDataCtrl;
  GATTCharacteristic? _notifyChar;
  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>? _writeSub;
  StreamSubscription<GATTCharacteristicNotifyStateChangedEventArgs>?
  _notifyStateSub;
  StreamSubscription<CentralConnectionStateChangedEventArgs>? _connSub;
  bool _hostRunning = false;
  bool _disposed = false;

  @override
  BleAdapterStatus get status {
    if (_disposed) return BleAdapterStatus.unknown;
    final raw = _central.state;
    return switch (raw) {
      BluetoothLowEnergyState.poweredOn => BleAdapterStatus.poweredOn,
      BluetoothLowEnergyState.poweredOff => BleAdapterStatus.poweredOff,
      BluetoothLowEnergyState.unauthorized => BleAdapterStatus.unauthorized,
      BluetoothLowEnergyState.unsupported => BleAdapterStatus.unsupported,
      BluetoothLowEnergyState.unknown => BleAdapterStatus.unknown,
    };
  }

  /// How long a permission request may take before we give up waiting on the
  /// plugin's result callback. The plugin's `authorize()` awaits an
  /// `onRequestPermissionsResult` delivery that can silently never arrive
  /// (when the permissions are already granted, or the result is lost), so
  /// this bounds the wait — the lobby must never hang on "Starting…" forever.
  static const Duration _authorizeTimeout = Duration(seconds: 15);

  @override
  Future<bool> ensureAuthorized() async {
    if (_disposed) return false;
    // Let the managers' construction-time state query settle, so `status`
    // reflects reality before we decide anything.
    for (var i = 0; i < 20 && status == BleAdapterStatus.unknown; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Fast path: permissions are already granted (the managers observed it
    // at construction or on app resume), so there is nothing to request.
    if (status != BleAdapterStatus.unauthorized) return true;
    // Both managers need their role-specific permissions: the central needs
    // BLUETOOTH_SCAN/CONNECT (client), the peripheral needs
    // BLUETOOTH_ADVERTISE/CONNECT (host). On Android the runtime prompt is
    // raised per manager, so the host flow must authorize the peripheral too
    // or startAdvertising() throws a SecurityException on Android 12+.
    //
    // The plugin refreshes its state only at construction and on app resume
    // (WidgetsBindingObserver.didChangeAppLifecycleState) — not when
    // authorize() completes. So after the permission prompts dismiss, the
    // state flips to authorized on resume, which the state watcher below
    // observes. Racing the callback against that refresh means a lost
    // callback (a real plugin behavior) does not leave us hanging: we
    // proceed as soon as either signal arrives, and [timeout] bounds the
    // pathological case where neither does.
    for (final manager in [_central, _peripheral]) {
      try {
        await Future.any([
          manager.authorize(),
          _waitForStatusRefresh(),
        ]).timeout(_authorizeTimeout);
      } on TimeoutException {
        // The result callback was lost and no state refresh arrived; the
        // final check below decides from the (possibly now-granted) state.
      } on UnsupportedError {
        // iOS: the OS prompts automatically on first use; state reflects it.
      } catch (_) {
        // Any platform quirk: fall through to the state check.
      }
    }
    // Give the post-prompt resume refresh a moment to land.
    for (var i = 0; i < 30 && status == BleAdapterStatus.unauthorized; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return status != BleAdapterStatus.unauthorized;
  }

  /// Completes as soon as the adapter stops reporting `unauthorized` (the
  /// managers refresh their state on app resume, which follows the
  /// permission prompt being dismissed). Never errors; used in a race with
  /// the plugin's authorize() callback.
  Future<void> _waitForStatusRefresh() async {
    while (status == BleAdapterStatus.unauthorized) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  Future<void> showAppSettings() async {
    try {
      await _central.showAppSettings();
    } catch (_) {
      // Best-effort: the caller already surfaces a message.
    }
  }

  // -------------------------------------------------------------------
  // Host (peripheral)
  // -------------------------------------------------------------------

  @override
  Future<void> startHost({required String displayName}) async {
    if (_disposed) return;
    if (_hostRunning) return;
    final writeChar = GATTCharacteristic.mutable(
      uuid: kBleWriteCharacteristicUuid,
      properties: [GATTCharacteristicProperty.write],
      permissions: [GATTCharacteristicPermission.write],
      descriptors: const [],
    );
    final notifyChar = GATTCharacteristic.mutable(
      uuid: kBleNotifyCharacteristicUuid,
      properties: [GATTCharacteristicProperty.notify],
      permissions: [GATTCharacteristicPermission.read],
      descriptors: const [],
    );
    final service = GATTService(
      uuid: kTurtleKingBleServiceUuid,
      isPrimary: true,
      includedServices: const [],
      characteristics: [writeChar, notifyChar],
    );
    await _peripheral.addService(service);
    _notifyChar = notifyChar;

    _hostEventsCtrl = StreamController<BleHostEvent>.broadcast();
    _hostDataCtrl = StreamController<BleHostData>.broadcast();

    // Inbound writes from clients (the write characteristic is
    // `withResponse`, so every request must be answered or the client's
    // write hangs).
    _writeSub = _peripheral.characteristicWriteRequested.listen((event) {
      final id = event.central.uuid.toString();
      _centrals[id] = event.central;
      if (event.characteristic.uuid != kBleWriteCharacteristicUuid) {
        return;
      }
      try {
        unawaited(_peripheral.respondWriteRequest(event.request));
      } catch (_) {
        // Link already gone; the heartbeat will reap the peer.
      }
      final ctrl = _hostDataCtrl;
      if (ctrl != null && !ctrl.isClosed) {
        ctrl.add(BleHostData(peerId: id, bytes: event.request.value));
      }
    });

    // Notification subscription = the peer is ready to receive frames.
    _notifyStateSub = _peripheral.characteristicNotifyStateChanged.listen((
      event,
    ) {
      final id = event.central.uuid.toString();
      _centrals[id] = event.central;
      if (!event.state ||
          event.characteristic.uuid != kBleNotifyCharacteristicUuid) {
        return;
      }
      final ctrl = _hostEventsCtrl;
      if (ctrl != null && !ctrl.isClosed) {
        ctrl.add(BleHostConnected(id));
      }
    });

    // Android-only: immediate disconnect events. iOS has no peripheral-side
    // disconnect callback — silent peers are reaped by the session
    // heartbeat instead (see m19-bluetooth-architecture.md §13).
    try {
      _connSub = _peripheral.connectionStateChanged.listen((event) {
        final id = event.central.uuid.toString();
        if (event.state == ConnectionState.disconnected) {
          _centrals.remove(id);
          final ctrl = _hostEventsCtrl;
          if (ctrl != null && !ctrl.isClosed) {
            ctrl.add(BleHostDisconnected(id));
          }
        }
      });
    } on UnsupportedError {
      // iOS: no peripheral-side disconnect stream.
    } catch (_) {
      // Ignore any platform quirk; heartbeat is the safety net.
    }

    // NOTE: the advertisement deliberately carries **no name**. The Android
    // plugin implements an advertised name by renaming the device itself
    // (BluetoothAdapter.setName), which (a) renames the user's phone to the
    // game name and (b) hangs forever on repeat hosts — when the name is
    // unchanged, ACTION_LOCAL_NAME_CHANGED never broadcasts and the
    // plugin's setName() await never completes, leaving "Starting…" stuck.
    // Joiners match on the service UUID and show the fallback game name
    // (see BleSessionDiscovery), so the custom name is cosmetic only.
    try {
      // Belt and braces: a platform hang must surface as a failure (the
      // lobby maps it to a friendly message), never an infinite spinner.
      await _peripheral
          .startAdvertising(
            Advertisement(serviceUUIDs: [kTurtleKingBleServiceUuid]),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const BleConnectException('Bluetooth advertising did not start.');
    }
    _hostRunning = true;
  }

  @override
  Future<void> stopAdvertising() async {
    if (_disposed) return;
    try {
      await _peripheral.stopAdvertising();
    } catch (_) {
      // Already stopped.
    }
  }

  @override
  Future<void> dropPeer(String peerId) async {
    if (_disposed) return;
    final central = _centrals.remove(peerId);
    if (central == null) return;
    try {
      await _peripheral.disconnect(central);
    } catch (_) {
      // Already gone or platform quirk; the heartbeat reaps silent peers.
    }
  }

  @override
  Future<void> stopHost() async {
    if (_disposed) return;
    _hostRunning = false;
    await stopAdvertising();
    try {
      await _peripheral.removeAllServices();
    } catch (_) {}
    _notifyChar = null;
    _centrals.clear();
    await _writeSub?.cancel();
    _writeSub = null;
    await _notifyStateSub?.cancel();
    _notifyStateSub = null;
    await _connSub?.cancel();
    _connSub = null;
    await _hostEventsCtrl?.close();
    _hostEventsCtrl = null;
    await _hostDataCtrl?.close();
    _hostDataCtrl = null;
  }

  @override
  Stream<BleHostEvent> get hostEvents =>
      _hostEventsCtrl?.stream ?? const Stream.empty();

  @override
  Stream<BleHostData> get hostData =>
      _hostDataCtrl?.stream ?? const Stream.empty();

  @override
  Future<int> hostNotifyChunkSize(String peerId) async {
    final central = _centrals[peerId];
    if (central == null) return 20;
    try {
      final size = await _peripheral.getMaximumNotifyLength(central);
      return size < 20 ? 20 : size;
    } catch (_) {
      return 20;
    }
  }

  @override
  Future<void> sendToHostPeer(String peerId, Uint8List bytes) async {
    final central = _centrals[peerId];
    final notifyChar = _notifyChar;
    if (central == null || notifyChar == null || _disposed) return;
    await _peripheral.notifyCharacteristic(central, notifyChar, value: bytes);
  }

  // -------------------------------------------------------------------
  // Client (central)
  // -------------------------------------------------------------------

  @override
  Future<void> startScan() async {
    if (_disposed || _scanning) return;
    _scanning = true;
    _discoveredCtrl ??= StreamController<BleDiscoveredPeer>.broadcast();
    _scanSub ??= _central.discovered.listen((event) {
      final id = event.peripheral.uuid.toString();
      _peripherals[id] = event.peripheral;
      final ctrl = _discoveredCtrl;
      if (ctrl == null || ctrl.isClosed) return;
      ctrl.add(
        BleDiscoveredPeer(
          id: id,
          displayName: event.advertisement.name?.trim().isNotEmpty == true
              ? event.advertisement.name!.trim()
              : kTurtleKingGameDisplayName,
          rssi: event.rssi,
          serviceUuids: event.advertisement.serviceUUIDs
              .map((u) => u.toString())
              .toSet(),
        ),
      );
    });
    try {
      await _central.startDiscovery(serviceUUIDs: [kTurtleKingBleServiceUuid]);
    } catch (e) {
      _scanning = false;
      rethrow;
    }
  }

  @override
  Future<void> stopScan() async {
    if (_disposed) return;
    _scanning = false;
    try {
      await _central.stopDiscovery();
    } catch (_) {}
  }

  @override
  Stream<BleDiscoveredPeer> get discovered {
    // Lazy: BleSessionDiscovery subscribes *before* startScan() is called,
    // so the controller must exist at subscription time or the listener
    // binds to `const Stream.empty()` and silently drops every discovered
    // host (the real-device "search finds nothing" bug). Same pattern as
    // the in-memory fake adapter.
    final ctrl = _discoveredCtrl ??=
        StreamController<BleDiscoveredPeer>.broadcast();
    return ctrl.stream;
  }

  @override
  Future<BleCentralConnection> connect(
    String peerId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_disposed) {
      throw const BleConnectException('Bluetooth is not available.');
    }
    // Resolve the peripheral: prefer the one from discovery; fall back to
    // already-connected peripherals so a reconnect (RemoteDriver) can
    // rejoin without a fresh scan.
    var peripheral = _peripherals[peerId];
    if (peripheral == null) {
      try {
        final connected = await _central.retrieveConnectedPeripherals();
        for (final p in connected) {
          if (p.uuid.toString() == peerId) {
            peripheral = p;
            _peripherals[peerId] = p;
            break;
          }
        }
      } catch (_) {}
    }
    if (peripheral == null) {
      throw BleConnectException('The host is no longer visible. Search again.');
    }
    // A provably non-null local: flow analysis cannot promote `peripheral`
    // inside the closures below because the variable was reassigned above.
    final target = peripheral;

    final connected = Completer<void>();
    final connectedSub = _central.connectionStateChanged.listen((event) {
      if (event.peripheral.uuid.toString() == peerId &&
          event.state == ConnectionState.connected &&
          !connected.isCompleted) {
        connected.complete();
      }
    });
    // The timeout must cover the native connect call too: on Android,
    // `connectGatt` can fail silently without ever firing its callback (a
    // stale scan result, a vanished peer, or an already-connected GATT), and
    // awaiting it without a deadline would leave the UI on "Connecting…"
    // forever. Race both futures against [timeout]; whichever completes
    // first is the connection signal.
    try {
      await Future.any([
        _central.connect(peripheral),
        connected.future,
      ]).timeout(timeout);
    } on TimeoutException {
      throw const BleConnectException('Connection timed out.');
    } catch (e) {
      throw const BleConnectException('Could not connect to the host.');
    } finally {
      connectedSub.cancel();
    }

    final List<GATTService> services;
    GATTCharacteristic? writeChar;
    GATTCharacteristic? notifyChar;
    try {
      services = await _central.discoverGATT(peripheral);
      for (final service in services) {
        if (service.uuid != kTurtleKingBleServiceUuid) continue;
        for (final c in service.characteristics) {
          if (c.uuid == kBleWriteCharacteristicUuid) writeChar = c;
          if (c.uuid == kBleNotifyCharacteristicUuid) notifyChar = c;
        }
      }
    } catch (_) {
      throw const BleConnectException('Could not read the host services.');
    }
    if (writeChar == null || notifyChar == null) {
      throw const BleConnectException(
        'The host does not speak this version of Turtle King.',
      );
    }
    // Final locals: flow analysis cannot promote the loop-assigned
    // variables inside the closures below.
    final writeTarget = writeChar;
    final notifyTarget = notifyChar;

    // Larger MTU on Android (iOS negotiates internally; Android 14+ is
    // auto-517). Best-effort.
    try {
      await _central.requestMTU(peripheral, mtu: 512);
    } catch (_) {}

    int writeChunkSize = 20;
    try {
      final size = await _central.getMaximumWriteLength(
        peripheral,
        type: GATTCharacteristicWriteType.withResponse,
      );
      writeChunkSize = size < 20 ? 20 : size;
    } catch (_) {}

    final incoming = StreamController<Uint8List>.broadcast();
    final disconnectedCtrl = StreamController<void>.broadcast();
    final notifiedSub = _central.characteristicNotified.listen((event) {
      if (event.peripheral.uuid.toString() != peerId) return;
      if (event.characteristic.uuid != kBleNotifyCharacteristicUuid) return;
      if (!incoming.isClosed) incoming.add(event.value);
    });
    final stateSub = _central.connectionStateChanged.listen((event) {
      if (event.peripheral.uuid.toString() != peerId) return;
      if (event.state == ConnectionState.disconnected &&
          !disconnectedCtrl.isClosed) {
        disconnectedCtrl.add(null);
      }
    });

    // Subscribe BEFORE the caller sends anything: the host admits the peer
    // on this subscription, so the first JOIN_REQUEST must arrive after it.
    try {
      await _central.setCharacteristicNotifyState(
        target,
        notifyTarget,
        state: true,
      );
    } catch (_) {
      await notifiedSub.cancel();
      await stateSub.cancel();
      await incoming.close();
      await disconnectedCtrl.close();
      throw const BleConnectException('Could not subscribe to the host.');
    }

    return _PluginCentralConnection(
      peripheral: target,
      characteristic: writeTarget,
      incoming: incoming,
      disconnectedCtrl: disconnectedCtrl,
      notifiedSub: notifiedSub,
      stateSub: stateSub,
      writeChunkSize: writeChunkSize,
      onSend: (bytes) => _central.writeCharacteristic(
        target,
        writeTarget,
        value: bytes,
        type: GATTCharacteristicWriteType.withResponse,
      ),
      onClose: () => _central.disconnect(target),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopScan();
    await stopHost();
  }
}

/// Client-side link returned by [PluginBleAdapter.connect].
class _PluginCentralConnection implements BleCentralConnection {
  _PluginCentralConnection({
    required this.peripheral,
    required this.characteristic,
    required this.incoming,
    required this.disconnectedCtrl,
    required this.notifiedSub,
    required this.stateSub,
    required this.writeChunkSize,
    required this.onSend,
    required this.onClose,
  });

  final Peripheral peripheral;
  final GATTCharacteristic characteristic;
  final StreamController<Uint8List> incoming;
  final StreamController<void> disconnectedCtrl;
  final StreamSubscription<GATTCharacteristicNotifiedEventArgs> notifiedSub;
  final StreamSubscription<PeripheralConnectionStateChangedEventArgs> stateSub;
  @override
  final int writeChunkSize;
  final Future<void> Function(Uint8List bytes) onSend;
  final Future<void> Function() onClose;

  bool _closed = false;

  @override
  Stream<Uint8List> get data => incoming.stream;

  @override
  Stream<void> get disconnected => disconnectedCtrl.stream;

  @override
  Future<void> send(Uint8List bytes) async {
    if (_closed) return;
    await onSend(bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await onClose();
    } catch (_) {}
    await notifiedSub.cancel();
    await stateSub.cancel();
    if (!incoming.isClosed) await incoming.close();
    if (!disconnectedCtrl.isClosed) await disconnectedCtrl.close();
  }
}
