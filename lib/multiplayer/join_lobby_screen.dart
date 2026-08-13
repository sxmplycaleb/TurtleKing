import 'dart:async';

import 'package:flutter/material.dart';

import 'discovery.dart';
import 'join_code.dart';
import 'join_payload.dart';
import 'net_utils.dart';
import 'public_state.dart';
import 'qr_scan_screen.dart';
import 'relay_config.dart';
import 'relay_transport.dart';
import 'remote_driver.dart';
import 'remote_game_screen.dart';
import 'session.dart';
import 'transport.dart';

/// The join lobby: join a hosted session by scanning the host's QR code or
/// typing the 6-digit code.
///
/// The primary paths go through the **internet relay** — players do not
/// need to be on the same Wi-Fi network. LAN discovery and manual host-IP
/// entry still exist for development/testing, tucked behind a collapsed
/// "For Nerds" section.
///
/// Both [codeResolver] and [scanPayloadProvider] are injectable test seams
/// so widget tests never need a camera or a live relay.
class JoinLobbyScreen extends StatefulWidget {
  const JoinLobbyScreen({
    super.key,
    this.relayUrl = kDefaultRelayUrl,
    this.codeResolver,
    this.scanPayloadProvider,
  });

  /// The internet relay endpoint used for QR/code joins. Defaults to the
  /// build-time [kDefaultRelayUrl]; tests inject a local in-process relay.
  final String relayUrl;

  /// Resolves a typed 6-digit code to a typed result ([JoinCodeResolution]:
  /// found / notFound / unavailable). Defaults to the beacon-based
  /// [resolveJoinCode] against this screen's discovery stream, which checks
  /// already-discovered sessions first and fails fast instead of hanging on
  /// a long timeout.
  final Future<JoinCodeResolution> Function(String code, {Duration timeout})?
  codeResolver;

  /// Returns a raw scanned QR payload string, or null when the user cancels
  /// the scanner. Defaults to pushing [QrScanScreen].
  final Future<String?> Function()? scanPayloadProvider;

  @override
  State<JoinLobbyScreen> createState() => _JoinLobbyScreenState();
}

