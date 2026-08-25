import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/challenge/challenge_engine.dart';
import 'package:turtle_king/challenge/challenge_state.dart';
import 'package:turtle_king/challenge/trivia_card.dart';
import 'package:turtle_king/challenge/trivia_deck.dart';
import 'package:turtle_king/challenge/trivia_repository.dart';
import 'package:turtle_king/challenge/trivia_state.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/driver.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

void main() {
  List<Player> makePlayers(int count) => [
    for (var i = 0; i < count; i++)
      Player(
        id: 'player-$i',
        name: 'Player $i',
        color: PlayerColors.palette[i],
      ),
  ];

  /// Fast-forwards through the viewing phase so the pouring phase begins.
  void viewAll(GameState game) {
    while (!game.pouringStarted) {
      game.revealCurrentPlayer();
      game.passToNextPlayer();
    }
  }

  group('TriviaCard', () {
    test('construction with all fields', () {
      final card = TriviaCard(
        id: 'test-001',
        category: TriviaCategory.generalKnowledge,
        question: 'What is 2 + 2?',
        answer: '4',
        difficulty: TriviaDifficulty.easy,
        isPersonal: true,
        isGroupQuestion: true,
        aToZLetter: 'A',
        aToZCategory: 'Countries',
      );

      expect(card.id, 'test-001');
      expect(card.category, TriviaCategory.generalKnowledge);
      expect(card.question, 'What is 2 + 2?');
      expect(card.answer, '4');
      expect(card.difficulty, TriviaDifficulty.easy);
      expect(card.isPersonal, isTrue);
      expect(card.isGroupQuestion, isTrue);
      expect(card.aToZLetter, 'A');
      expect(card.aToZCategory, 'Countries');
    });

    test('equality based on id', () {
      final card1 = TriviaCard(
        id: 'test-001',
        category: TriviaCategory.generalKnowledge,
        question: 'Question 1',
        answer: 'Answer 1',
      );
      final card2 = TriviaCard(
        id: 'test-001',
        category: TriviaCategory.geography,
        question: 'Question 2',
        answer: 'Answer 2',
      );
      final card3 = TriviaCard(
        id: 'test-002',
        category: TriviaCategory.generalKnowledge,
        question: 'Question 1',
        answer: 'Answer 1',
      );

      expect(card1, equals(card2));
      expect(card1, isNot(equals(card3)));
    });
  });

  group('TriviaDeck', () {
    test('creates deck from cards', () {
      final cards = [
        TriviaCard(
          id: '1',
          category: TriviaCategory.generalKnowledge,
          question: 'Q1',
          answer: 'A1',
        ),
        TriviaCard(
          id: '2',
          category: TriviaCategory.generalKnowledge,
          question: 'Q2',
          answer: 'A2',
        ),
        TriviaCard(
          id: '3',
          category: TriviaCategory.generalKnowledge,
          question: 'Q3',
          answer: 'A3',
        ),
      ];

      final deck = TriviaDeck(cards, random: Random(42));

      expect(deck.totalCards, 3);
      expect(deck.remaining, 3);
    });

    test('draw removes card from pile', () {
      final cards = [
        TriviaCard(
          id: '1',
          category: TriviaCategory.generalKnowledge,
          question: 'Q1',
          answer: 'A1',
        ),
        TriviaCard(
          id: '2',
          category: TriviaCategory.generalKnowledge,
          question: 'Q2',
          answer: 'A2',
        ),
      ];

      final deck = TriviaDeck(cards, random: Random(42));

      final drawn = deck.draw();
      expect(drawn.id, isNotEmpty);
      expect(deck.remaining, 1);
    });

    test('draw does not repeat immediately', () {
      final cards = [
        TriviaCard(
          id: '1',
          category: TriviaCategory.generalKnowledge,
          question: 'Q1',
          answer: 'A1',
        ),
        TriviaCard(
          id: '2',
          category: TriviaCategory.generalKnowledge,
          question: 'Q2',
          answer: 'A2',
        ),
      ];

      final deck = TriviaDeck(cards, random: Random(42));

      final drawn1 = deck.draw();
      final drawn2 = deck.draw();

      expect(drawn1.id, isNot(equals(drawn2.id)));
    });

    test('draw reshuffles when exhausted', () {
      final cards = [
        TriviaCard(
          id: '1',
          category: TriviaCategory.generalKnowledge,
          question: 'Q1',
          answer: 'A1',
        ),
      ];

      final deck = TriviaDeck(cards, random: Random(42));

      // Draw the only card
      final drawn1 = deck.draw();
      expect(deck.remaining, 0);

      // Draw again - should reshuffle
      final drawn2 = deck.draw();
      expect(deck.remaining, 0);
      expect(drawn1.id, equals(drawn2.id));
    });

    test('drawFromCategory draws from specific category', () {
      final cards = [
        TriviaCard(
          id: '1',
          category: TriviaCategory.generalKnowledge,
          question: 'Q1',
          answer: 'A1',
        ),
        TriviaCard(
          id: '2',
          category: TriviaCategory.geography,
          question: 'Q2',
          answer: 'A2',
        ),
      ];

      final deck = TriviaDeck(cards, random: Random(42));

      final drawn = deck.drawFromCategory(TriviaCategory.geography);
      expect(drawn.category, TriviaCategory.geography);
    });

    test('drawPersonalQuestion draws personal question', () {
      final cards = [
        TriviaCard(
          id: '1',
          category: TriviaCategory.generalKnowledge,
          question: 'Q1',
          answer: 'A1',
        ),
        TriviaCard(
          id: '2',
          category: TriviaCategory.personal,
          question: 'Q2',
          answer: 'A2',
          isPersonal: true,
        ),
      ];

      final deck = TriviaDeck(cards, random: Random(42));

      final drawn = deck.drawPersonalQuestion();
      expect(drawn.isPersonal, isTrue);
    });
  });

  group('TriviaRepository', () {
    test('newDeck creates a deck with cards', () {
      final deck = TriviaRepository.newDeck(random: Random(42));

      expect(deck.totalCards, greaterThan(0));
      expect(deck.remaining, deck.totalCards);
    });

    test('deck contains all categories', () {
      final deck = TriviaRepository.newDeck(random: Random(42));
      final categories = <TriviaCategory>{};

      // Draw all cards to check categories
      for (var i = 0; i < deck.totalCards; i++) {
        final card = deck.draw();
        categories.add(card.category);
      }

      expect(categories, contains(TriviaCategory.generalKnowledge));
      expect(categories, contains(TriviaCategory.geography));
      expect(categories, contains(TriviaCategory.history));
      expect(categories, contains(TriviaCategory.science));
      expect(categories, contains(TriviaCategory.technology));
      expect(categories, contains(TriviaCategory.sports));
      expect(categories, contains(TriviaCategory.music));
      expect(categories, contains(TriviaCategory.moviesAndTv));
      expect(categories, contains(TriviaCategory.food));
      expect(categories, contains(TriviaCategory.kenyaAfrica));
      expect(categories, contains(TriviaCategory.personal));
      expect(categories, contains(TriviaCategory.aToZ));
      expect(categories, contains(TriviaCategory.rapidFire));
    });
  });

  group('TriviaState', () {
    test('initial state is correct', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      final state = TriviaState(
        challengedPlayer: alice,
        challenger: bob,
        question: card,
      );

      expect(state.phase, TriviaPhase.questionReady);
      expect(state.isCorrect, isNull);
      expect(state.resolved, isFalse);
      expect(state.isInProgress, isTrue);
      expect(state.readyToResolve, isFalse);
    });

    test('copyWith preserves other fields', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      final state = TriviaState(
        challengedPlayer: alice,
        challenger: bob,
        question: card,
      );

      final updated = state.copyWith(
        isCorrect: true,
        phase: TriviaPhase.answered,
      );

      expect(updated.isCorrect, isTrue);
      expect(updated.phase, TriviaPhase.answered);
      expect(updated.challengedPlayer, alice);
      expect(updated.challenger, bob);
    });
  });

  group('ChallengeEngine Trivia', () {
    test('startTrivia creates Trivia state', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final carol = Player(
        id: 'c',
        name: 'Carol',
        color: PlayerColors.palette[2],
      );
      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      final engine = ChallengeEngine(random: Random(0));
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      engine.chooseChallengeType(ChallengeType.trivia, challenger);

      final trivia = engine.startTrivia(card);
      expect(trivia, isNotNull);
      expect(trivia.challengedPlayer, alice);
      expect(trivia.challenger, challenger);
      expect(trivia.question, card);
      expect(engine.state!.triviaState, trivia);
    });

    test('recordTriviaAnswer records answer', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final carol = Player(
        id: 'c',
        name: 'Carol',
        color: PlayerColors.palette[2],
      );
      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      final engine = ChallengeEngine(random: Random(0));
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      engine.chooseChallengeType(ChallengeType.trivia, challenger);
      engine.startTrivia(card);

      engine.recordTriviaAnswer(true);
      expect(engine.state!.triviaState!.isCorrect, isTrue);
      expect(engine.state!.triviaState!.phase, TriviaPhase.answered);
    });

    test('resolveTrivia resolves challenge', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final carol = Player(
        id: 'c',
        name: 'Carol',
        color: PlayerColors.palette[2],
      );
      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      final engine = ChallengeEngine(random: Random(0));
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      engine.chooseChallengeType(ChallengeType.trivia, challenger);
      engine.startTrivia(card);

      engine.recordTriviaAnswer(true);
      final result = engine.resolveTrivia(ChallengeResult.challengerPenalty);

      expect(result.resolved, isTrue);
      expect(result.penaltyRecipient, challenger);
    });

    test('resolveTrivia rejects mismatched result', () {
      final alice = Player(
        id: 'a',
        name: 'Alice',
        color: PlayerColors.palette[0],
      );
      final bob = Player(id: 'b', name: 'Bob', color: PlayerColors.palette[1]);
      final carol = Player(
        id: 'c',
        name: 'Carol',
        color: PlayerColors.palette[2],
      );
      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      final engine = ChallengeEngine(random: Random(0));
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      engine.chooseChallengeType(ChallengeType.trivia, challenger);
      engine.startTrivia(card);

      engine.recordTriviaAnswer(true);

      // Wrong result - correct answer should be challengerPenalty
      expect(
        () => engine.resolveTrivia(ChallengeResult.challengedPenalty),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('GameState Trivia', () {
    test('startTrivia creates Trivia state in game', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      final trivia = game.startTrivia(card);
      expect(trivia, isNotNull);
      expect(game.triviaState, trivia);
    });

    test('recordTriviaAnswer records answer', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);
      game.recordTriviaAnswer(true);

      expect(game.triviaState!.isCorrect, isTrue);
    });

    test('resolveTrivia applies penalty correctly', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);
      game.recordTriviaAnswer(true);

      // Correct answer → challenger takes penalty
      game.resolveTrivia(ChallengeResult.challengerPenalty);

      expect(game.challengeActive, isFalse);
      expect(game.drinksOf(challenger), 1);
    });

    test('resolveTrivia applies penalty for wrong answer', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      final challenged = game.challengeState!.challengedPlayer;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);
      game.recordTriviaAnswer(false);

      // Wrong answer → challenged player takes penalty
      game.resolveTrivia(ChallengeResult.challengedPenalty);

      expect(game.challengeActive, isFalse);
      expect(game.drinksOf(challenged), 1);
    });

    test('resolveTrivia rejects if not answered', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);

      // Try to resolve without answering
      expect(
        () => game.resolveTrivia(ChallengeResult.challengerPenalty),
        throwsA(isA<YamadaRoundException>()),
      );
    });
  });

  group('Trivia loop prevention', () {
    test('cannot start another challenge during Trivia', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);

      // Try to start another challenge
      expect(
        () => game.refuseDrink(game.pourCurrentPlayer),
        throwsA(isA<StateError>()),
      );
    });

    test('resolved Trivia cannot be resolved again', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);
      game.recordTriviaAnswer(true);
      game.resolveTrivia(ChallengeResult.challengerPenalty);

      // Try to resolve again
      expect(
        () => game.resolveTrivia(ChallengeResult.challengerPenalty),
        throwsA(isA<YamadaRoundException>()),
      );
    });

    test('Trivia cannot trigger Dare', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);

      expect(() => game.drawDare(), throwsA(isA<YamadaRoundException>()));
    });
  });

  group('Trivia game history', () {
    test('Trivia events are recorded', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);
      game.recordTriviaAnswer(true);
      game.resolveTrivia(ChallengeResult.challengerPenalty);

      final events = game.events;
      expect(events.any((e) => e.type == GameEventType.triviaStarted), isTrue);
      expect(events.any((e) => e.type == GameEventType.triviaCorrect), isTrue);
      expect(events.any((e) => e.type == GameEventType.triviaResolved), isTrue);
      expect(
        events.any((e) => e.type == GameEventType.challengePenalty),
        isTrue,
      );
    });
  });

  group('LocalDriver Trivia', () {
    test('startTrivia delegates to GameState', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      final driver = LocalDriver(game);
      viewAll(game);

      driver.refuseDrink(game.pourCurrentPlayer);
      driver.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      driver.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      final trivia = driver.startTrivia(card);
      expect(trivia, isNotNull);
      expect(game.triviaState, trivia);
    });

    test('recordTriviaAnswer delegates to GameState', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      final driver = LocalDriver(game);
      viewAll(game);

      driver.refuseDrink(game.pourCurrentPlayer);
      driver.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      driver.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      driver.startTrivia(card);
      driver.recordTriviaAnswer(true);

      expect(game.triviaState!.isCorrect, isTrue);
    });

    test('resolveTrivia delegates to GameState', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      final driver = LocalDriver(game);
      viewAll(game);

      driver.refuseDrink(game.pourCurrentPlayer);
      driver.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      driver.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      driver.startTrivia(card);
      driver.recordTriviaAnswer(true);
      driver.resolveTrivia(ChallengeResult.challengerPenalty);

      expect(game.challengeActive, isFalse);
      expect(game.drinksOf(challenger), 1);
    });
  });

  group('Trivia categories', () {
    test('all categories have labels', () {
      for (final category in TriviaCategory.values) {
        expect(category.label, isNotEmpty);
        expect(category.description, isNotEmpty);
      }
    });

    test('all difficulties have values', () {
      for (final difficulty in TriviaDifficulty.values) {
        expect(difficulty.value, greaterThan(0));
      }
    });
  });

  group('Trivia penalty', () {
    test('winner receives 0 shots', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      final challenged = game.challengeState!.challengedPlayer;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);
      game.recordTriviaAnswer(true);

      // Correct answer → challenger takes penalty
      game.resolveTrivia(ChallengeResult.challengerPenalty);

      expect(game.drinksOf(challenged), 0);
      expect(game.drinksOf(challenger), 1);
    });

    test('penalty applied exactly once', () {
      final players = makePlayers(4);
      final game = GameState(players: players, random: Random(42));
      viewAll(game);

      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);

      final card = TriviaCard(
        id: 'test',
        category: TriviaCategory.generalKnowledge,
        question: 'Test?',
        answer: 'Test',
      );

      game.startTrivia(card);
      game.recordTriviaAnswer(true);
      game.resolveTrivia(ChallengeResult.challengerPenalty);

      expect(game.drinksOf(challenger), 1);
      expect(game.challengeActive, isFalse);

      // Cannot resolve again
      expect(
        () => game.resolveTrivia(ChallengeResult.challengerPenalty),
        throwsA(isA<YamadaRoundException>()),
      );
    });
  });
}
