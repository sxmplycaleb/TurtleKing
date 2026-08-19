import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart' show Color;

import '../game_state.dart';
import '../player_colors.dart';
import 'errors.dart';
import 'private_state.dart';
import 'protocol.dart';
import 'protocol_codec.dart';
import 'public_state.dart';
import 'relay_transport.dart';
import 'tcp_transport.dart';
import 'transport.dart';

/// Generates a reasonably-unique session id for a new host session.
String generateSessionId() {
  final random = Random.secure();
  final suffix = random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return 'tk-$suffix';
}

/// The host's own roster entry id.
const String kHostPlayerId = 'host';

// ---------------------------------------------------------------------------
// Events (shared vocabulary for the lobby UI)
// ---------------------------------------------------------------------------

/// A lobby-relevant fact emitted by a [HostSession].
enum HostSessionEventType {
  started,
  clientJoined,
  clientLeft,
  rosterUpdated,
  gameStarted,
  actionAccepted,
  actionRejected,
  sessionEnded,
}

class HostSessionEvent {
  const HostSessionEvent(this.type, {this.playerId, this.roster, this.reason});

  final HostSessionEventType type;

  /// The player the event concerns (join/leave), if any.
  final String? playerId;

  /// The current full roster at the time of the event.
  final List<PublicPlayer>? roster;

  /// Human-readable context (e.g. session-end reason).
  final String? reason;
}

/// A lobby-relevant fact emitted by a [ClientSession].
enum ClientSessionEventType {
  joined,
  rejected,
  rosterUpdated,
  connectionLost,
  sessionEnded,
}

class ClientSessionEvent {
  const ClientSessionEvent(
    this.type, {
    this.roster,
    this.playerId,
    this.reason,
  });

  final ClientSessionEventType type;
  final List<PublicPlayer>? roster;
  final String? playerId;
  final String? reason;
}

/// A gameplay-relevant fact emitted by a [ClientSession] (M18.4).
enum ClientGameplayEventType {
  gameStarted,
  stateUpdated,
  privateUpdated,
  actionAccepted,
  actionRejected,
  resynced,
}

/// Payload of one [ClientGameplayEvent] — always typed, never raw JSON.
class ClientGameplayEvent {
  const ClientGameplayEvent(
    this.type, {
    this.publicState,
    this.privateState,
    this.action,
    this.requestSeq = -1,
    this.stateSeq = -1,
    this.reason,
  });

  final ClientGameplayEventType type;
  final PublicStateView? publicState;
  final PrivateStateView? privateState;
  final GameAction? action;
  final int requestSeq;
  final int stateSeq;
  final String? reason;
}

/// The outcome of a client's join attempt.
enum JoinOutcome {
  accepted,
  rejected,
  connectionFailed,
  timedOut,
  protocolError,
  sessionEnded,
}

/// The result of [ClientSession.join].
class JoinResult {
  const JoinResult.accepted(this.self, this.roster)
    : outcome = JoinOutcome.accepted,
      reason = null;

  const JoinResult.rejected(this.reason)
    : outcome = JoinOutcome.rejected,
      self = null,
      roster = null;

  const JoinResult.failure(this.outcome, this.reason)
    : self = null,
      roster = null;

  final JoinOutcome outcome;

  /// The identity the host assigned (when accepted).
  final PublicPlayer? self;

  /// The roster at join time (when accepted).
  final List<PublicPlayer>? roster;

  /// Why the join failed or was rejected.
  final String? reason;

  bool get isAccepted => outcome == JoinOutcome.accepted;
}

/// One connected client on the host, with its liveness bookkeeping.
class _HostClient {
  _HostClient(this.connection, this.playerId, this.playerName);

  final TransportConnection connection;
  final String playerId;
  final String playerName;

  /// Updated whenever any message arrives from this client.
  DateTime lastSeen = DateTime.now();
}

// ---------------------------------------------------------------------------
// Host
// ---------------------------------------------------------------------------

/// The host-authoritative LAN session: owns the roster and the TCP server,
/// validates joins, broadcasts roster updates, and tracks client liveness.
///
/// The host runs no gameplay here — this layer handles only session and
/// lobby concerns. Gameplay (M18.4) will build on the same [GameDriver]
/// seam. Nothing about authoritative state, hands, cards, or saves enters
/// this layer.
class HostSession {
  HostSession({
    required this.sessionId,
    MultiplayerTransport? transport,
    this.discovery,
    this.joinCode,
    this.playerLimit = PlayerColors.maxPlayers,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.heartbeatTimeout = const Duration(seconds: 15),
  }) : _transport = transport ?? TcpMultiplayerTransport();

  final String sessionId;
  final int playerLimit;

  /// The human-friendly 6-digit join code, broadcast with the discovery
  /// beacon so clients can resolve a typed code to this session. A locator
  /// only — never used for authentication (see [join_code.dart]).
  final String? joinCode;

  /// How often the host sends heartbeats and sweeps for dead clients.
  final Duration heartbeatInterval;

  /// How long a client may go silent before the host considers it dead.
  final Duration heartbeatTimeout;

  final MultiplayerTransport _transport;

  /// The discovery mechanism used to advertise this session (optional; the
  /// manual host-IP path never needs it).
  final SessionDiscovery? discovery;
  final MessageCodec _codec = const MessageCodec();
  // Broadcast: two consumers co-listen — the host lobby (roster/status
  // updates) and the HostRemoteController while the host plays its own
  // game. A single-subscription controller throws "Stream has already been
  // listened to" on the second listen (real-device host-game-start crash);
  // the client session was already broadcast for the same reason.
  final StreamController<HostSessionEvent> _events =
      StreamController<HostSessionEvent>.broadcast();
  final Map<String, _HostClient> _clients = {};

