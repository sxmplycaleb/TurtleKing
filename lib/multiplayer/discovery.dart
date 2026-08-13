import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'join_code.dart';
import 'json_util.dart';
import 'platform_multicast.dart';
import 'transport.dart';

/// The multicast group the built-in discovery beacons use by default.
///
/// Chosen from the administratively-scoped multicast range (239.0.0.0/8) so
/// beacons never leave the local network. Some routers/APs filter multicast;
/// the manual host-IP join path exists precisely for those networks.
final InternetAddress kBeaconGroup = InternetAddress('239.255.77.77');

/// The beacon protocol version.
const int kBeaconProtocolVersion = 1;

/// The beacon message type name.
const String kBeaconType = 'BEACON';

/// Encodes one discovery beacon payload.
///
/// Purely data — the beacon carries only what a lobby entry needs: the
/// session identity, a display name, the TCP port to connect to, and the
/// human-friendly 6-digit join code (so clients can resolve a typed code to
/// this session without scanning the QR). No player, card, or game data.
String encodeBeacon({
  required String sessionId,
  required String displayName,
  required int port,
  String? joinCode,
}) {
  return canonicalJson({
    'v': kBeaconProtocolVersion,
    'type': kBeaconType,
    'sessionId': sessionId,
    'displayName': displayName,
    'port': port,
    'code': ?joinCode,
  });
}

/// Parses and validates one beacon payload into session metadata, or returns
/// null when the datagram is malformed, unrelated, or from an unknown
/// protocol version. Never throws.
DiscoveredSession? parseBeacon(String raw, InternetAddress source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  try {
    final map = requireMap(decoded, 'beacon');
    final version = requireInt(map['v'], 'beacon version');
    if (version != kBeaconProtocolVersion) return null;
    if (requireString(map['type'], 'beacon type') != kBeaconType) return null;
    final sessionId = requireString(map['sessionId'], 'sessionId');
    if (sessionId.isEmpty) return null;
    final displayName = requireString(map['displayName'], 'displayName');
    if (displayName.isEmpty) return null;
    final port = requireInt(map['port'], 'port');
    if (port < 1 || port > 65535) return null;
    // The join code is optional on the wire (older hosts omit it); when
    // present it must be a valid 6-digit code or the beacon is rejected.
    final rawCode = map['code'];
    final joinCode = rawCode == null ? null : requireString(rawCode, 'code');
    if (joinCode != null && !isValidJoinCode(joinCode)) return null;
    return DiscoveredSession(
      sessionId: sessionId,
      displayName: displayName,
      hostAddress: source.address,
      port: port,
      joinCode: joinCode,
    );
  } on MultiplayerProtocolException {
    return null;
  }
}

/// The built-in LAN discovery: small UDP beacons on a local multicast group.
///
/// Implements both sides of [SessionDiscovery]:
///
/// * **Host** — [advertise] periodically broadcasts a beacon carrying the
///   session id, display name, and TCP port (interval injectable for tests).
/// * **Client** — [discovered] listens for beacons and emits validated
///   [DiscoveredSession]s, ignoring malformed or unrelated datagrams.
///
/// This is the deliberate replacement for the originally-planned
/// `multicast_dns` package, which is query-only (it can advertise nothing);
/// see docs/multiplayer/m18-architecture.md §5.3.
class UdpBeaconDiscovery implements SessionDiscovery {
  UdpBeaconDiscovery({
    InternetAddress? beaconTarget,
    this.discoveryPort = kDiscoveryPort,
    this.beaconInterval = const Duration(seconds: 2),
  }) : _beaconTarget = beaconTarget ?? kBeaconGroup;

  final InternetAddress _beaconTarget;

  /// The UDP port beacons are broadcast to / listened on.
  final int discoveryPort;

  /// How often the host re-broadcasts its beacon.
  final Duration beaconInterval;

  RawDatagramSocket? _sender;
  RawDatagramSocket? _listener;
  StreamSubscription<RawSocketEvent>? _listenSub;
  Timer? _beaconTimer;
  StreamController<DiscoveredSession>? _discovered;
  bool _advertising = false;
  bool _stopped = false;

  @override
  Future<void> advertise({
    required String sessionId,
    required String displayName,
    required int port,
    String? joinCode,
  }) async {
    if (_advertising) return;
    _advertising = true;
    _sender ??= await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final beacon = utf8.encode(
      encodeBeacon(
        sessionId: sessionId,
        displayName: displayName,
        port: port,
        joinCode: joinCode,
      ),
    );
    void broadcast() {
      if (_stopped || _sender == null) return;
      try {
        _sender!.send(beacon, _beaconTarget, discoveryPort);
      } catch (_) {
        // A transient send failure must never interrupt hosting.
      }
    }

    broadcast();
    _beaconTimer = Timer.periodic(beaconInterval, (_) => broadcast());
  }

