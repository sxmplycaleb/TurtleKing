import '../player.dart';

/// The outcome of a single Rock Paper Scissors round.
enum RpsRoundOutcome {
  challengedPlayerWon('Challenged Player Won'),
  challengerWon('Challenger Won'),
  draw('Draw');

  const RpsRoundOutcome(this.label);

  /// Human-readable label.
  final String label;
}

/// The result of one recorded RPS round.
class RpsRoundResult {
  const RpsRoundResult({required this.roundNumber, required this.outcome});

  /// 1-based round number (1, 2, 3, 4, ... for sudden death).
  final int roundNumber;

  /// The outcome of this round.
  final RpsRoundOutcome outcome;

  @override
  String toString() => 'RpsRoundResult(round: $roundNumber, outcome: $outcome)';
}

/// Manages the state of a Rock Paper Scissors challenge.
///
/// RPS is best-of-3: the first player to win 2 rounds wins the match.
/// Round 3 is only played if the score is 1–1 after Round 2.
/// If Round 3 is a draw, sudden death begins (Round 4, 5, 6, ...)
/// until one player wins a round.
///
/// The match resolves automatically when a player reaches 2 wins.
/// There is no manual loser selection — the loser is the non-winner.
///
/// The app does NOT detect hand gestures — it records human-reported results.
class RpsState {
  const RpsState({
    required this.challengedPlayer,
    required this.challenger,
    this.roundResults = const [],
    this.resolved = false,
  });

  /// The player who refused to drink (being challenged).
  final Player challengedPlayer;

  /// The challenger who selected RPS.
  final Player challenger;

  /// Results of completed rounds.
  final List<RpsRoundResult> roundResults;

  /// Whether the RPS match has been fully resolved.
  final bool resolved;

  /// The current round number (1-based).
  int get currentRound => roundResults.length + 1;

  /// The number of rounds won by the challenged player.
  int get challengedPlayerWins => roundResults
      .where((r) => r.outcome == RpsRoundOutcome.challengedPlayerWon)
      .length;

  /// The number of rounds won by the challenger.
  int get challengerWins => roundResults
      .where((r) => r.outcome == RpsRoundOutcome.challengerWon)
      .length;

  /// Whether the match is in sudden death.
  ///
  /// Sudden death begins when:
  /// - Score is 1–1 after 3 rounds (round 3 was a draw)
  /// - OR we're past round 3 and no one has 2 wins yet
  bool get isInSuddenDeath {
    if (roundResults.length < 3) return false;
    // After 3 rounds with 1-1 score, sudden death begins
    if (roundResults.length == 3) {
      return challengedPlayerWins == 1 && challengerWins == 1;
    }
    // Past round 3: stay in sudden death until someone wins
    return !isMatchComplete;
  }

  /// Whether the match is complete (one player has 2 wins).
  bool get isMatchComplete => challengedPlayerWins >= 2 || challengerWins >= 2;

  /// Whether the match is ready to resolve (complete and not yet resolved).
  bool get readyToResolve => isMatchComplete && !resolved;

  /// Whether the match is still in progress (no winner yet).
  bool get isInProgress => !isMatchComplete && !resolved;

  /// The winner of the match, or null if not yet complete.
  Player? get winner {
    if (!isMatchComplete) return null;
    return challengedPlayerWins >= 2 ? challengedPlayer : challenger;
  }

  /// The loser of the match, or null if not yet complete.
  Player? get loser {
    if (!isMatchComplete) return null;
    return challengedPlayerWins >= 2 ? challenger : challengedPlayer;
  }

  /// Creates a copy with the given fields replaced.
  RpsState copyWith({List<RpsRoundResult>? roundResults, bool? resolved}) {
    return RpsState(
      challengedPlayer: challengedPlayer,
      challenger: challenger,
      roundResults: roundResults ?? this.roundResults,
      resolved: resolved ?? this.resolved,
    );
  }

  @override
  String toString() =>
      'RpsState(rounds: ${roundResults.length}, '
      'score: $challengedPlayerWins-$challengerWins, '
      'resolved: $resolved, suddenDeath: $isInSuddenDeath)';
}