  TransportServer? _server;
  StreamSubscription<TransportConnection>? _acceptSub;
  Timer? _heartbeatTimer;
  List<PublicPlayer> _roster = const [];
  int _nextPlayerNumber = 1;
  int _seq = 0;
  bool _running = false;
  bool _stopped = false;

  /// Every player identity ever assigned, keyed by player id, kept across
  /// disconnects so a reconnecting player reclaims their original identity
  /// instead of becoming a duplicate (M18.4 reconnection).
  final Map<String, PublicPlayer> _knownPlayers = {};

  // -------------------------------------------------------------------------
  // Gameplay (M18.4): the host owns the authoritative GameState and routes
  // client actions through it. Nothing about hidden cards, the deck, or the
  // save document ever leaves this class.
  // -------------------------------------------------------------------------

  GameState? _game;

  /// Monotonic version of the public state broadcast to clients.
  int _stateSeq = 0;

  /// Whether a game has started (locks the roster and the join flow).
  bool _gameStarted = false;

  /// Highest ACTION_REQUEST seq seen per player id — rejects stale and
  /// duplicated actions after reconnects.
  final Map<String, int> _clientActionSeq = {};

  /// Lobby events (started, joins/leaves, roster updates, session end).
  Stream<HostSessionEvent> get events => _events.stream;

  /// The current roster (host first, then clients in join order).
  List<PublicPlayer> get roster => List.unmodifiable(_roster);

  bool get isRunning => _running && !_stopped;

  /// The port clients should connect to (valid after [start]).
  int? get port => _server?.port;