  @override
  Stream<DiscoveredSession> get discovered {
    if (_discovered == null) {
      // Broadcast: the lobby keeps a long-lived listener for the "Nearby
      // games" list while a one-shot code resolution (see
      // [resolveJoinCode]) may attach a second listener at the same time.
      _discovered = StreamController<DiscoveredSession>.broadcast();
      unawaited(_startListening());
    }
    return _discovered!.stream;
  }

  Future<void> _startListening() async {
    if (_listener != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _listener = socket;
      final target = _beaconTarget;
      if (target.isMulticast) {
        socket.joinMulticast(target);
        // Best-effort on Android: without the multicast lock some devices
        // drop multicast packets. No-op where the platform channel is
        // unavailable (tests, desktop).
        await MulticastLock.acquire();
      }
      _listenSub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final raw = utf8.decode(datagram.data, allowMalformed: true);
        final session = parseBeacon(raw, datagram.address);
        if (session != null && !_stopped) {
          _discovered?.add(session);
        }
      });
    } catch (_) {
      // Binding/listening failed (e.g. no network or port in use): discovery
      // degrades to manual host-IP entry, which is always available.
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _advertising = false;
    await _listenSub?.cancel();
    _listenSub = null;
    _listener?.close();
    _listener = null;
    _sender?.close();
    _sender = null;
    await MulticastLock.release();
    if (_discovered != null && !_discovered!.isClosed) {
      await _discovered!.close();
    }
    _discovered = null;
  }
}

/// The outcome of resolving a typed 6-digit join code.
enum JoinCodeResolveStatus {
  /// A discovered session advertising this code was found.
  found,

  /// No session advertising this code appeared within the resolution
  /// window. The code is either wrong or the host's beacon has not been
  /// heard yet — the caller should tell the user the code is invalid rather
  /// than waiting indefinitely.
  notFound,

  /// Discovery itself is not available (no stream, stream error, or the
  /// stream closed), so no code can be resolved at all. The caller should
  /// point the user at the QR or manual host-IP path instead.
  unavailable,
}

/// The result of [resolveJoinCode]: either a found session, or a typed
/// failure so the join UI can distinguish "no session with that code"
/// (fast — after checking everything already discovered) from "discovery
/// is not working on this network at all".
class JoinCodeResolution {
  const JoinCodeResolution.found(this.session)
    : status = JoinCodeResolveStatus.found;

  const JoinCodeResolution.notFound()
    : status = JoinCodeResolveStatus.notFound,
      session = null;

  const JoinCodeResolution.unavailable()
    : status = JoinCodeResolveStatus.unavailable,
      session = null;

  final JoinCodeResolveStatus status;

  /// The matching session, when [status] is [JoinCodeResolveStatus.found].
  final DiscoveredSession? session;

  bool get isFound => status == JoinCodeResolveStatus.found;
}

/// Resolves a 6-digit [code] to a discovered session.
///
/// The resolution is deliberately **fast and typed**:
///
/// 1. A syntactically invalid code resolves immediately to
///    [JoinCodeResolveStatus.notFound].
/// 2. Any session already seen (via [alreadySeen], typically the lobby's
///    live "Nearby games" list) is matched immediately — a successful join
///    never waits for a beacon cycle or the full timeout.
/// 3. Otherwise the code is matched against new beacons on [discovered]
///    for at most [timeout] (short, e.g. 4s). A session found mid-window
///    completes immediately.
/// 4. If the window elapses without a match the result is
///    [JoinCodeResolveStatus.notFound] (wrong code / host not advertising).
/// 5. If the stream errors or closes (discovery unavailable), the result
///    is [JoinCodeResolveStatus.unavailable].
///
/// Never throws, and the internal subscription/timer are always cancelled.
/// The code is a locator, not an identifier: if several hosts advertise
/// the same code (a LAN collision), the first matching session wins and
/// the join itself is still validated by the normal HostSession/
/// ClientSession protocol checks.
Future<JoinCodeResolution> resolveJoinCode(
  Stream<DiscoveredSession> discovered,
  String code, {
  Iterable<DiscoveredSession> alreadySeen = const [],
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (!isValidJoinCode(code)) {
    return const JoinCodeResolution.notFound();
  }
  final match = code.trim();

  // Fast path: the code is already on screen from a previous beacon — no
  // need to wait for the next beacon cycle or the timeout.
  for (final session in alreadySeen) {
    if (session.joinCode == match) {
      return JoinCodeResolution.found(session);
    }
  }

  final completer = Completer<JoinCodeResolution>();
  StreamSubscription<DiscoveredSession>? sub;
  sub = discovered.listen(
    (session) {
      if (session.joinCode == match && !completer.isCompleted) {
        completer.complete(JoinCodeResolution.found(session));
      }
    },
    onError: (_) {
      if (!completer.isCompleted) {
        completer.complete(const JoinCodeResolution.unavailable());
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.complete(const JoinCodeResolution.unavailable());
      }
    },
  );
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.complete(const JoinCodeResolution.notFound());
    }
  });
  try {
    return await completer.future;
  } finally {
    timer.cancel();
    await sub.cancel();
  }
}
