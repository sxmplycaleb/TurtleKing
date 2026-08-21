import 'dart:async';

import '../challenge/challenge_state.dart';
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

  /// Refuse to drink — initiates a challenge if 3+ other players.
  void refuseDrink();

  /// Select a random challenger from eligible players (host-authoritative).
  void selectChallenger();

  /// The challenger chooses the challenge type.
  void chooseChallengeType(ChallengeType type);

  /// Resolve the active challenge with the given result.
  void resolveChallenge(ChallengeResult result);

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
    switch (event.type) {
      case HostSessionEventType.sessionEnded:
        _emit(RemoteGameStatus.sessionEnded, message: event.reason);
      case HostSessionEventType.actionAccepted:
        // An action was applied to the authoritative game — the host's own
        // action (broadcastHostAction) OR a client's (routed through the
        // session). The game object we already own is the source of truth;
        // refresh the host's view and notify the UI so it re-renders. The
        // screen rebuilds only on RemoteGameEvent — without this, the
        // host's first action would appear to do nothing.
        _view = RemoteGameView(
          publicState: PublicStateView.fromGame(game),
          selfPlayerId: hostPlayer.id,
          myCard: PrivateCard.fromCard(game.visibleCardOf(hostPlayer)),
        );
        _emit(RemoteGameStatus.playing);
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

  @override
  void refuseDrink() => _act(() => game.refuseDrink(game.pourCurrentPlayer));

  @override
  void selectChallenger() => _act(() {
    if (!game.challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    game.selectChallenger();
  });

  @override
  void chooseChallengeType(ChallengeType type) => _act(() {
    if (!game.challengeActive || game.challengeState?.challenger == null) {
      throw const YamadaRoundException('No active challenge');
    }
    game.chooseChallengeType(type, game.challengeState!.challenger!);
  });

  @override
  void resolveChallenge(ChallengeResult result) => _act(() {
    if (!game.challengeActive) {
      throw const YamadaRoundException('No active challenge');
    }
    game.resolveChallenge(result);
  });

  void _act(void Function() action) {
    if (!_started) return;
    try {
      action();
    } on YamadaRoundException catch (error) {
      _emit(RemoteGameStatus.playing, rejection: error.message);
      return;
    }
    // Do NOT rebuild _view here — broadcastHostAction() fires
    // actionAccepted on the session, which triggers _onHostEvent and
    // rebuilds _view + emits RemoteGameStatus.playing in one pass.
    // Rebuilding here would create a redundant duplicate rebuild on
    // every host action.
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
