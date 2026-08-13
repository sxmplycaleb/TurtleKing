/// Transport and discovery interfaces for the future LAN implementation
/// (see docs/multiplayer/m18-architecture.md §5–§6).
///
/// M18.2 defines the contract only — no sockets, no mDNS, no Bluetooth.
/// The eventual implementation will back these with `dart:io` TCP sockets
/// and the `multicast_dns` package (M18.3/M18.4). Interfaces are defined in
/// terms of complete JSON messages (as produced by [MessageCodec]) so the
/// session layer above them stays transport-agnostic.
library;

import 'protocol_codec.dart';

/// A bidirectional JSON message channel to exactly one peer.
///
/// Messages are complete, codec-encoded protocol strings ([MessageCodec]);
/// the transport never interprets them.
abstract class TransportConnection {
  /// Incoming complete messages from the peer, in arrival order.
  Stream<String> get incoming;

  /// Sends one complete encoded message. Completes when handed off to the
  /// transport; never blocks gameplay.
  Future<void> send(String message);

  /// Whether the connection is currently open.
  bool get isOpen;

  /// Closes the connection (idempotent).
  Future<void> close();
}

/// The default TCP port for Turtle King LAN sessions.
///
/// Uncommon port chosen to avoid clashing with well-known services; the
/// manual-IP join path defaults to it. Tests may bind port 0 (ephemeral).
const int kDefaultGamePort = 41321;

/// The UDP port used by the built-in LAN discovery beacons.
const int kDiscoveryPort = 5354;

/// Accepts incoming connections (host side of a session).
abstract class TransportServer {
  /// Newly accepted connections, one per client.
  Stream<TransportConnection> get connections;

  /// The local port the server is bound to (useful when bound to port 0).
  int get port;

  /// Stops accepting and closes every accepted connection (idempotent).
  Future<void> close();
}

/// The transport facade the session layer will use.
///
/// The LAN implementation in tcp_transport.dart backs [startServer] with a
/// `dart:io` `ServerSocket` and [connect] with a client `Socket`, addressed
/// by the host address discovered via the built-in UDP beacons or manual
/// entry.
abstract class MultiplayerTransport {
  /// Hosts a session, returning a server that accepts client connections.
  ///
  /// [port] is the TCP port to bind; pass 0 for an ephemeral port (tests).
  /// The LAN implementation ignores [joinCode]/[displayName]; the relay
  /// implementation uses them to register the session (and its 6-digit join
  /// code) with the relay.
  Future<TransportServer> startServer({
    required String sessionId,
    int port = kDefaultGamePort,
    String? joinCode,
    String? displayName,
  });

  /// Connects to a hosted session at [hostAddress] (e.g. `192.168.1.20`).
  Future<TransportConnection> connect({
    required String hostAddress,
    required String sessionId,
    int port = kDefaultGamePort,
    Duration connectTimeout = const Duration(seconds: 5),
  });

  /// Releases all resources held by this transport (idempotent).
  Future<void> dispose();
}

/// A session discovered on the local network or resolved via the relay.
class DiscoveredSession {
  const DiscoveredSession({
    required this.sessionId,
    required this.displayName,
    required this.hostAddress,
    this.port = kDefaultGamePort,
    this.joinCode,
    this.relayUrl,
  });

  final String sessionId;

  /// Human-readable session name shown in the lobby.
  final String displayName;

  /// Host address to pass to [MultiplayerTransport.connect] (LAN mode). For
  /// relay mode this is the relay endpoint and [relayUrl] is set instead.
  final String hostAddress;

  /// The TCP port the host's session server is bound to (LAN mode).
  final int port;

  /// The host's 6-digit join code, when the host advertises one. Used to
  /// resolve a typed code to this session (see [resolveJoinCode]); never an
  /// authentication credential.
  final String? joinCode;

  /// The internet relay endpoint this session lives on, when the session is
  /// reachable through the relay rather than a LAN address. When set, the
  /// client joins via [ClientSession.joinRelay] and no LAN address is used.
  final String? relayUrl;
}

/// LAN session discovery.
///
/// M18.2 kept this as a stub; M18.3 implements it in discovery.dart with the
/// built-in UDP beacon protocol (see the architecture doc §5.3 for why the
/// originally-planned `multicast_dns` package could not be used — it is
/// query-only and cannot advertise a host service).
abstract class SessionDiscovery {
  /// Starts advertising [displayName] for [sessionId] so other devices can
  /// find the host.
  ///
  /// [port] is the TCP port clients should connect to (the beacon carries it
  /// so clients can find the session without assuming a fixed port);
  /// [joinCode] is the host's 6-digit code, broadcast so clients can resolve
  /// a typed code to this session without scanning.
  Future<void> advertise({
    required String sessionId,
    required String displayName,
    required int port,
    String? joinCode,
  });

  /// Stream of sessions discovered on the local network.
  Stream<DiscoveredSession> get discovered;

  /// Stops advertising/browsing (idempotent).
  Future<void> stop();
}
