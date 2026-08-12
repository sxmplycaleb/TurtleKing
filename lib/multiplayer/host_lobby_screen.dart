import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../game_state.dart';
import '../player.dart';
import 'join_code.dart';
import 'join_payload.dart';
import 'public_state.dart';
import 'relay_config.dart';
import 'relay_transport.dart';
import 'remote_game_controller.dart';
import 'remote_game_screen.dart';
import 'session.dart';

/// The host lobby: enter a name, create a session on the internet relay,
/// and watch the roster fill as clients join by QR or 6-digit code.
///
/// Session/lobby concerns only. The players do **not** need to be on the
/// same Wi-Fi network: the host registers the session with the relay and
/// every client connects to the relay, so any mix of Wi-Fi/mobile-data
/// works (see docs/multiplayer/m18-architecture.md §8).
class HostLobbyScreen extends StatefulWidget {
  const HostLobbyScreen({
    super.key,
    this.joinCodeGenerator = generateJoinCode,
    this.relayUrl = kDefaultRelayUrl,
  });

  /// Test seam: how the 6-digit join code is drawn (deterministic in tests).
  final String Function() joinCodeGenerator;

  /// The internet relay endpoint this session is hosted on. Defaults to the
  /// build-time [kDefaultRelayUrl]; tests inject a local in-process relay.
  final String relayUrl;

  @override
  State<HostLobbyScreen> createState() => _HostLobbyScreenState();
}

class _HostLobbyScreenState extends State<HostLobbyScreen> {
  final TextEditingController _nameController = TextEditingController(
    text: 'Host',
  );
  final TextEditingController _gameNameController = TextEditingController(
    text: 'Turtle King Game',
  );

  HostSession? _session;
  StreamSubscription<HostSessionEvent>? _eventSub;
  List<PublicPlayer> _roster = const [];
  String _gameName = '';
  String _joinCode = '';
  String? _qrPayload;
  String? _error;
  bool _starting = false;
  bool _copied = false;

  @override
  void dispose() {
    _eventSub?.cancel();
    _session?.dispose();
    _nameController.dispose();
    _gameNameController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name first.');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });

    final relayUrl = widget.relayUrl;
    if (relayUrl.isEmpty) {
      setState(() {
        _starting = false;
        _error =
            'Multiplayer relay is not configured for this build. Build the '
            'app with --dart-define=RELAY_URL=wss://your-relay and try '
            'again.';
      });
      return;
    }
    final session = HostSession(
      sessionId: generateSessionId(),
      transport: RelayMultiplayerTransport(relayUrl: relayUrl),
      joinCode: widget.joinCodeGenerator(),
    );
    try {
      await session.start(
        displayName: _gameNameController.text.trim(),
        hostName: name,
        port: 0,
      );
    } catch (_) {
      await session.dispose();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error =
            'Could not start the session. Check your internet connection '
            'and that the game relay is reachable.';
      });
      return;
    }
    if (!mounted) {
      await session.dispose();
      return;
    }
    _eventSub = session.events.listen(_onEvent);
    final code = session.joinCode ?? '';
    setState(() {
      _session = session;
      _roster = session.roster;
      _gameName = _gameNameController.text.trim().isEmpty
          ? 'Turtle King Game'
          : _gameNameController.text.trim();
      _joinCode = code;
      _starting = false;
      // The QR identifies the session on the internet relay — no LAN IP.
      _qrPayload = code.isEmpty
          ? null
          : JoinPayload(
              sessionId: session.sessionId,
              joinCode: code,
              relayUrl: relayUrl,
            ).encode();
    });
  }

  void _onEvent(HostSessionEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case HostSessionEventType.started:
        case HostSessionEventType.clientJoined:
        case HostSessionEventType.clientLeft:
        case HostSessionEventType.rosterUpdated:
        case HostSessionEventType.gameStarted:
        case HostSessionEventType.actionAccepted:
        case HostSessionEventType.actionRejected:
          if (event.roster != null) _roster = event.roster!;
        case HostSessionEventType.sessionEnded:
          _session = null;
          _roster = const [];
          _joinCode = '';
          _qrPayload = null;
          _copied = false;
      }
    });
  }

  Future<void> _copyCode() async {
    if (_joinCode.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _joinCode));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _stop() async {
    final session = _session;
    if (session == null) return;
    await session.stop();
  }

  /// Builds the authoritative [GameState] from the joined roster and starts
  /// the remote game. The host's own device plays through the same remote
  /// game screen as the clients, acting against the authoritative state.
  Future<void> _startGame() async {
    final session = _session;
    if (session == null || _roster.length < 2) return;
    final players = [
      for (final p in _roster)
        Player(id: p.id, name: p.name, color: Color(p.color)),
    ];
    final hostPlayer = players.firstWhere(
      (p) => p.id == kHostPlayerId,
      orElse: () => players.first,
    );
    final game = GameState(players: players, random: Random.secure());
    final controller = HostRemoteController(
      hostSession: session,
      game: game,
      hostPlayer: hostPlayer,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteGameScreen(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Host Game')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _session == null ? _formView(theme) : _hostingView(theme),
        ),
      ),
    );
  }

  Widget _formView(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'Start a session and other players on the same Wi-Fi network '
            'can find it and join.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _gameNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Game name',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _starting ? null : _start,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: theme.textTheme.titleMedium,
            ),
            child: Text(_starting ? 'Starting…' : 'Start Session'),
          ),
        ],
      ),
    );
  }

  Widget _hostingView(ThemeData theme) {
    final session = _session!;
    final qrPayload = _qrPayload;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Hosting “$_gameName”',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Session ${session.sessionId}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Join Game',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // The large 6-digit code: the primary way a friend joins.
          SelectableText(
            formatJoinCode(_joinCode),
            textAlign: TextAlign.center,
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'On another phone: Join Game → Enter code',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Works over Wi-Fi or mobile data — no need to be on the same '
            'network.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: OutlinedButton.icon(
              onPressed: _joinCode.isEmpty ? null : _copyCode,
              icon: Icon(_copied ? Icons.check : Icons.copy),
              label: Text(_copied ? 'Code copied' : 'Copy code'),
            ),
          ),
          const SizedBox(height: 12),
          // The QR code: the zero-typing join path. Its payload identifies
          // the session on the internet relay — no LAN address (see
          // [JoinPayload]).
          if (qrPayload != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: qrPayload,
                  version: QrVersions.auto,
                  size: 220,
                  semanticsLabel: 'Join QR code for $_gameName',
                ),
              ),
            )
          else
            Text(
              'Waiting for the relay…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 24),
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
              trailing: player.id == kHostPlayerId
                  ? Text('you', style: theme.textTheme.bodySmall)
                  : null,
            ),
          ],
          const SizedBox(height: 24),
          if (_roster.length >= 2)
            FilledButton.icon(
              onPressed: _startGame,
              icon: const Icon(Icons.play_arrow),
              label: Text('Start Game (${_roster.length} players)'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: theme.textTheme.titleMedium,
              ),
            )
          else
            Text(
              'Waiting for at least one more player to join…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop),
            label: const Text('End Session'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
