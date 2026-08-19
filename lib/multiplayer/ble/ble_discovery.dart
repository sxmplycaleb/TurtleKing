import 'dart:async';

import '../transport.dart';
import 'ble_adapter.dart';
import 'plugin_ble_adapter.dart';

/// BLE session discovery: the host advertises a service UUID + game name,
/// and clients scan for it.
///
/// Implements the same [SessionDiscovery] interface as the LAN UDP beacon
/// discovery, so the join lobby treats Bluetooth like any other local
/// source of [DiscoveredSession]s. Two BLE-specific notes:
///
/// * The advertisement carries **no structured payload** (iOS advertises
///   name + service UUIDs only), so the session id and join code cannot
///   ride in it. The discovered session uses the peer's BLE identifier as
///   both [DiscoveredSession.hostAddress] and a placeholder session id —
///   the host's real id is adopted during the JOIN handshake, exactly like
///   a manual-IP LAN join. The join code remains the relay path's locator;
///   BLE sessions are joined from the nearby list.
/// * Advertising is started by the transport's [BleMultiplayerTransport]
///   (the GATT server must be published before advertising), so
///   [advertise] is a no-op kept for interface parity, and [stop] stops
///   advertising without tearing down the server (the host still needs to
///   deliver SESSION_END to already-joined clients).
class BleSessionDiscovery implements SessionDiscovery {
  BleSessionDiscovery({BleAdapter? adapter})
    : _adapter = adapter ?? PluginBleAdapter();

  final BleAdapter _adapter;
  StreamController<DiscoveredSession>? _discovered;
  StreamSubscription<BleDiscoveredPeer>? _sub;
  bool _scanning = false;
  bool _stopped = false;

  /// Peer ids already surfaced, so a platform that reports the same
  /// advertiser repeatedly (common on Android, which re-emits a device for
  /// every advertisement packet) cannot produce duplicate lobby entries.
  final Set<String> _surfacedPeerIds = {};

  @override
  Future<void> advertise({
    required String sessionId,
    required String displayName,
    required int port,
    String? joinCode,
  }) async {
    // Advertising was already started by BleMultiplayerTransport.startServer
    // (the GATT server must exist first). Nothing further to do.
  }

  @override
  Stream<DiscoveredSession> get discovered {
    if (_discovered == null) {
      // Broadcast: the lobby's live "Nearby" listener and any one-shot
      // resolver coexist (same pattern as UdpBeaconDiscovery).
      _discovered = StreamController<DiscoveredSession>.broadcast();
      _stopped = false;
      unawaited(_startScanning());
    }
    return _discovered!.stream;
  }

  Future<void> _startScanning() async {
    if (_scanning) return;
    _scanning = true;
    try {
      _sub = _adapter.discovered.listen(
        (peer) {
          final ctrl = _discovered;
          if (ctrl == null || ctrl.isClosed || _stopped) return;
          // Defense in depth: the client's scan is filtered to the Turtle
          // King service UUID, but a platform may still surface unrelated
          // advertisers. Only reject peers that positively advertise a
          // different service; peers with no reported UUIDs pass (some
          // platforms omit them even on a filtered scan).
          if (peer.serviceUuids.isNotEmpty &&
              !peer.serviceUuids.contains(kTurtleKingBleServiceUuidString)) {
            return;
          }
          if (!_surfacedPeerIds.add(peer.id)) return;
          ctrl.add(
            DiscoveredSession(
              // The peer's BLE identifier is the address to connect to;
              // the session id is a placeholder adopted on join.
              sessionId: peer.id,
              displayName: peer.displayName.trim().isNotEmpty
                  ? peer.displayName.trim()
                  : kTurtleKingGameDisplayName,
              hostAddress: peer.id,
              port: 0,
            ),
          );
        },
        onError: (_) {},
        onDone: () {},
      );
      await _adapter.startScan();
    } catch (e) {
      // Scanning failed (adapter off / permission / unsupported): discovery
      // is simply empty; the lobby shows a friendly state.
      _scanning = false;
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _scanning = false;
    await _sub?.cancel();
    _sub = null;
    await _adapter.stopScan();
    _surfacedPeerIds.clear();
    if (_discovered != null && !_discovered!.isClosed) {
      await _discovered!.close();
    }
    _discovered = null;
  }
}
