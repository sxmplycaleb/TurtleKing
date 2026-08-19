import 'dart:async';

import 'protocol.dart';
import 'remote_game_controller.dart';
import 'remote_game_view.dart';
import 'session.dart';
import 'transport.dart';

/// The client's connection/play state, surfaced to the remote game UI.
enum RemoteGameStatus {
  /// Connecting to the host / joining the session.
  connecting,

  /// Joined and in the lobby (game not started yet).
  inLobby,

  /// In a started game with a live connection.
  playing,

  /// The connection dropped and a bounded reconnect is in progress.
  reconnecting,

  /// Reconnected; asking the host for the authoritative state.
  resyncing,

  /// The host ended the session.
  sessionEnded,

  /// The connection was lost and reconnect attempts were exhausted.
  connectionFailed,

  /// No gameplay connection exists (nothing was joined).
  idle,
}

/// A state/status fact emitted by [RemoteDriver] to its UI.
class RemoteGameEvent {
  const RemoteGameEvent(this.status, {this.message, this.rejection});

  final RemoteGameStatus status;

  /// Human-readable context (reconnect attempt, host reason, etc.).
  final String? message;

  /// Set when a requested action was rejected by the host.
  final String? rejection;
}

/// The client side of a remote game.
///
/// Owns the [ClientSession] connection and exposes exactly the five
/// gameplay operations the UI needs — the same surface as `GameDriver` —
/// but sends ACTION_REQUEST instead of executing rules. Gameplay validity is
/// decided **only** by the host: this class never touches game rules, never
/// builds a `GameState`, and renders exclusively from [RemoteGameView]
/// (public state + the client's own authorized card).
class RemoteDriver implements RemoteGameController {
  RemoteDriver({
    required this.sessionId,
    required this.playerName,
    this.relayUrl,
    this.reconnectAttempts = 5,
    this.reconnectBaseDelay = const Duration(milliseconds: 400),
    this.rejoinTransport,
    this.rejoinHostAddress,
  });

  final String sessionId;
  final String playerName;

  /// The internet relay endpoint this session lives on, when joined through
  /// the relay (null for LAN joins). Reconnects use it instead of a host
  /// address, so a client whose internet blips can rejoin without any LAN
  /// dependency.
  final String? relayUrl;

  /// The transport a rejoin must use, for transports whose connection is not
  /// a plain `hostAddress:port` LAN join (e.g. Bluetooth, where the address
  /// is a BLE peer identifier and the port is 0). Null means the default TCP
  /// LAN transport, whose rejoin target is `hostAddress` + a non-zero port.
  final MultiplayerTransport? rejoinTransport;

  /// The address to reconnect to when [rejoinTransport] is set (for BLE,
  /// the peer identifier). Falls back to the last `join()` address.
  final String? rejoinHostAddress;

  /// Maximum reconnect attempts before giving up.
  final int reconnectAttempts;

  /// Delay of the first reconnect attempt; each retry doubles it.
  final Duration reconnectBaseDelay;

  final StreamController<RemoteGameEvent> _events =
      StreamController<RemoteGameEvent>.broadcast();

  ClientSession? _session;
  StreamSubscription<ClientSessionEvent>? _lobbySub;
  StreamSubscription<ClientGameplayEvent>? _gameplaySub;
  RemoteGameView? _view;
  RemoteGameStatus _status = RemoteGameStatus.idle;
  bool _gameStarted = false;
  bool _disposed = false;

  /// The host address last connected to (used for LAN reconnects).
  String? _hostAddress;
  int _port = 0;
  bool _sessionEndedPermanently = false;

  /// The current sanitized view (empty until a game starts).
  @override
  RemoteGameView get view {
    final current = _view;
    if (current != null) return current;
    return RemoteGameView.empty(
      players: _session?.roster ?? const [],
      selfPlayerId: _session?.self?.id ?? '',
    );
  }

  /// The client's own player id once joined.
  String? get selfPlayerId => _session?.self?.id;

  bool get isConnected =>
      _session != null && _session!.isConnected && !_sessionEndedPermanently;

  @override
  bool get isHost => false;

  @override
  Stream<RemoteGameEvent> get events => _events.stream;

  @override
  RemoteGameStatus get status => _status;

  void _setStatus(
    RemoteGameStatus status, {
    String? message,
    String? rejection,
  }) {
    _status = status;
    if (_events.isClosed) return;
    _events.add(
      RemoteGameEvent(status, message: message, rejection: rejection),
    );
  }

  /// Adopts an already-joined [session] (used by the join lobby, which
  /// connects/joins before gameplay starts). The driver then renders the
  /// session's gameplay events and sends actions through it.
  void attach(ClientSession session) {
    if (_disposed) return;
    _session = session;
    _hostAddress ??= '';
    _attachSession(session);
    _setStatus(RemoteGameStatus.inLobby);
  }

