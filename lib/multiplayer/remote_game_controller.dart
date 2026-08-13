import 'dart:async';

import '../game_state.dart';
import '../player.dart';
import 'private_state.dart';
import 'public_state.dart';
import 'remote_driver.dart';
import 'remote_game_view.dart';
import 'session.dart';

/// The gameplay surface the remote game screen renders from.
///
/// Both sides of a remote game implement this:
///
/// * **Client** — [RemoteDriver] sends ACTION_REQUEST and renders the
///   sanitized [RemoteGameView] it receives.
/// * **Host** — [HostRemoteController] executes actions against the real
///   authoritative [GameState] and broadcasts the result.
///
/// The screen never branches on host/client; it only reads the view, the
/// status, and calls the same five actions.
abstract class RemoteGameController {
  RemoteGameView get view;

  RemoteGameStatus get status;

  Stream<RemoteGameEvent> get events;

  /// True when this controller is the authoritative host device.
  bool get isHost;

  /// The same five gameplay operations the UI always performs.
  void revealCurrentPlayer();

  void passToNextPlayer();

  void holdOut();

  void callYamada();

  void startNextRound();

  /// Reconnects after a failed connection. Hosts always report success
  /// (they are the authority); clients retry their last-known host.
  Future<bool> reconnect();

  /// Leaves the session cleanly (used by the back/quit affordance).
  Future<void> leave();
}

/// The host device's gameplay controller.
///
/// The host is authoritative: it owns the real [GameState], executes actions
/// through [LocalDriver] semantics against it, and then broadcasts the new
/// public state plus every player's own visible card via [HostSession]. Its
/// own view is the same sanitized projection the clients see — the host UI
/// reveals only the host player's own card, never another player's.
class HostRemoteController implements RemoteGameController {
  HostRemoteController({
    required this.hostSession,
    required this.game,
    required this.hostPlayer,
  });

  final HostSession hostSession;
  final GameState game;
  final Player hostPlayer;

  final StreamController<RemoteGameEvent> _events =
      StreamController<RemoteGameEvent>.broadcast();
  StreamSubscription<HostSessionEvent>? _hostSub;

  RemoteGameView? _view;
  bool _started = false;

  @override
  Stream<RemoteGameEvent> get events => _events.stream;

  @override
  RemoteGameView get view {
    final current = _view;
    if (current != null) return current;
    return RemoteGameView(
      publicState: PublicStateView.fromGame(game),
      selfPlayerId: hostPlayer.id,
      myCard: PrivateCard.fromCard(game.visibleCardOf(hostPlayer)),
    );
  }

  @override
  RemoteGameStatus get status =>
      _started ? RemoteGameStatus.playing : RemoteGameStatus.connecting;

  @override
  bool get isHost => true;

  /// Starts the authoritative game and begins broadcasting to clients.
  Future<void> start() async {
    _started = true;
    _view = RemoteGameView(
      publicState: PublicStateView.fromGame(game),
      selfPlayerId: hostPlayer.id,
      myCard: PrivateCard.fromCard(game.visibleCardOf(hostPlayer)),
    );
    _hostSub = hostSession.events.listen(_onHostEvent);
    await hostSession.startGame(game);
    _emit(RemoteGameStatus.playing);
  }

  void _onHostEvent(HostSessionEvent event) {
    // Surface only what the host UI needs; state broadcasts arrive via the
    // authoritative game object we already own.
    switch (event.type) {
      case HostSessionEventType.sessionEnded:
        _emit(RemoteGameStatus.sessionEnded, message: event.reason);
      case HostSessionEventType.actionAccepted:
      case HostSessionEventType.actionRejected:
      case HostSessionEventType.gameStarted:
      case HostSessionEventType.started:
      case HostSessionEventType.clientJoined:
      case HostSessionEventType.clientLeft:
      case HostSessionEventType.rosterUpdated:
        break;
    }
  }

  // Actions execute against the authoritative GameState (the host's own
  // device acts like a local player), then broadcast.
  @override
  void revealCurrentPlayer() => _act(() => game.revealCurrentPlayer());

  @override
  void passToNextPlayer() => _act(() => game.passToNextPlayer());

  @override
  void holdOut() => _act(() => game.holdOut(game.pourCurrentPlayer));

  @override
  void callYamada() => _act(() => game.callYamada(game.pourCurrentPlayer));

  @override
  void startNextRound() => _act(() => game.startNextRound());

  void _act(void Function() action) {
    if (!_started) return;
    try {
      action();
    } on YamadaRoundException catch (error) {
      _emit(RemoteGameStatus.playing, rejection: error.message);
      return;
    }
    _view = RemoteGameView(
      publicState: PublicStateView.fromGame(game),
      selfPlayerId: hostPlayer.id,
      myCard: PrivateCard.fromCard(game.visibleCardOf(hostPlayer)),
    );
    hostSession.broadcastHostAction();
  }

  void _emit(RemoteGameStatus status, {String? message, String? rejection}) {
    if (_events.isClosed) return;
    _events.add(
      RemoteGameEvent(status, message: message, rejection: rejection),
    );
  }

  @override
  Future<bool> reconnect() async {
    // The host is the authority; there is nothing to reconnect to.
    return true;
  }

  @override
  Future<void> leave() async {
    await _hostSub?.cancel();
    _hostSub = null;
    await hostSession.dispose();
    if (!_events.isClosed) {
      await _events.close();
    }
  }
}
