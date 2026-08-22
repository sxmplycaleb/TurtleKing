import 'dart:math';

import '../player.dart';
import 'challenge_state.dart';
import 'dare_card.dart';

/// The minimum number of OTHER players required to trigger the challenge
/// selection flow when a player refuses to drink.
const int challengeMinimumOtherPlayers = 3;

/// Manages the lifecycle of a refusal challenge:
///
/// 1. Begin: challenged player refuses → challenge starts
/// 2. Select: random challenger is chosen from eligible players
/// 3. Choose type: challenger picks Dare / RPS / Trivia
/// 4. Resolve: challenge completes → penalty recipient determined
///
/// The engine is a pure state machine — no UI, no side effects. It is
/// designed to be driven by both local (pass-and-play) and multiplayer
/// (host-authoritative) code paths.
class ChallengeEngine {
  ChallengeEngine({Random? random}) : _random = random ?? Random();

  final Random _random;
  ChallengeState? _state;

  /// The current active challenge, or null when no challenge is in progress.
  ChallengeState? get state => _state;

  /// Whether a challenge is currently active.
  bool get isActive => _state?.isActive ?? false;

  /// Begins a new challenge.
  ///
  /// [challengedPlayer] is the player who refused to drink.
  /// [eligiblePlayers] is every other active player (not the challenged one).
  ///
  /// Returns the initial challenge state in the selection phase.
  ChallengeState begin({
    required Player challengedPlayer,
    required List<Player> eligiblePlayers,
  }) {
    if (_state?.isActive == true) {
      throw StateError('A challenge is already in progress');
    }
    if (eligiblePlayers.isEmpty) {
      throw ArgumentError('Must have at least one eligible player');
    }
    if (eligiblePlayers.any((p) => p.id == challengedPlayer.id)) {
      throw ArgumentError('Challenged player cannot be in eligible list');
    }

    _state = ChallengeState.begin(
      challengedPlayer: challengedPlayer,
      eligiblePlayers: eligiblePlayers,
    );
    return _state!;
  }

  /// Randomly selects one eligible player as the challenger.
  ///
  /// Returns the updated state with the challenger set and phase moved
  /// to [ChallengePhase.typeSelection].
  ///
  /// Throws [StateError] if called outside the selection phase.
  ChallengeState selectChallenger() {
    _validatePhase(ChallengePhase.selection);
    final eligible = _state!.eligiblePlayers;
    final index = _random.nextInt(eligible.length);
    final selected = eligible[index];

    _state = _state!.copyWith(
      challenger: selected,
      phase: ChallengePhase.typeSelection,
    );
    return _state!;
  }

  /// The challenger selects the challenge type.
  ///
  /// Throws [StateError] if called outside the type selection phase,
  /// or if [player] is not the challenger.
  ChallengeState chooseChallengeType(ChallengeType type, Player player) {
    _validatePhase(ChallengePhase.typeSelection);
    if (player.id != _state!.challenger!.id) {
      throw ArgumentError('Only the challenger can choose the challenge type');
    }

    _state = _state!.copyWith(type: type, phase: ChallengePhase.inProgress);
    return _state!;
  }

  /// Resolves the challenge with the given outcome.
  ///
  /// This is the single resolution point. Once called, the challenge is
  /// marked as resolved and the penalty recipient is determined.
  ///
  /// Throws [StateError] if the challenge is already resolved.
  ChallengeState resolve(ChallengeResult result) {
    if (_state == null) {
      throw StateError('No active challenge');
    }
    if (_state!.resolved) {
      throw StateError('Challenge already resolved');
    }

    _state = _state!.copyWith(
      result: result,
      phase: ChallengePhase.resolved,
      resolved: true,
    );
    return _state!;
  }

  /// Sets the current Dare card on the active challenge state.
  ///
  /// Must be called during the inProgress phase when type == Dare.
  void setDare(DareCard card) {
    if (_state == null) {
      throw StateError('No active challenge');
    }
    if (_state!.type != ChallengeType.dare) {
      throw StateError('Challenge is not a Dare');
    }
    if (_state!.currentDare != null) {
      throw StateError('A Dare has already been drawn');
    }
    _state = _state!.copyWith(currentDare: card);
  }

  /// Clears the current challenge, allowing a new one to begin.
  void reset() {
    _state = null;
  }

  /// Validates that the engine is in the expected phase.
  void _validatePhase(ChallengePhase expected) {
    if (_state == null) {
      throw StateError('No active challenge');
    }
    if (_state!.phase != expected) {
      throw StateError('Expected phase $expected but found ${_state!.phase}');
    }
  }
}
