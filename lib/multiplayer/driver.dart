import '../challenge/challenge_state.dart';
import '../game_state.dart';
import '../player.dart';

/// The gameplay operations the UI performs, decoupled from how they are
/// executed.
///
/// This is the seam between the presentation layer and the authoritative
/// rules engine (see docs/multiplayer/m18-architecture.md §1.1):
///
/// ```
/// UI (GameStartScreen)
///   → GameDriver
///       ├─ LocalDriver  → wraps the real GameState (pass-and-play today)
///       └─ RemoteDriver → sends ACTION_REQUEST over the session (M18.3)
/// ```
///
/// The abstraction represents exactly the five authoritative actions
/// `GameStartScreen` performs. It deliberately duplicates **no** gameplay
/// rules — actions are forwarded to (or, remotely, validated by) the
/// underlying [GameState], which remains the single rules engine.
///
/// [state] is the authoritative [GameState] for [LocalDriver]. A future
/// remote implementation will back it with a read-only view of the broadcast
/// public state (M18.3); until then the UI reads the same state object it
/// always has.
abstract class GameDriver {
  /// The authoritative game state backing this driver.
  GameState get state;

  /// Reveals the current viewer's one permitted card.
  void revealCurrentPlayer();

  /// Passes the phone to the next viewer (or starts pouring after the last).
  void passToNextPlayer();

  /// [player]'s pouring-turn action: hold out (keep their cards).
  void holdOut(Player player);

  /// [player]'s pouring-turn action: shout YAMADA (admit defeat).
  void callYamada(Player player);

  /// [player]'s pouring-turn action: refuse to drink.
  ///
  /// Returns `true` if a challenge was initiated, `false` if the player
  /// drinks directly.
  bool refuseDrink(Player player);

  /// Selects a random challenger from eligible players.
  ChallengeState selectChallenger();

  /// The challenger chooses the challenge type.
  ChallengeState chooseChallengeType(ChallengeType type, Player player);

  /// Resolves the active challenge with the given result.
  void resolveChallenge(ChallengeResult result);

  /// Starts the next round after the current one has completed.
  void startNextRound();
}

/// The single-device (pass-and-play) driver: a thin, rule-free wrapper over a
/// real [GameState].
///
/// Every method simply forwards to [state], preserving today's behavior
/// exactly. No gameplay logic lives here — invalid actions still throw the
/// same [YamadaRoundException] from the underlying state.
class LocalDriver implements GameDriver {
  LocalDriver(this.state);

  @override
  final GameState state;

  @override
  void revealCurrentPlayer() => state.revealCurrentPlayer();

  @override
  void passToNextPlayer() => state.passToNextPlayer();

  @override
  void holdOut(Player player) => state.holdOut(player);

  @override
  void callYamada(Player player) => state.callYamada(player);

  @override
  bool refuseDrink(Player player) => state.refuseDrink(player);

  @override
  ChallengeState selectChallenger() => state.selectChallenger();

  @override
  ChallengeState chooseChallengeType(ChallengeType type, Player player) =>
      state.chooseChallengeType(type, player);

  @override
  void resolveChallenge(ChallengeResult result) =>
      state.resolveChallenge(result);

  @override
  void startNextRound() => state.startNextRound();
}
