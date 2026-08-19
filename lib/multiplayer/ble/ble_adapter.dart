import 'dart:typed_data';

/// Canonical (128-bit) string form of the Turtle King BLE service UUID.
///
/// Single source of truth for the advertised service UUID: the host
/// advertises it, the client's scan filter matches it, and the discovery
/// layer verifies a scanned peer actually carries it (defense in depth — a
/// platform may report unrelated advertisers even when asked to filter).
/// `0000fc00-0000-1000-8000-00805f9b34fb` is the Bluetooth base-UUID
/// expansion of the 16-bit vendor-range UUID `FC00`.
const String kTurtleKingBleServiceUuidString =
    '0000fc00-0000-1000-8000-00805f9b34fb';

/// Display name shown for a discovered host when its advertisement carries
/// no usable name (most Android phones advertise no name; the advertisement
/// carries the service UUID only — see PluginBleAdapter.startHost).
const String kTurtleKingGameDisplayName = 'Turtle King game';

/// The runtime state of the device's Bluetooth adapter, as surfaced to the
/// UI. Deliberately coarse — the UI only needs to distinguish "works",
/// "needs permission", "needs Bluetooth on", and "no Bluetooth here".
enum BleAdapterStatus {
  /// The adapter state is not known yet (no query has happened).
  unknown,

  /// This device has no usable Bluetooth LE stack.
  unsupported,

  /// Bluetooth permissions have not been granted.
  unauthorized,

  /// Bluetooth is present but powered off.
  poweredOff,

  /// Bluetooth is on and the app may use it.
  poweredOn,
}

/// One Turtle King host discovered by a scan.
///
/// Carries only what a lobby entry needs: an opaque peer identifier (used as
/// the [DiscoveredSession.hostAddress] for [BleMultiplayerTransport.connect])
/// and the advertised game name. No session id, join code, player, card, or
/// game data is ever advertised (the session id is adopted from the host
/// during the normal JOIN handshake, exactly like a manual-IP LAN join).
class BleDiscoveredPeer {
  const BleDiscoveredPeer({
    required this.id,
    required this.displayName,
    required this.rssi,
    this.serviceUuids = const <String>{},
  });

  /// Stable identifier of the advertising device (its BLE peer UUID).
  final String id;

  /// The advertised game name (truncated to advertisement size limits).
  final String displayName;

  /// Received signal strength, dBm (informational only).
  final int rssi;

  /// Canonical 128-bit UUID strings the peer advertises. Empty when the
  /// platform did not report any (some platforms omit them even on a
  /// filtered scan); the discovery layer only rejects peers that
  /// positively advertise a different service.
  final Set<String> serviceUuids;
}

/// A host-side lifecycle fact about one connected peer.
sealed class BleHostEvent {
  const BleHostEvent();
}

/// A peer (client) established a GATT connection and subscribed.
class BleHostConnected extends BleHostEvent {
  const BleHostConnected(this.peerId);

  final String peerId;
}

/// A peer disconnected (Android reports this; on iOS the session heartbeat
/// covers silent peers instead).
class BleHostDisconnected extends BleHostEvent {
  const BleHostDisconnected(this.peerId);

  final String peerId;
}

/// One inbound chunk from a connected peer on the host side.
class BleHostData {
  const BleHostData({required this.peerId, required this.bytes});

  final String peerId;
  final Uint8List bytes;
}

/// A connected, usable data link from a client (central) to a host.
///
/// Chunks flow in both directions; the framing/reassembly happens one layer
/// up in the BLE transport, so this interface is bytes only.
abstract class BleCentralConnection {
  /// Inbound chunks from the host, in arrival order.
  Stream<Uint8List> get data;

  /// Emits once when the link drops (host lost, disconnect, timeout).
  Stream<void> get disconnected;

  /// The largest single write the negotiated link accepts (bytes).
  int get writeChunkSize;

  /// Sends one chunk to the host.
  Future<void> send(Uint8List bytes);

  /// Closes the link (idempotent).
  Future<void> close();
}

/// The seam between the transport/discovery layers and the Bluetooth LE
/// platform.
///
/// The plugin-backed [PluginBleAdapter] implements this over
/// `bluetooth_low_energy` (host = peripheral, client = central); tests
/// inject an in-memory [FakeBleAdapter] that simulates a room of phones, so
/// the whole session layer runs over real framing without any hardware.
///
/// **Privacy contract:** nothing in this interface ever carries game
/// payloads that the platform would log or expose — frames are opaque
/// bytes, and the advertisement carries only a name + service UUID.
abstract class BleAdapter {
  /// Current adapter state.
  BleAdapterStatus get status;

  /// Ensures the app has Bluetooth permission (Android runtime prompt;
  /// on iOS the OS prompts on first use). Returns false when permission
  /// is permanently denied. Never throws for platform quirks.
  Future<bool> ensureAuthorized();

  /// Opens the app's system settings (escape hatch after denial).
  Future<void> showAppSettings();

  // ---------------------------------------------------------------------
  // Host (peripheral) side
  // ---------------------------------------------------------------------

  /// Publishes the Turtle King GATT service and starts advertising
  /// [displayName]. Idempotent per session; the GATT server must exist
  /// before advertising begins.
  Future<void> startHost({required String displayName});

  /// Stops advertising (peers can no longer discover the session) without
  /// tearing down the GATT server. Idempotent.
  Future<void> stopAdvertising();

  /// Stops advertising, removes the GATT service, and releases host
  /// resources. Idempotent.
  Future<void> stopHost();

  /// Host-side lifecycle events (peer connected / disconnected).
  Stream<BleHostEvent> get hostEvents;

  /// Host-side inbound bytes from any connected peer.
  Stream<BleHostData> get hostData;

  /// The largest notification payload (bytes) the host may send to
  /// [peerId] in one chunk.
  Future<int> hostNotifyChunkSize(String peerId);

  /// Sends one chunk to [peerId] as a GATT notification.
  Future<void> sendToHostPeer(String peerId, Uint8List bytes);

  /// Disconnects one connected peer. Used when the host drops a
  /// protocol-violating client so the peer's link is actually torn down
  /// (the client sees its disconnect stream fire). Idempotent; a peer that
  /// is already gone is a no-op.
  Future<void> dropPeer(String peerId);

  // ---------------------------------------------------------------------
  // Client (central) side
  // ---------------------------------------------------------------------

  /// Starts scanning for Turtle King hosts. Idempotent.
  Future<void> startScan();

  /// Stops scanning. Idempotent.
  Future<void> stopScan();

  /// Discovered hosts while scanning.
  Stream<BleDiscoveredPeer> get discovered;

  /// Connects to the host identified by [peerId] and returns a usable data
  /// link. Throws a typed exception on timeout/permission/connect failure
  /// (the session layer maps it to a friendly join error).
  Future<BleCentralConnection> connect(String peerId, {Duration timeout});

  /// Releases every resource held by this adapter (idempotent).
  Future<void> dispose();
}