class _JoinLobbyScreenState extends State<JoinLobbyScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '$kDefaultGamePort',
  );

  /// LAN discovery (developer options only): started lazily when the
  /// developer section is expanded, never part of the normal join flow.
  UdpBeaconDiscovery? _discovery;
  StreamSubscription<DiscoveredSession>? _discoverySub;
  List<DiscoveredSession> _discovered = [];
  bool _devDiscoveryStarted = false;

  ClientSession? _client;
  StreamSubscription<ClientSessionEvent>? _clientSub;
  StreamSubscription<ClientGameplayEvent>? _gameplaySub;
  RemoteDriver? _remoteDriver;
  List<PublicPlayer> _roster = const [];
  String? _error;
  bool _joining = false;
  bool _inLobby = false;
  bool _navigatingToGame = false;

  @override
  void initState() {
    super.initState();
    // The join-code field must always start completely empty: no default
    // value, no restoration, no autofill (the TextField below also disables
    // Android autofill, which can otherwise pre-fill the digits).
    _codeController.clear();
    // Note: no UDP discovery starts here — the normal join path is the
    // internet relay (QR/code). LAN discovery only starts if the user
    // expands the "For Nerds" section.
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _discovery?.stop();
    _clientSub?.cancel();
    _gameplaySub?.cancel();
    _client?.dispose();
    _remoteDriver?.dispose();
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  /// Starts listening for LAN host beacons (developer options only).
  /// Failures (multicast blocked, no network) degrade silently to the
  /// manual host-IP path.
  void _ensureDiscovery() {
    if (_devDiscoveryStarted) return;
    _devDiscoveryStarted = true;
    final discovery = UdpBeaconDiscovery();
    _discovery = discovery;
    _discoverySub = discovery.discovered.listen(
      (session) {
        if (!mounted) return;
        setState(() {
          final alreadyKnown = _discovered.any(
            (d) =>
                d.sessionId == session.sessionId &&
                d.hostAddress == session.hostAddress,
          );
          if (!alreadyKnown) _discovered = [..._discovered, session];
        });
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  /// Scans the host's QR code, validates the payload strictly, and joins
  /// through the internet relay.
  Future<void> _joinFromQr() async {
    if (_joining) return; // one join attempt at a time
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name first.');
      return;
    }
    final String? payload;
    try {
      payload = await (widget.scanPayloadProvider ?? _scanWithCamera)();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Could not open the camera. Allow camera access in the app '
            'settings, or enter the 6-digit code instead.',
      );
      return;
    }
    if (!mounted || payload == null) return; // cancelled
    final parsed = JoinPayload.parse(payload);
    if (parsed == null) {
      setState(() => _error = 'Invalid QR code — not a Turtle King join code.');
      return;
    }
    // "Connecting…" starts the moment the payload is valid — before the
    // relay handshake — so a successful scan never looks like it did
    // nothing.
    setState(() {
      _joining = true;
      _error = null;
    });
    await _joinTo(relayUrl: parsed.relayUrl, sessionId: parsed.sessionId);
  }

  /// Resolves a typed 6-digit code against the internet relay, then joins
  /// the session.
  ///
  /// Resolution is fast and typed: the relay answers within a short window
  /// (default 4s), so a wrong code fails quickly with a clear message
  /// instead of hanging.
  Future<void> _joinFromCode() async {
    if (_joining) return; // one join attempt at a time
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name first.');
      return;
    }
    final code = _codeController.text.trim();
    if (!isValidJoinCode(code)) {
      setState(
        () => _error =
            'Invalid join code — enter the 6 digits from the '
            'host’s screen.',
      );
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    final relayUrl = widget.relayUrl;
    final resolver =
        widget.codeResolver ??
        (String code, {Duration timeout = const Duration(seconds: 4)}) async {
          if (relayUrl.isEmpty) {
            return const JoinCodeResolution.unavailable();
          }
          final result = await lookupJoinCodeOnRelay(
            relayUrl,
            code,
            timeout: timeout,
          );
          return switch (result) {
            RelayLookupFound(:final sessionId, :final displayName) =>
              JoinCodeResolution.found(
                DiscoveredSession(
                  sessionId: sessionId,
                  displayName: displayName,
                  hostAddress: relayUrl,
                  port: 0,
                  joinCode: code,
                  relayUrl: relayUrl,
                ),
              ),
            RelayLookupNotFound() => const JoinCodeResolution.notFound(),
            RelayLookupUnavailable() => const JoinCodeResolution.unavailable(),
          };
        };
    final JoinCodeResolution resolution;
    try {
      resolution = await resolver(code);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error =
            'Connection failed — could not look up that code. Make sure '
            'both phones have an internet connection.';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _joining = false);
    switch (resolution.status) {
      case JoinCodeResolveStatus.found:
        final session = resolution.session!;
        await _joinTo(
          relayUrl: session.relayUrl,
          hostAddress: session.relayUrl == null ? session.hostAddress : null,
          port: session.relayUrl == null ? session.port : null,
          sessionId: session.sessionId,
        );
      case JoinCodeResolveStatus.notFound:
        setState(
          () => _error =
              'No game found with this code. Check the code and that the '
              'host has started a game.',
        );
      case JoinCodeResolveStatus.unavailable:
        setState(
          () => _error =
              'Game unavailable — could not reach the game relay. Check '
              'your internet connection and try again.',
        );
    }
  }

  Future<String?> _scanWithCamera() {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanScreen()),
    );
  }

  Future<void> _join({DiscoveredSession? discovered}) async {
    if (_joining) return; // one join attempt at a time
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name first.');
      return;
    }

    if (discovered != null && discovered.relayUrl != null) {
      await _joinTo(
        relayUrl: discovered.relayUrl,
        sessionId: discovered.sessionId,
      );
      return;
    }
    final String hostAddress;
    final int port;
    final String sessionId;
    if (discovered != null) {
      hostAddress = discovered.hostAddress;
      port = discovered.port;
      sessionId = discovered.sessionId;
    } else {
      hostAddress = _ipController.text.trim();
      if (!isValidIpv4(hostAddress)) {
        setState(
          () => _error = 'Enter a valid IPv4 address (e.g. 192.168.1.20).',
        );
        return;
      }
      final portText = _portController.text.trim();
      if (!isValidPort(portText)) {
        setState(() => _error = 'Enter a valid port (1–65535).');
        return;
      }
      port = int.parse(portText);
      // A manual joiner cannot know the host's session id; the host accepts
      // the join and the client adopts the real id from the first message.
      sessionId = 'manual-join';
    }

    await _joinTo(hostAddress: hostAddress, port: port, sessionId: sessionId);
  }

  /// Core join: connects through [ClientSession] and enters the lobby,
  /// either through the internet relay ([relayUrl]) or a direct LAN address
  /// (developer options).
  ///
  /// Every failure — transport, timeout, protocol, or an unexpected error —
  /// is contained and surfaced as a concise user-facing message. Raw socket
  /// exceptions and stack traces never reach the user.
  Future<void> _joinTo({
    String? relayUrl,
    String? hostAddress,
    int? port,
    required String sessionId,
  }) async {
    final name = _nameController.text.trim();
    setState(() {
      _joining = true;
      _error = null;
    });

    final ClientSession client;
    final JoinResult result;
    try {
      await _client?.dispose();
      client = ClientSession(sessionId: sessionId, playerName: name);
      _client = client;
      result = relayUrl != null
          ? await client.joinRelay(relayUrl: relayUrl)
          : await client.join(
              hostAddress: hostAddress ?? '',
              port: port ?? kDefaultGamePort,
            );
    } catch (_) {
      // Defensive: any unexpected error (e.g. a stale session state) must
      // surface as a message, never as a silent hang or an unhandled crash.
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Connection failed — check your internet connection.';
      });
      return;
    }
    if (!mounted) return;

    setState(() => _joining = false);
    if (result.isAccepted) {
      _roster = result.roster ?? const [];
      _clientSub = client.events.listen(_onClientEvent);
      // When the host starts the game, this client becomes a remote player:
      // hand the session to a RemoteDriver and enter the game screen.
      final driver = RemoteDriver(
        sessionId: client.sessionId,
        playerName: name,
        relayUrl: relayUrl,
      );
      _remoteDriver = driver;
      driver.attach(client);
      _gameplaySub = client.gameplayEvents.listen((event) {
        if (event.type == ClientGameplayEventType.gameStarted &&
            !_navigatingToGame) {
          _navigatingToGame = true;
          _openRemoteGame(driver);
        }
      });
      setState(() => _inLobby = true);
    } else {
      setState(
        () => _error = _joinFailureMessage(result, relay: relayUrl != null),
      );
      await client.dispose();
      if (mounted) _client = null;
    }
  }

  /// Maps a typed join outcome to a concise, user-facing message. Host-side
  /// rejection reasons (name taken, session full, game already started,
  /// session ended) are already written for the user and pass through
  /// unchanged; transport failures are never exposed raw.
  ///
  /// [relay] distinguishes internet joins (the normal flow — failures point
  /// at the internet connection) from the LAN developer fallback (where
  /// same-network wording is accurate).
  String _joinFailureMessage(JoinResult result, {bool relay = false}) {
    switch (result.outcome) {
      case JoinOutcome.rejected:
        return result.reason ?? 'The host rejected the join.';
      case JoinOutcome.connectionFailed:
        return relay
            ? 'Connection failed — check your internet connection and try '
                  'again.'
            : 'Connection failed — make sure both phones are on the same '
                  'Wi-Fi network.';
      case JoinOutcome.timedOut:
        return relay
            ? 'Connection timed out — the relay may be busy or your '
                  'connection is slow. Try again.'
            : 'Connection timed out — the host may be out of range or the '
                  'network is slow. Try again.';
      case JoinOutcome.protocolError:
        return 'Could not join — your app versions may be incompatible.';
      case JoinOutcome.sessionEnded:
        return 'The session has ended.';
      case JoinOutcome.accepted:
        return 'Could not join the session.';
    }
  }

  void _onClientEvent(ClientSessionEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case ClientSessionEventType.joined:
        case ClientSessionEventType.rosterUpdated:
          if (event.roster != null) _roster = event.roster!;
        case ClientSessionEventType.connectionLost:
          _error = 'Connection to the host was lost.';
          _inLobby = false;
          _roster = const [];
        case ClientSessionEventType.sessionEnded:
          _error = 'The host ended the session.';
          _inLobby = false;
          _roster = const [];
        case ClientSessionEventType.rejected:
          _error = event.reason ?? 'The host rejected the join.';
          _inLobby = false;
      }
    });
  }

  Future<void> _leave() async {
    await _client?.disconnect();
    if (!mounted) return;
    setState(() {
      _inLobby = false;
      _roster = const [];
      _error = null;
    });
  }

  Future<void> _openRemoteGame(RemoteDriver driver) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteGameScreen(controller: driver),
      ),
    );
    if (!mounted) return;
    setState(() => _navigatingToGame = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Join Game')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _inLobby ? _lobbyView(theme) : _joinView(theme),
        ),
      ),
    );
  }

  Widget _joinView(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          // Primary path A: scan the host's QR code.
          FilledButton.icon(
            onPressed: _joining ? null : _joinFromQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR Code'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: theme.textTheme.bodySmall),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          // Primary path B: type the 6-digit code from the host's screen.
          Text(
            'Enter the code from the host’s screen',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  // Never let the platform autofill these digits (Android
                  // autofill can otherwise pre-fill a fresh screen from a
                  // previously saved value).
                  autofillHints: const <String>[],
                  enableSuggestions: false,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Join code',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _joining ? null : _joinFromCode,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(_joining ? 'Connecting…' : 'Join'),
                ),
              ),
            ],
          ),
          if (_joining) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 24),
          // LAN discovery and manual host-IP entry are development/testing
          // fallbacks only — normal players join by QR or 6-digit code over
          // the internet relay, with no same-Wi-Fi requirement.
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('For Nerds'),
            subtitle: const Text('Advanced options for curious turtles.'),
            leading: const Icon(Icons.bug_report_outlined),
            onExpansionChanged: (expanded) {
              if (expanded) _ensureDiscovery();
            },
            children: [
              const SizedBox(height: 4),
              Text('Nearby games (LAN)', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_discovered.isEmpty)
                Text(
                  'LAN discovery is off for normal play. If your network '
                  'blocks it, use the manual setup below.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                for (final session in _discovered) ...[
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.sports_esports),
                      title: Text(session.displayName),
                      subtitle: Text('${session.hostAddress}:${session.port}'),
                      trailing: FilledButton(
                        onPressed: _joining
                            ? null
                            : () => _join(discovered: session),
                        child: const Text('Join'),
                      ),
                    ),
                  ),
                ],
              const SizedBox(height: 12),
              // Debug/fallback: manual host IP. Never part of the primary
              // flow.
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Manual setup (host IP)'),
                leading: const Icon(Icons.settings_ethernet),
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _ipController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Host IPv4',
                            hintText: '192.168.1.20',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _joining ? null : () => _join(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_joining ? 'Connecting…' : 'Join by IP'),
                  ),
                ],
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            // Visually obvious and actionable: a tinted banner with an icon,
            // not a bare line of red text.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lobbyView(ThemeData theme) {
    final client = _client;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Joined as ${client?.self?.name ?? ''}',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Players (${_roster.length})',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final player in _roster) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(backgroundColor: Color(player.color)),
              title: Text(player.name),
              trailing: player.id == client?.self?.id
                  ? Text('you', style: theme.textTheme.bodySmall)
                  : null,
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.logout),
            label: const Text('Leave'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
