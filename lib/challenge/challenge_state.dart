import 'dare_card.dart';
import '../player.dart';

/// The type of challenge the challenger can choose.
enum ChallengeType {
  dare('Dare'),
  rockPaperScissors('Rock Paper Scissors'),
  trivia('Trivia');

  const ChallengeType(this.label);

  /// Human-readable name shown in the UI.
  final String label;
}

/// The current phase of an active challenge.
enum ChallengePhase {
  /// Awaiting finger placement and challenger selection.
  selection,

  /// Challenger is choosing the challenge type (Dare/RPS/Trivia).
  typeSelection,

  /// Challenge is in progress (RPS rounds, trivia question, dare flow).
  inProgress,

  /// Challenge has been resolved; result is known.
  resolved,
}

/// The outcome of a resolved challenge.
enum ChallengeResult {
  /// Challenger takes the shot (challenger lost / dare completed).
  challengerPenalty,

  /// Challenged player takes the shot (challenger won / dare refused).
  challengedPenalty,
}

/// Immutable snapshot of an active or completed challenge.
///
/// The challenge engine creates one of these when a player refuses to drink
/// and manages it through to resolution. The challenge is a single resolution
/// event — once resolved, the penalty recipient is determined and the game
/// returns to normal flow.
class ChallengeState {
  const ChallengeState({
    required this.challengedPlayer,
    this.challenger,
    this.type,
    this.phase = ChallengePhase.selection,
    this.result,
    this.resolved = false,
    this.eligiblePlayers = const [],
    this.currentDare,
  });

  /// The player who refused to drink (the one being challenged).
  final Player challengedPlayer;

  /// The randomly selected challenger. Null until selection completes.
  final Player? challenger;

  /// The challenge type chosen by the challenger. Null until type selection.
  final ChallengeType? type;

  /// Current phase of the challenge flow.
  final ChallengePhase phase;

  /// The outcome, set once the challenge resolves.
  final ChallengeResult? result;

  /// Whether this challenge has been fully resolved and its penalty applied.
  final bool resolved;

  /// The players eligible to be selected as challenger (everyone except
  /// the challenged player). Set when the challenge begins.
  final List<Player> eligiblePlayers;

  /// The current Dare card if the challenge type is Dare and a card has been
  /// drawn. Null for non-Dare challenges.
  final DareCard? currentDare;

  /// Creates a new challenge in the selection phase.
  factory ChallengeState.begin({
    required Player challengedPlayer,
    required List<Player> eligiblePlayers,
  }) {
    return ChallengeState(
      challengedPlayer: challengedPlayer,
      eligiblePlayers: List.unmodifiable(eligiblePlayers),
      phase: ChallengePhase.selection,
      resolved: false,
    );
  }

  /// Returns a copy with the given fields replaced.
  ChallengeState copyWith({
    Player? challenger,
    ChallengeType? type,
    ChallengePhase? phase,
    ChallengeResult? result,
    bool? resolved,
    DareCard? currentDare,
  }) {
    return ChallengeState(
      challengedPlayer: challengedPlayer,
      eligiblePlayers: eligiblePlayers,
      challenger: challenger ?? this.challenger,
      type: type ?? this.type,
      phase: phase ?? this.phase,
      result: result ?? this.result,
      resolved: resolved ?? this.resolved,
      currentDare: currentDare ?? this.currentDare,
    );
  }

  /// Whether the challenge is currently active (not yet resolved).
  bool get isActive => !resolved;

  /// Whether we are waiting for the challenger to choose a challenge type.
  bool get awaitingTypeSelection =>
      phase == ChallengePhase.typeSelection &&
      challenger != null &&
      type == null;

  /// Whether the penalty recipient has been determined.
  bool get hasPenaltyRecipient => result != null;

  /// The player who must take the shot after resolution.
  Player? get penaltyRecipient {
    if (result == null || challenger == null) return null;
    return switch (result!) {
      ChallengeResult.challengerPenalty => challenger,
      ChallengeResult.challengedPenalty => challengedPlayer,
    };
  }
}
