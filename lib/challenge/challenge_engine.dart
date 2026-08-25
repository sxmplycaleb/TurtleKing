import 'dart:math';

import '../player.dart';
import 'challenge_state.dart';
import 'dare_card.dart';
import 'rps_state.dart';
import 'trivia_card.dart';
import 'trivia_state.dart';

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

  /// Starts the RPS match for this challenge.
  ///
  /// Must be called during the inProgress phase when type == RPS.
  RpsState startRps() {
    if (_state == null) {
      throw StateError('No active challenge');
    }
    if (_state!.type != ChallengeType.rockPaperScissors) {
      throw StateError('Challenge is not RPS');
    }
    if (_state!.rpsState != null) {
      throw StateError('RPS has already been started');
    }
    final rps = RpsState(
      challengedPlayer: _state!.challengedPlayer,
      challenger: _state!.challenger!,
    );
    _state = _state!.copyWith(rpsState: rps);
    return rps;
  }

  /// Starts the Trivia challenge for this challenge.
  ///
  /// Must be called during the inProgress phase when type == Trivia.
  TriviaState startTrivia(TriviaCard card) {
    if (_state == null) {
      throw StateError('No active challenge');
    }
    if (_state!.type != ChallengeType.trivia) {
      throw StateError('Challenge is not Trivia');
    }
    if (_state!.triviaState != null) {
      throw StateError('Trivia has already been started');
    }
    final trivia = TriviaState(
      challengedPlayer: _state!.challengedPlayer,
      challenger: _state!.challenger!,
      question: card,
    );
    _state = _state!.copyWith(triviaState: trivia);
    return trivia;
  }

  /// Records the answer to a trivia question.
  ///
  /// [isCorrect] indicates whether the challenged player's answer was correct.
  void recordTriviaAnswer(bool isCorrect) {
    if (_state == null) {
      throw StateError('No active challenge');
    }
    final trivia = _state!.triviaState;
    if (trivia == null) {
      throw StateError('Trivia has not been started');
    }
    if (trivia.resolved) {
      throw StateError('Trivia is already resolved');
    }
    if (trivia.phase == TriviaPhase.answered) {
      throw StateError('Answer has already been recorded');
    }
    _state = _state!.copyWith(
      triviaState: trivia.copyWith(
        isCorrect: isCorrect,
        phase: TriviaPhase.answered,
      ),
    );
  }

  /// Resolves the Trivia challenge and applies the penalty.
  ///
  /// Correct answer: challenger takes the penalty.
  /// Wrong answer: challenged player takes the penalty.
  ChallengeState resolveTrivia(ChallengeResult result) {
    if (_state == null) {
      throw StateError('No active challenge');
    }
    final trivia = _state!.triviaState;
    if (trivia == null) {
      throw StateError('Trivia has not been started');
    }
    if (trivia.resolved) {
      throw StateError('Trivia is already resolved');
    }
    if (trivia.phase != TriviaPhase.answered) {
      throw StateError('Trivia answer has not been recorded yet');
    }

    // Validate that the result matches the answer.
    final expectedResult = trivia.isCorrect!
        ? ChallengeResult
              .challengerPenalty // Correct → challenger takes shot
        : ChallengeResult
              .challengedPenalty; // Wrong → challenged player takes shot
    if (result != expectedResult) {
      throw ArgumentError('ChallengeResult does not match the Trivia answer');
    }

    _state = _state!.copyWith(triviaState: trivia.copyWith(resolved: true));
    return resolve(result);
  }

  /// Records the outcome of one RPS round.
  ///
  /// [roundNumber] must match the expected round (1-based).
  /// [outcome] is the result of the physical RPS round.
  ///
  /// After recording, the match may be complete if a player has 2 wins.
  /// The caller should check `rpsState.isMatchComplete` to determine
  /// whether to continue to the next round or resolve the match.
  void recordRpsRound(int roundNumber, RpsRoundOutcome outcome) {
    if (_state == null) {
      throw StateError('No active challenge');
    }
    final rps = _state!.rpsState;
    if (rps == null) {
      throw StateError('RPS has not been started');
    }
    if (rps.resolved) {
      throw StateError('RPS is already resolved');
    }
    if (rps.isMatchComplete) {
      throw StateError('RPS match is already complete');
    }
    if (roundNumber != rps.currentRound) {
      throw StateError(
        'Expected round ${rps.currentRound} but got $roundNumber',
      );
    }
    final newResults = [
      ...rps.roundResults,
      RpsRoundResult(roundNumber: roundNumber, outcome: outcome),
    ];
    _state = _state!.copyWith(rpsState: rps.copyWith(roundResults: newResults));
  }

  /// Resolves the RPS match and applies the penalty.
  ///
  /// The winner/loser is determined automatically from the round results.
  /// Must be called after the match is complete (one player has 2 wins).
  ///
  /// The loser receives the shot penalty.
  ChallengeState resolveRps(ChallengeResult result) {
    if (_state == null) {
      throw StateError('No active challenge');
    }
    final rps = _state!.rpsState;
    if (rps == null) {
      throw StateError('RPS has not been started');
    }
    if (rps.resolved) {
      throw StateError('RPS is already resolved');
    }
    if (!rps.isMatchComplete) {
      throw StateError(
        'RPS match is not complete — must have a winner (2 rounds won)',
      );
    }

    // Validate that the result matches the automatic winner/loser.
    // ChallengeResult determines who takes the shot (the loser).
    final penaltyRecipient = result == ChallengeResult.challengerPenalty
        ? rps.challenger
        : rps.challengedPlayer;
    if (penaltyRecipient.id != rps.loser!.id) {
      throw ArgumentError('ChallengeResult does not match the RPS loser');
    }

    _state = _state!.copyWith(rpsState: rps.copyWith(resolved: true));
    return resolve(result);
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