  /// Connects to the host and joins with [playerName] over a direct LAN
  /// connection. Completes with the join outcome; never throws.
  Future<JoinResult> join({
    required String hostAddress,
    int port = kDefaultGamePort,
    Duration connectTimeout = const Duration(seconds: 5),
  }) async {
    if (_disposed) {
      return const JoinResult.failure(
        JoinOutcome.connectionFailed,
        'The session was disposed.',
      );
    }
    _hostAddress = hostAddress;
    _port = port;
    return _joinSession(
      (session) => session.join(
        hostAddress: hostAddress,
        port: port,
        connectTimeout: connectTimeout,
      ),
    );
  }

  /// Connects to the host through the internet relay and joins with
  /// [playerName]. Completes with the join outcome; never throws.
  ///
  /// The default timeout matches [ClientSession.joinRelay]: a public relay
  /// can be mid-wake (Render's free tier sleeps when idle), and the session
  /// layer runs the single controlled retry for transient failures.
  Future<JoinResult> joinRelay({
    required String relayUrl,
    Duration connectTimeout = const Duration(seconds: 30),
  }) async {
    if (_disposed) {
      return const JoinResult.failure(
        JoinOutcome.connectionFailed,
        'The session was disposed.',
      );
    }
    return _joinSession(
      (session) =>
          session.joinRelay(relayUrl: relayUrl, connectTimeout: connectTimeout),
    );
  }

  Future<JoinResult> _joinSession(
    Future<JoinResult> Function(ClientSession session) join,
  ) async {
    _setStatus(RemoteGameStatus.connecting);
    final session = ClientSession(sessionId: sessionId, playerName: playerName);
    _session = session;
    _attachSession(session);
    final result = await join(session);
    if (!result.isAccepted) {
      if (result.outcome == JoinOutcome.sessionEnded) {
        _sessionEndedPermanently = true;
        _setStatus(RemoteGameStatus.sessionEnded, message: result.reason);
      } else {
        _setStatus(RemoteGameStatus.connectionFailed, message: result.reason);
      }
      return result;
    }
    _setStatus(RemoteGameStatus.inLobby);
    return result;
  }

  void _attachSession(ClientSession session) {
    _lobbySub?.cancel();
    _gameplaySub?.cancel();
    _lobbySub = session.events.listen(_onSessionEvent);
    _gameplaySub = session.gameplayEvents.listen(_onGameplayEvent);
  }

  void _onSessionEvent(ClientSessionEvent event) {
    switch (event.type) {
      case ClientSessionEventType.sessionEnded:
        _sessionEndedPermanently = true;
        _setStatus(RemoteGameStatus.sessionEnded, message: event.reason);
      case ClientSessionEventType.connectionLost:
        if (!_sessionEndedPermanently) _beginReconnect();
      case ClientSessionEventType.joined:
      case ClientSessionEventType.rejected:
      case ClientSessionEventType.rosterUpdated:
        break;
    }
  }

  void _onGameplayEvent(ClientGameplayEvent event) {
    switch (event.type) {
      case ClientGameplayEventType.gameStarted:
        _gameStarted = true;
        if (event.publicState != null) {
          _view = RemoteGameView(
            publicState: event.publicState!,
            selfPlayerId: _session?.self?.id ?? '',
          );
        }
        _setStatus(RemoteGameStatus.playing);
      case ClientGameplayEventType.stateUpdated:
        if (event.publicState != null) {
          _view = RemoteGameView(
            publicState: event.publicState!,
            selfPlayerId: _session?.self?.id ?? '',
            myCard: _view?.myCard,
          );
        }
        // The view changed — notify the UI so it re-renders (the screen
        // rebuilds only on RemoteGameEvent; without this, the first action
        // would appear to do nothing even though the host applied it and
        // the new state arrived).
        _setStatus(RemoteGameStatus.playing);
      case ClientGameplayEventType.privateUpdated:
        // Only ever applied for this player (session layer filters it).
        if (event.privateState != null) {
          _view = RemoteGameView(
            publicState:
                _view?.publicState ??
                RemoteGameView.empty(
                  players: _session?.roster ?? const [],
                  selfPlayerId: _session?.self?.id ?? '',
                ).publicState,
            selfPlayerId: _session?.self?.id ?? '',
            myCard: event.privateState!.card,
          );
        }
        // The client's own card changed — re-render (see stateUpdated).
        _setStatus(RemoteGameStatus.playing);
      case ClientGameplayEventType.resynced:
        if (event.publicState != null) {
          _view = RemoteGameView(
            publicState: event.publicState!,
            selfPlayerId: _session?.self?.id ?? '',
            myCard: _view?.myCard,
          );
        }
        _setStatus(RemoteGameStatus.playing);
      case ClientGameplayEventType.actionAccepted:
        break;
      case ClientGameplayEventType.actionRejected:
        _setStatus(
          RemoteGameStatus.playing,
          rejection: event.reason ?? 'The host rejected that action.',
        );
    }
  }

  // -------------------------------------------------------------------
  // Gameplay operations (the GameDriver surface, remote edition)
  // -------------------------------------------------------------------

  @override
  void revealCurrentPlayer() => _request(GameAction.revealCurrentPlayer);

