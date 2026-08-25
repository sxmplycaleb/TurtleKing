import '../player.dart';
import 'trivia_card.dart';

/// The current phase of a trivia challenge.
enum TriviaPhase {
  /// Waiting for the question to be presented.
  questionReady,

  /// The question has been presented; awaiting answer.
  awaitingAnswer,

  /// The answer has been recorded; awaiting resolution.
  answered,

  /// The trivia challenge is fully resolved.
  resolved,
}

/// Manages the state of a Trivia challenge.
///
/// Trivia challenges can be:
/// - Standard trivia questions
/// - Personal questions about specific players
/// - Group questions about the group dynamic
/// - A-Z category challenges
/// - Rapid fire timed sequences
///
/// The app records the result (correct/wrong) and applies the penalty.
class TriviaState {
  const TriviaState({
    required this.challengedPlayer,
    required this.challenger,
    required this.question,
    this.phase = TriviaPhase.questionReady,
    this.isCorrect,
    this.resolved = false,
  });

  /// The player who refused to drink (being challenged).
  final Player challengedPlayer;

  /// The challenger who selected Trivia.
  final Player challenger;

  /// The current trivia question.
  final TriviaCard question;

  /// Current phase of the trivia challenge.
  final TriviaPhase phase;

  /// Whether the answer was correct (null until answered).
  final bool? isCorrect;

  /// Whether the trivia challenge has been fully resolved.
  final bool resolved;

  /// Whether the challenge is ready to resolve (answered but not yet resolved).
  bool get readyToResolve => phase == TriviaPhase.answered && !resolved;

  /// Whether the challenge is in progress (question presented, awaiting answer).
  bool get isInProgress =>
      phase == TriviaPhase.questionReady || phase == TriviaPhase.awaitingAnswer;

  /// Creates a copy with the given fields replaced.
  TriviaState copyWith({TriviaPhase? phase, bool? isCorrect, bool? resolved}) {
    return TriviaState(
      challengedPlayer: challengedPlayer,
      challenger: challenger,
      question: question,
      phase: phase ?? this.phase,
      isCorrect: isCorrect ?? this.isCorrect,
      resolved: resolved ?? this.resolved,
    );
  }

  @override
  String toString() =>
      'TriviaState(question: ${question.id}, phase: $phase, '
      'correct: $isCorrect, resolved: $resolved)';
}