  /// Binds the TCP server, adds the host as player 0, advertises the
  /// session (when discovery is provided), and starts accepting clients.
  Future<TransportServer> start({
    required String displayName,
    required String hostName,
    int port = kDefaultGamePort,
  }) async {
    if (_running) throw StateError('session already started');
    final server = await _transport.startServer(
      sessionId: sessionId,
      port: port,
      joinCode: joinCode,
      displayName: displayName.trim().isEmpty
          ? 'Turtle King Game'
          : displayName.trim(),
    );
    _server = server;
    _roster = [
      PublicPlayer(
        id: kHostPlayerId,
        name: hostName.trim().isEmpty ? 'Host' : hostName.trim(),
        color: PlayerColors.palette[0].toARGB32(),
      ),
    ];
    _running = true;
    _acceptSub = server.connections.listen(_onConnection);
    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) => _onHeartbeatTick(),
    );
    if (discovery != null) {
      await discovery!.advertise(
        sessionId: sessionId,
        displayName: displayName.trim().isEmpty
            ? 'Turtle King Game'
            : displayName.trim(),
        port: server.port,
        joinCode: joinCode,
      );
    }
    _emit(HostSessionEventType.started);
    return server;
  }

  /// Ends the session: tells every client, closes all connections and the
  /// server, stops advertising and heartbeats. Idempotent.
  Future<void> stop({String reason = 'host-left'}) async {
    if (_stopped) return;
    _stopped = true;
    _running = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _acceptSub?.cancel();
    _acceptSub = null;
    try {
      await discovery?.stop();
    } catch (_) {
      // Advertising failure must not block a clean shutdown.
    }
    final end = SessionEndMessage(
      seq: _nextSeq(),
      sessionId: sessionId,
      reason: reason,
    );
    for (final client in List.of(_clients.values)) {
      try {
        await client.connection.send(_codec.encode(end));
      } catch (_) {}
      await client.connection.close();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    _emit(HostSessionEventType.sessionEnded, reason: reason);
    if (!_events.isClosed) {
      unawaited(_events.close());
    }
  }

  /// Releases transport resources without notifying clients (used on
  /// dispose paths where the session is being torn down anyway).
  Future<void> dispose() async {
    await stop(reason: 'host-disposed');
  }

  // -------------------------------------------------------------------------
  // Connection handling
  // -------------------------------------------------------------------------

  void _onConnection(TransportConnection connection) {
    connection.incoming.listen(
      (raw) => _onMessage(connection, raw),
      onDone: () => _onConnectionClosed(connection),
      onError: (_) => _onConnectionClosed(connection),
    );
  }

  void _onMessage(TransportConnection connection, String raw) {
    final MultiplayerMessage message;
    try {
      message = _codec.decode(raw);
    } on MultiplayerProtocolException {
      // A peer that does not speak our protocol cannot join; closing it
      // also guarantees one malformed client cannot harm the server.
      _closeQuietly(connection);
      return;
    }
    // The join request itself may carry any session id: a client joining by
    // manual host IP cannot know this session's id, and the TCP connection
    // already binds it to this session. Every other message must carry the
    // host's session id or the connection is rejected.
    if (message.sessionId != sessionId && message is! JoinRequestMessage) {
      _closeQuietly(connection);
      return;
    }
    switch (message) {
      case JoinRequestMessage(:final playerName):
        _handleJoin(connection, playerName);
      case DisconnectMessage(:final playerId):
        _handleDisconnect(connection, playerId);
      case HeartbeatMessage():
        _noteSeen(connection);
      case ActionRequestMessage():
        _handleActionRequest(connection, message);
      case ResyncRequestMessage():
        _handleResync(connection, message);
      default:
        // Host-only or future message types are ignored.
        break;
    }
  }

  void _handleJoin(TransportConnection connection, String playerName) {
    // Idempotency: a connection that already joined sends nothing more.
    if (_clients.values.any((c) => c.connection == connection)) return;

    final name = playerName.trim();

    // Reconnection (M18.4): a player who lost their connection may rejoin
    // with the same name and reclaim their original identity — same player
    // id and color — instead of becoming a duplicate. Only honored when the
    // player is not currently connected.
    PublicPlayer? reconnecting;
    for (final p in _knownPlayers.values) {
      if (p.name.toLowerCase() == name.toLowerCase() &&
          !_clients.containsKey(p.id)) {
        reconnecting = p;
        break;
      }
    }

    String? rejectReason;
    if (name.isEmpty) {
      rejectReason = 'Enter a name to join.';
    } else if (reconnecting == null &&
        _roster.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      rejectReason = 'That name is already taken.';
    } else if (_roster.length >= playerLimit) {
      rejectReason = 'The session is full ($playerLimit players).';
    } else if (_stopped) {
      rejectReason = 'The session has ended.';
    } else if (reconnecting == null && _gameStarted) {
      rejectReason = 'The game has already started.';
    }

    if (rejectReason != null) {
      _send(
        connection,
        JoinRejectMessage(
          seq: _nextSeq(),
          sessionId: sessionId,
          reason: rejectReason,
        ),
      );
      return;
    }

    final PublicPlayer player;
    if (reconnecting != null) {
      player = reconnecting;
      _clients[player.id] = _HostClient(connection, player.id, player.name);
      // A lobby-stage reconnect (game not started) must put the player back
      // into the visible roster; during gameplay the identity stays reserved
      // and the roster never lost it.
      if (!_roster.any((p) => p.id == player.id)) {
        _roster = [..._roster, player];
      }
    } else {
      final usedColors = _roster.map((p) => Color(p.color)).toSet();
      final playerId = 'mp-${_nextPlayerNumber++}';
      player = PublicPlayer(
        id: playerId,
        name: name,
        color: PlayerColors.nextAvailable(usedColors).toARGB32(),
      );
      _clients[playerId] = _HostClient(connection, playerId, name);
      _roster = [..._roster, player];
      _knownPlayers[playerId] = player;
    }

    _send(
      connection,
      JoinAcceptMessage(
        seq: _nextSeq(),
        sessionId: sessionId,
        playerId: player.id,
        color: player.color,
        roster: _roster,
      ),
    );
    _broadcastRoster();
    _emit(
      HostSessionEventType.clientJoined,
      playerId: player.id,
      roster: _roster,
    );
    _emit(HostSessionEventType.rosterUpdated, roster: _roster);

    // A reconnecting player must immediately recover the authoritative
    // state and their own visible card.
    if (reconnecting != null && _game != null) {
      _handleResync(
        connection,
        ResyncRequestMessage(
          seq: 0,
          sessionId: sessionId,
          playerId: player.id,
          lastStateSeq: -1,
        ),
      );
    }
  }

  void _handleDisconnect(TransportConnection connection, String playerId) {
    final client = _clients[playerId];
    if (client == null) return;
    _removeClient(client, notify: true);
  }

  void _onConnectionClosed(TransportConnection connection) {
    final client = _clients.values
        .where((c) => c.connection == connection)
        .firstOrNull;
    if (client != null) {
      _removeClient(client, notify: true);
    }
    _closeQuietly(connection);
  }

  void _removeClient(_HostClient client, {required bool notify}) {
    _clients.remove(client.playerId);
    if (_gameStarted) {
      // During gameplay the identity stays reserved so the player can
      // reconnect; the roster (and everyone's view of it) is unchanged.
    } else {
      _roster = [
        for (final p in _roster)
          if (p.id != client.playerId) p,
      ];
    }
    if (notify) {
      _broadcastRoster();
      _emit(
        HostSessionEventType.clientLeft,
        playerId: client.playerId,
        roster: _roster,
      );
      _emit(HostSessionEventType.rosterUpdated, roster: _roster);
    }
  }

  void _onHeartbeatTick() {
    final now = DateTime.now();
    for (final client in List.of(_clients.values)) {
      _sendRaw(
        client.connection,
        _codec.encode(HeartbeatMessage(seq: _nextSeq(), sessionId: sessionId)),
      );
      if (now.difference(client.lastSeen) > heartbeatTimeout) {
        _removeClient(client, notify: true);
        _closeQuietly(client.connection);
      }
    }
  }

  void _noteSeen(TransportConnection connection) {
    final client = _clients.values
        .where((c) => c.connection == connection)
        .firstOrNull;
    if (client != null) client.lastSeen = DateTime.now();
  }

  void _broadcastRoster() {
    final message = RosterUpdateMessage(
      seq: _nextSeq(),
      sessionId: sessionId,
      roster: _roster,
    );
    final raw = _codec.encode(message);
    for (final client in _clients.values) {
      _sendRaw(client.connection, raw);
    }
  }

  // -------------------------------------------------------------------------
  // Gameplay (M18.4)
  // -------------------------------------------------------------------------

  /// The authoritative game the host runs (null until [startGame]).
  GameState? get game => _game;

  /// Whether a game has started.
  bool get gameStarted => _gameStarted;

  /// The current public-state version (increments per accepted action).
  int get stateSeq => _stateSeq;

  /// The player id the host's own device plays as.
  String get hostPlayerId => kHostPlayerId;

  /// Locks the roster and starts a game with [game] as the sole authority.
  ///
  /// The roster must already match [game]'s players (the host starts a game
  /// built from the joined roster). Every connected client receives
  /// [GameStartMessage] plus its own [PrivateUpdateMessage]; the public state
  /// is broadcast as the first [StateUpdateMessage].
  Future<void> startGame(GameState game) async {
    if (_gameStarted) throw StateError('game already started');
    _game = game;
    _gameStarted = true;
    _stateSeq = 0;
    final publicView = PublicStateView.fromGame(game);

    final start = GameStartMessage(
      seq: _nextSeq(),
      sessionId: sessionId,
      gameId: sessionId,
      publicState: publicView,
    );
    for (final client in _clients.values) {
      _sendRaw(client.connection, _codec.encode(start));
    }

    // Broadcast state and deliver each player their own visible card.
    _broadcastPublicState(publicView);
    for (final client in _clients.values) {
      _sendPrivateCard(client);
    }
    _emit(HostSessionEventType.gameStarted, roster: _roster);
  }

  /// Broadcasts [view] as a STATE_UPDATE with the next state sequence.
  void _broadcastPublicState(PublicStateView view) {
    _stateSeq++;
    final message = StateUpdateMessage(
      seq: _nextSeq(),
      sessionId: sessionId,
      stateSeq: _stateSeq,
      publicState: view,
    );
    final raw = _codec.encode(message);
    for (final client in _clients.values) {
      _sendRaw(client.connection, raw);
    }
  }

  /// Broadcasts the host's own locally-executed action to all clients.
  ///
  /// The host player acts through the same authoritative [GameState] (via
  /// `LocalDriver`), so after any local action the host must re-broadcast
  /// the public state and each player's own visible card so every client
  /// stays in sync. Called after the host's local action has already
  /// mutated [game].
  void broadcastHostAction() {
    final game = _game;
    if (game == null) return;
    _broadcastPublicState(PublicStateView.fromGame(game));
    for (final c in _clients.values) {
      _sendPrivateCard(c);
    }
    _emit(HostSessionEventType.actionAccepted, playerId: kHostPlayerId);
  }

  /// Unicasts the recipient's own authorized visible card (PRIVATE_UPDATE).
  ///
  /// Uses the narrow [PrivateStateView.forVisibleCard] factory, which reads
  /// only the rule-authorized `visibleCardOf` getter — the hidden second
  /// card and every other player's cards are unreachable through this API.
  void _sendPrivateCard(_HostClient client) {
    final game = _game;
    if (game == null) return;
    final player = game.players
        .where((p) => p.id == client.playerId)
        .firstOrNull;
    if (player == null) return;
    final privateView = PrivateStateView.forVisibleCard(game, player);
    _sendRaw(
      client.connection,
      _codec.encode(
        PrivateUpdateMessage(
          seq: _nextSeq(),
          sessionId: sessionId,
          stateSeq: _stateSeq,
          privateState: privateView,
        ),
      ),
    );
  }

  /// Routes one client ACTION_REQUEST through the authoritative [GameState].
  ///
  /// Validation happens here in order: sender authenticity (the request's
  /// playerId must match the connection's assigned player), staleness (the
  /// per-player seq must advance), and turn ownership (only the current
  /// actor may act). Invalid requests never touch the game state and are
  /// answered with [ActionRejectedMessage].
  void _handleActionRequest(
    TransportConnection connection,
    ActionRequestMessage message,
  ) {
    final game = _game;
    final client = _clients.values
        .where((c) => c.connection == connection)
        .firstOrNull;
    if (client == null || game == null) return;

    // Sender authenticity: the request must come from the assigned player.
    if (message.playerId != client.playerId) {
      _sendRejected(connection, message, 'not your turn');
      return;
    }
    // Staleness: per-player action seq must advance (rejects duplicates and
    // actions echoed after a reconnect).
    final lastSeq = _clientActionSeq[client.playerId] ?? -1;
    if (message.seq <= lastSeq) {
      _sendRejected(connection, message, 'stale or duplicate action');
      return;
    }
    _clientActionSeq[client.playerId] = message.seq;

    // A completed game accepts nothing more (the rules engine also throws,
    // but its pour-turn getters are only valid mid-round).
    if (game.gameComplete) {
      _sendRejected(connection, message, 'the game is complete');
      return;
    }

    // Turn ownership: only the current actor may act. This mirrors the
    // rules engine's own checks (which still run as the final authority).
    final bool owned;
    switch (message.action) {
      case GameAction.revealCurrentPlayer:
        owned = game.currentPlayer.id == client.playerId;
      case GameAction.passToNextPlayer:
        owned = game.currentPlayer.id == client.playerId;
      case GameAction.holdOut:
        owned = game.pourCurrentPlayer.id == client.playerId;
      case GameAction.callYamada:
        owned = game.pourCurrentPlayer.id == client.playerId;
      case GameAction.startNextRound:
        owned = true;
    }
    if (!owned) {
      _sendRejected(connection, message, 'not your turn');
      _emit(
        HostSessionEventType.actionRejected,
        playerId: client.playerId,
        roster: _roster,
        reason: 'not your turn',
      );
      return;
    }

    String? rejection;
    try {
      switch (message.action) {
        case GameAction.revealCurrentPlayer:
          game.revealCurrentPlayer();
        case GameAction.passToNextPlayer:
          game.passToNextPlayer();
        case GameAction.holdOut:
          game.holdOut(game.pourCurrentPlayer);
        case GameAction.callYamada:
          game.callYamada(game.pourCurrentPlayer);
        case GameAction.startNextRound:
          game.startNextRound();
      }
    } on YamadaRoundException catch (error) {
      rejection = error.message;
    } on Object {
      // A malformed/edge action must never crash the host's message loop:
      // contain it as a rejection, exactly like an invalid rules action.
      rejection = 'that action could not be applied';
    }

    if (rejection != null) {
      _sendRejected(connection, message, rejection);
      _emit(
        HostSessionEventType.actionRejected,
        playerId: client.playerId,
        roster: _roster,
        reason: rejection,
      );
      return;
    }

    // Accepted: confirm to the requester, broadcast the new public state,
    // and deliver every player their own (possibly new) visible card.
    _sendRaw(
      connection,
      _codec.encode(
        ActionAcceptedMessage(
          seq: _nextSeq(),
          sessionId: sessionId,
          action: message.action,
          requestSeq: message.seq,
          stateSeq: _stateSeq + 1,
        ),
      ),
    );
    _broadcastPublicState(PublicStateView.fromGame(game));
    for (final c in _clients.values) {
      _sendPrivateCard(c);
    }
    _emit(
      HostSessionEventType.actionAccepted,
      playerId: client.playerId,
      roster: _roster,
    );
  }

  /// Answers a RESYNC_REQUEST with the current public state plus the
  /// requester's own visible card.
  void _handleResync(
    TransportConnection connection,
    ResyncRequestMessage message,
  ) {
    final game = _game;
    final client = _clients.values
        .where((c) => c.connection == connection)
        .firstOrNull;
    if (client == null || game == null) return;
    if (message.playerId != client.playerId) return;
    _sendRaw(
      connection,
      _codec.encode(
        ResyncResponseMessage(
          seq: _nextSeq(),
          sessionId: sessionId,
          stateSeq: _stateSeq,
          publicState: PublicStateView.fromGame(game),
        ),
      ),
    );
    _sendPrivateCard(client);
  }

  void _sendRejected(
    TransportConnection connection,
    ActionRequestMessage message,
    String reason,
  ) {
    _sendRaw(
      connection,
      _codec.encode(
        ActionRejectedMessage(
          seq: _nextSeq(),
          sessionId: sessionId,
          action: message.action,
          requestSeq: message.seq,
          reason: reason,
        ),
      ),
    );
  }

  void _send(TransportConnection connection, MultiplayerMessage message) {
    _sendRaw(connection, _codec.encode(message));
  }

  void _sendRaw(TransportConnection connection, String raw) {
    try {
      // Swallow both synchronous and asynchronous send failures: the close
      // handler will clean up a dying connection either way.
      unawaited(connection.send(raw).catchError((_) {}));
    } catch (_) {
      // Synchronous failure (already closed): ignore.
    }
  }

  void _closeQuietly(TransportConnection connection) {
    try {
      unawaited(connection.close());
    } catch (_) {}
  }

  int _nextSeq() => _seq++;

  void _emit(
    HostSessionEventType type, {
    String? playerId,
    List<PublicPlayer>? roster,
    String? reason,
  }) {
    if (_events.isClosed) return;
    _events.add(
      HostSessionEvent(
        type,
        playerId: playerId,
        roster: roster,
        reason: reason,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// A client's LAN session: connects to a host, joins with a name, and keeps
/// the lobby roster in sync until it leaves or the session ends.
class ClientSession {
  ClientSession({
    required this.sessionId,
    required this.playerName,
    MultiplayerTransport? transport,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.heartbeatTimeout = const Duration(seconds: 15),
  }) : _transport = transport ?? TcpMultiplayerTransport();

  /// The session id this client attempts to join with (for discovery joins
  /// it is the discovered id; for manual-IP joins it is a placeholder). The
  /// host's real id is adopted from the first accepted message so that all
  /// subsequent messages pass the host's validation.
  final String sessionId;
  final String playerName;

  /// The session id the host confirmed; adopted from the first accepted
  /// message and used for every subsequent send.
  String? _hostSessionId;

  /// How often the client sends heartbeats.
  final Duration heartbeatInterval;

  /// How long the host may go silent before the client reports a lost
  /// connection.
  final Duration heartbeatTimeout;

  MultiplayerTransport _transport;
  final MessageCodec _codec = const MessageCodec();
  // Broadcast: the join lobby and a RemoteDriver both listen to these
  // streams (the lobby for roster/lobby updates, the driver for gameplay),
  // so a single-subscription controller would throw on the second listen.
  // Early events emitted before any listener (e.g. the initial `joined`
  // during join()) are intentionally dropped; consumers rely on join()'s
  // return value and later messages instead.
  final StreamController<ClientSessionEvent> _events =
      StreamController<ClientSessionEvent>.broadcast();
  final StreamController<ClientGameplayEvent> _gameplayEvents =
      StreamController<ClientGameplayEvent>.broadcast();

  TransportConnection? _connection;
  StreamSubscription<String>? _incomingSub;
  Timer? _heartbeatTimer;
  Timer? _joinTimeout;
  Completer<JoinResult>? _joinCompleter;
  List<PublicPlayer> _roster = const [];
  PublicPlayer? _self;
  DateTime _lastSeen = DateTime.now();
  int _seq = 0;
  bool _joined = false;
  bool _closed = false;

  /// Highest STATE_UPDATE seq applied (guards against stale/out-of-order
  /// broadcasts after a reconnect).
  int _lastStateSeq = -1;

  /// Lobby events (roster updates, connection loss, session end).
  Stream<ClientSessionEvent> get events => _events.stream;

  /// Gameplay events: game start, state broadcasts, private card updates,
  /// action accept/reject, and resync responses (M18.4).
  Stream<ClientGameplayEvent> get gameplayEvents => _gameplayEvents.stream;

  /// The player identity assigned by the host (null until accepted).
  PublicPlayer? get self => _self;

  /// The latest roster (null until joined).
  List<PublicPlayer> get roster => List.unmodifiable(_roster);

  bool get isConnected =>
      !_closed && _connection != null && _connection!.isOpen;

  /// Connects to the host and requests a seat over a direct connection.
  /// Completes with the outcome (accepted, rejected, or a typed failure).
  /// Never throws.
  ///
  /// [hostAddress] is transport-addressed: a LAN IP for the default TCP
  /// transport, a BLE peer identifier for the Bluetooth transport (port 0),
  /// etc. [socketErrorMessage] customizes the connection-failure message for
  /// the transport in use (e.g. Bluetooth wording instead of the default
  /// same-Wi-Fi wording).
  Future<JoinResult> join({
    required String hostAddress,
    int port = kDefaultGamePort,
    Duration connectTimeout = const Duration(seconds: 5),
    String socketErrorMessage =
        'Could not reach the host. Check that it is on the same Wi-Fi '
        'network and the address is correct.',
  }) {
    if (_joinCompleter != null) {
      throw StateError('join already in progress');
    }
    return _runJoin(
      connect: () => _transport.connect(
        hostAddress: hostAddress,
        sessionId: sessionId,
        port: port,
        connectTimeout: connectTimeout,
      ),
      connectTimeout: connectTimeout,
      socketErrorMessage: socketErrorMessage,
    ).then((attempt) => attempt.result);
  }

  /// Connects to the host through the internet relay.
  ///
  /// The relay is a reachable WebSocket endpoint, so the two phones can be
  /// on any mix of Wi-Fi/mobile-data networks. Same host-authoritative
  /// join: after the relay binds the client to the session, the normal
  /// JOIN_REQUEST/JOIN_ACCEPT handshake runs unchanged. Never throws.
  ///
  /// A relay join is given a generous timeout (default 30s) and up to **one
  /// controlled retry** because a public relay can be mid-wake: Render's
  /// free tier sleeps after ~15 minutes without traffic and takes 30–60s to
  /// boot, so the first attempt can fail or time out while the relay wakes.
  /// Permanent failures (no such session, session full, host not connected,
  /// protocol rejection) are never retried — only transient transport
  /// failures/timeouts are, and at most once.
  Future<JoinResult> joinRelay({
    required String relayUrl,
    Duration connectTimeout = const Duration(seconds: 30),
  }) {
    if (_joinCompleter != null) {
      throw StateError('join already in progress');
    }
    // Reuse an injected relay transport (tests inject a controllable one);
    // the real flow replaces the default TCP transport with the relay
    // transport exactly once.
    if (_transport is! RelayMultiplayerTransport) {
      _transport = RelayMultiplayerTransport(
        relayUrl: relayUrl,
        connectTimeout: connectTimeout,
      );
    }
    return _runRelayJoinWithRetry(
      relayUrl: relayUrl,
      connectTimeout: connectTimeout,
    );
  }

  /// Runs the relay join up to twice. The first attempt may fail because the
  /// relay is cold-starting (connect timeout, socket error, connection lost,
  /// or the host not answering) — exactly one retry gives it time to wake.
  /// Permanent relay rejections are classified as non-retryable by
  /// [_runJoin] and surface immediately.
  Future<JoinResult> _runRelayJoinWithRetry({
    required String relayUrl,
    required Duration connectTimeout,
  }) async {
    Future<TransportConnection> connect() => _transport.connect(
      hostAddress: relayUrl,
      sessionId: sessionId,
      port: 0,
      connectTimeout: connectTimeout,
    );
    JoinResult relayError(RelayJoinException error) => JoinResult.failure(
      _relayJoinOutcome(error.reason),
      _friendlyRelayReason(error.reason),
    );
    const socketErrorMessage =
        'Could not reach the game relay. Check your internet connection.';

    var attempt = await _runJoin(
      connect: connect,
      connectTimeout: connectTimeout,
      socketErrorMessage: socketErrorMessage,
      onRelayError: relayError,
    );
    if (!attempt.result.isAccepted && attempt.retryable) {
      attempt = await _runJoin(
        connect: connect,
        connectTimeout: connectTimeout,
        socketErrorMessage: socketErrorMessage,
        onRelayError: relayError,
      );
    }
    return attempt.result;
  }

  /// One join attempt: connect, send JOIN_REQUEST, wait for the host's
  /// JOIN_ACCEPT/JOIN_REJECT (or a typed failure). Never throws.
  ///
  /// Returns the result plus whether the failure was a **transient transport
  /// failure** (connect/exchange timeout, socket error, connection lost, or
  /// the host not answering) that a caller may retry once. Relay rejections
  /// (no such session, session full, host not connected, protocol errors)
  /// are permanent and come back with `retryable == false`.
  Future<({JoinResult result, bool retryable})> _runJoin({
    required Future<TransportConnection> Function() connect,
    required Duration connectTimeout,
    required String socketErrorMessage,
    JoinResult Function(RelayJoinException error)? onRelayError,
  }) async {
    final completer = Completer<JoinResult>();
    _joinCompleter = completer;
    var retryable = false;
    try {
      final connection = await connect();
      _connection = connection;
      _lastSeen = DateTime.now();
      _incomingSub = connection.incoming.listen(
        _onMessage,
        onDone: () {
          // A connection dropping mid-join is transient — the relay (or
          // host) may be waking — so one retry is allowed.
          if (!completer.isCompleted) retryable = true;
          _onConnectionClosed();
        },
        onError: (_) {
          if (!completer.isCompleted) retryable = true;
          _onConnectionClosed();
        },
      );
      await connection.send(
        _codec.encode(
          JoinRequestMessage(
            seq: _nextSeq(),
            sessionId: sessionId,
            playerName: playerName,
          ),
        ),
      );
      _joinTimeout = Timer(connectTimeout, () {
        if (!completer.isCompleted) {
          // The host did not answer in time — transient; allow one retry
          // instead of ending the session (the join UI disposes on failure).
          retryable = true;
          completer.complete(
            const JoinResult.failure(
              JoinOutcome.timedOut,
              'The host did not respond.',
            ),
          );
          _cleanupJoinFailure();
        }
      });
    } on RelayJoinException catch (error) {
      // A relay rejection (no such session, session full, host not
      // connected, …) is permanent — retrying cannot change it. The single
      // exception is a connection lost mid-handshake, which is transient.
      retryable = error.reason == 'relay connection lost';
      _completeJoin(
        onRelayError?.call(error) ??
            const JoinResult.failure(
              JoinOutcome.connectionFailed,
              'Could not connect to the host.',
            ),
      );
    } on SocketException catch (_) {
      retryable = true;
      _completeJoin(
        JoinResult.failure(JoinOutcome.connectionFailed, socketErrorMessage),
      );
    } on Exception catch (_) {
      // Covers the connect/exchange timeouts thrown while the relay wakes
      // or a transport (e.g. Bluetooth) fails its bounded connect. Use the
      // caller's transport-specific wording so the message stays friendly.
      retryable = true;
      _completeJoin(
        JoinResult.failure(JoinOutcome.connectionFailed, socketErrorMessage),
      );
    }
    return (result: await completer.future, retryable: retryable);
  }

  JoinOutcome _relayJoinOutcome(String reason) {
    // A session that no longer exists on the relay is terminal, like the
    // host ending the session — map it to sessionEnded so the UI shows the
    // friendly "session ended" state instead of a generic failure.
    return switch (reason) {
      'no such session' => JoinOutcome.sessionEnded,
      _ => JoinOutcome.connectionFailed,
    };
  }

  String _friendlyRelayReason(String reason) {
    return switch (reason) {
      'no such session' => 'Game unavailable — this session no longer exists.',
      'session full' => 'The session is full.',
      'host not connected' => 'The host is not reachable right now.',
      'session already hosted' =>
        'This session is already being hosted elsewhere.',
      'relay connection lost' => 'Connection to the relay was lost.',
      _ => 'Could not connect to the game relay.',
    };
  }

  void _onMessage(String raw) {
    _lastSeen = DateTime.now();
    final MultiplayerMessage message;
    try {
      message = _codec.decode(raw);
    } on MultiplayerProtocolException {
      if (!_joined) {
        _completeJoin(
          const JoinResult.failure(
            JoinOutcome.protocolError,
            'The host speaks an incompatible protocol version.',
          ),
        );
      }
      return;
    }
    if (_hostSessionId == null) {
      // First message from the host: adopt its session id so every later
      // message we send passes the host's validation.
      _hostSessionId = message.sessionId;
    } else if (message.sessionId != _hostSessionId) {
      // A message from a different session after joining is not ours.
      return;
    }
    switch (message) {
      case JoinAcceptMessage(:final playerId, :final color, :final roster):
        _joinTimeout?.cancel();
        _self = PublicPlayer(id: playerId, name: playerName, color: color);
        _roster = List.of(roster);
        _joined = true;
        _heartbeatTimer = Timer.periodic(
          heartbeatInterval,
          (_) => _onHeartbeatTick(),
        );
        _emit(ClientSessionEventType.joined, roster: _roster);
        _completeJoin(JoinResult.accepted(_self!, _roster));
      case JoinRejectMessage(:final reason):
        _joinTimeout?.cancel();
        _completeJoin(JoinResult.rejected(reason));
        _close();
      case RosterUpdateMessage(:final roster):
        _roster = List.of(roster);
        _emit(ClientSessionEventType.rosterUpdated, roster: _roster);
      case SessionEndMessage(:final reason):
        _joinTimeout?.cancel();
        _emit(ClientSessionEventType.sessionEnded, reason: reason);
        _completeJoin(JoinResult.failure(JoinOutcome.sessionEnded, reason));
        _close();
      case HeartbeatMessage():
        break;
      case GameStartMessage(:final publicState):
        _lastStateSeq = 0;
        _emitGameplay(
          ClientGameplayEventType.gameStarted,
          publicState: publicState,
          stateSeq: 0,
        );
      case StateUpdateMessage(:final stateSeq, :final publicState):
        if (stateSeq < _lastStateSeq) break; // stale broadcast: ignore
        _lastStateSeq = stateSeq;
        _emitGameplay(
          ClientGameplayEventType.stateUpdated,
          publicState: publicState,
          stateSeq: stateSeq,
        );
      case PrivateUpdateMessage(:final stateSeq, :final privateState):
        // Only ever apply a private card addressed to this player.
        if (privateState.recipientPlayerId != _self?.id) break;
        _emitGameplay(
          ClientGameplayEventType.privateUpdated,
          privateState: privateState,
          stateSeq: stateSeq,
        );
      case ActionAcceptedMessage(
        :final action,
        :final requestSeq,
        :final stateSeq,
      ):
        _emitGameplay(
          ClientGameplayEventType.actionAccepted,
          action: action,
          requestSeq: requestSeq,
          stateSeq: stateSeq,
        );
      case ActionRejectedMessage(
        :final action,
        :final requestSeq,
        :final reason,
      ):
        _emitGameplay(
          ClientGameplayEventType.actionRejected,
          action: action,
          requestSeq: requestSeq,
          reason: reason,
        );
      case ResyncResponseMessage(:final stateSeq, :final publicState):
        if (stateSeq < _lastStateSeq) break;
        _lastStateSeq = stateSeq;
        _emitGameplay(
          ClientGameplayEventType.resynced,
          publicState: publicState,
          stateSeq: stateSeq,
        );
      default:
        break;
    }
  }

  void _onHeartbeatTick() {
    final connection = _connection;
    if (connection != null) {
      try {
        unawaited(
          connection
              .send(
                _codec.encode(
                  HeartbeatMessage(
                    seq: _nextSeq(),
                    sessionId: _hostSessionId ?? sessionId,
                  ),
                ),
              )
              .catchError((_) {}),
        );
      } catch (_) {}
    }
    if (DateTime.now().difference(_lastSeen) > heartbeatTimeout) {
      _emit(ClientSessionEventType.connectionLost);
      _close();
    }
  }

  void _onConnectionClosed() {
    if (_joined) {
      _joinTimeout?.cancel();
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _emit(ClientSessionEventType.connectionLost);
      _close();
    } else {
      // A join that fails mid-handshake must not end the session: the relay
      // retry re-connects on the same [ClientSession].
      _completeJoin(
        const JoinResult.failure(
          JoinOutcome.connectionFailed,
          'The connection to the host was lost.',
        ),
      );
      _cleanupJoinFailure();
    }
  }

  /// Cleans up after a failed join attempt without ending the session:
  /// closes the transport connection and cancels timers so a retry can
  /// connect again on the same [ClientSession]. Only used while joining —
  /// the joined path still calls [_close].
  void _cleanupJoinFailure() {
    _joinTimeout?.cancel();
    _joinTimeout = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _incomingSub?.cancel();
    _incomingSub = null;
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      try {
        unawaited(connection.close());
      } catch (_) {}
    }
  }

  void _completeJoin(JoinResult result) {
    final completer = _joinCompleter;
    if (completer == null) return;
    _joinCompleter = null;
    if (!completer.isCompleted) completer.complete(result);
  }

  /// Leaves the session cleanly (sends DISCONNECT) and closes the connection.
  Future<void> disconnect() async {
    if (_closed) return;
    final connection = _connection;
    if (_joined && connection != null) {
      try {
        await connection.send(
          _codec.encode(
            DisconnectMessage(
              seq: _nextSeq(),
              sessionId: _hostSessionId ?? sessionId,
              playerId: _self?.id ?? '',
              reason: 'left',
            ),
          ),
        );
      } catch (_) {}
    }
    _close();
  }

  /// Sends one ACTION_REQUEST for [action] on behalf of this player.
  ///
  /// Fire-and-forget from the caller's perspective: the outcome arrives via
  /// [gameplayEvents] (actionAccepted / actionRejected). Never throws for
  /// transport failures; a closed connection simply drops the request.
  void requestAction(GameAction action) {
    final connection = _connection;
    final self = _self;
    if (connection == null || self == null || _closed) return;
    try {
      unawaited(
        connection
            .send(
              _codec.encode(
                ActionRequestMessage(
                  seq: _nextSeq(),
                  sessionId: _hostSessionId ?? sessionId,
                  action: action,
                  playerId: self.id,
                ),
              ),
            )
            .catchError((_) {}),
      );
    } catch (_) {
      // A dead connection cannot send; the reconnect path handles it.
    }
  }

  /// Asks the host for the current authoritative state (after a reconnect
  /// or missed broadcasts). Fire-and-forget.
  void requestResync() {
    final connection = _connection;
    final self = _self;
    if (connection == null || self == null || _closed) return;
    try {
      unawaited(
        connection
            .send(
              _codec.encode(
                ResyncRequestMessage(
                  seq: _nextSeq(),
                  sessionId: _hostSessionId ?? sessionId,
                  playerId: self.id,
                  lastStateSeq: _lastStateSeq,
                ),
              ),
            )
            .catchError((_) {}),
      );
    } catch (_) {}
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _joinTimeout?.cancel();
    _joinTimeout = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _incomingSub?.cancel();
    _incomingSub = null;
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      try {
        unawaited(connection.close());
      } catch (_) {}
    }
    if (!_events.isClosed) {
      unawaited(_events.close());
    }
    if (!_gameplayEvents.isClosed) {
      unawaited(_gameplayEvents.close());
    }
  }

  /// Releases resources without notifying the host.
  Future<void> dispose() async {
    _close();
  }

  int _nextSeq() => _seq++;

  void _emitGameplay(
    ClientGameplayEventType type, {
    PublicStateView? publicState,
    PrivateStateView? privateState,
    GameAction? action,
    int requestSeq = -1,
    int stateSeq = -1,
    String? reason,
  }) {
    if (_gameplayEvents.isClosed) return;
    _gameplayEvents.add(
      ClientGameplayEvent(
        type,
        publicState: publicState,
        privateState: privateState,
        action: action,
        requestSeq: requestSeq,
        stateSeq: stateSeq,
        reason: reason,
      ),
    );
  }

  void _emit(
    ClientSessionEventType type, {
    List<PublicPlayer>? roster,
    String? playerId,
    String? reason,
  }) {
    if (_events.isClosed) return;
    _events.add(
      ClientSessionEvent(
        type,
        roster: roster,
        playerId: playerId,
        reason: reason,
      ),
    );
  }
}