  @override
  void passToNextPlayer() => _request(GameAction.passToNextPlayer);

  @override
  void holdOut() => _request(GameAction.holdOut);

  @override
  void callYamada() => _request(GameAction.callYamada);

  @override
  void startNextRound() => _request(GameAction.startNextRound);

  void _request(GameAction action) {
    if (!isConnected || !_gameStarted) return;
    _session?.requestAction(action);
  }

  // -------------------------------------------------------------------
  // Reconnection
  // -------------------------------------------------------------------

  /// Bounded reconnect: retries [join] against the remembered host up to
  /// [reconnectAttempts] times with doubling backoff, then reports failure.
  /// On success, requests a resync so stale client state is replaced by the
  /// host's authoritative snapshot.
  Future<void> _beginReconnect() async {
    if (_disposed || _sessionEndedPermanently) return;
    _setStatus(RemoteGameStatus.reconnecting);
    if (!_hasRejoinTarget) {
      _setStatus(RemoteGameStatus.connectionFailed);
      return;
    }
    for (var attempt = 1; attempt <= reconnectAttempts; attempt++) {
      await Future<void>.delayed(reconnectBaseDelay * (1 << (attempt - 1)));
      if (_disposed || _sessionEndedPermanently) return;
      final session = ClientSession(
        sessionId: sessionId,
        playerName: playerName,
        transport: rejoinTransport,
      );
      _session = session;
      _attachSession(session);
      final result = await _tryRejoin(session);
      if (result.isAccepted) {
        _setStatus(
          RemoteGameStatus.resyncing,
          message: 'Reconnected. Syncing with the host…',
        );
        // Ask for the authoritative state; the response arrives via
        // gameplayEvents and flips status back to playing.
        session.requestResync();
        if (_gameStarted) {
          // Rebuild the view from the fresh roster immediately so the UI
          // shows the lobby/game without stale data.
          _view = RemoteGameView.empty(
            players: session.roster,
            selfPlayerId: result.self?.id ?? '',
          );
        }
        return;
      }
      if (result.outcome == JoinOutcome.sessionEnded) {
        _sessionEndedPermanently = true;
        _setStatus(RemoteGameStatus.sessionEnded, message: result.reason);
        return;
      }
    }
    _setStatus(RemoteGameStatus.connectionFailed);
  }

  /// The address to reconnect to for non-relay sessions (BLE peer id when a
  /// rejoin transport is set, otherwise the last LAN join address).
  String? get _rejoinAddress => rejoinHostAddress ?? _hostAddress;

  /// Whether a rejoin target exists: a relay URL for internet sessions, a
  /// remembered host address + port for LAN sessions, or a rejoin transport
  /// + address (Bluetooth, where the port is 0 and never used).
  bool get _hasRejoinTarget {
    if (relayUrl != null) return true;
    if (rejoinTransport != null) return _rejoinAddress != null;
    return _hostAddress != null && _port != 0;
  }

  /// Rejoins the session through the transport it was originally joined
  /// with: the internet relay when [relayUrl] is set, the rejoin transport
  /// (Bluetooth) when provided, otherwise the LAN host address. Never throws.
  Future<JoinResult> _tryRejoin(ClientSession session) {
    final relay = relayUrl;
    if (relay != null) {
      return session.joinRelay(
        relayUrl: relay,
        connectTimeout: reconnectBaseDelay * 2,
      );
    }
    final address = _rejoinAddress;
    if (address == null) {
      return Future.value(
        const JoinResult.failure(
          JoinOutcome.connectionFailed,
          'No host address to reconnect to.',
        ),
      );
    }
    return session.join(
      hostAddress: address,
      port: _port,
      connectTimeout: reconnectBaseDelay * 2,
    );
  }

  /// Explicitly reconnects after a [RemoteGameStatus.connectionFailed] state
  /// (e.g. the user retries). Returns true when the session is live again.
  @override
  Future<bool> reconnect() async {
    if (_disposed) return false;
    _sessionEndedPermanently = false;
    if (!_hasRejoinTarget) return false;
    _setStatus(RemoteGameStatus.reconnecting);
    final session = ClientSession(
      sessionId: sessionId,
      playerName: playerName,
      transport: rejoinTransport,
    );
    _session = session;
    _attachSession(session);
    final result = await _tryRejoin(session);
    if (result.isAccepted) {
      if (_gameStarted) session.requestResync();
      return true;
    }
    _setStatus(RemoteGameStatus.connectionFailed, message: result.reason);
    return false;
  }

  /// Leaves the session cleanly (sends DISCONNECT) and releases resources.
  @override
  Future<void> leave() async {
    if (_disposed) return;
    await _session?.disconnect();
    await dispose();
  }

  /// Leaves the session and releases resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sessionEndedPermanently = true;
    await _lobbySub?.cancel();
    await _gameplaySub?.cancel();
    _lobbySub = null;
    _gameplaySub = null;
    await _session?.dispose();
    _session = null;
    if (!_events.isClosed) {
      await _events.close();
    }
  }
}
