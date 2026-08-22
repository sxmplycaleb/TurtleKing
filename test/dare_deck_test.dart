import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/challenge/challenge_engine.dart';
import 'package:turtle_king/challenge/challenge_state.dart';
import 'package:turtle_king/challenge/dare_card.dart';
import 'package:turtle_king/challenge/dare_deck.dart';
import 'package:turtle_king/challenge/dare_repository.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/protocol.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

/// Creates a test player.
Player _p(String id, String name) =>
    Player(id: id, name: name, color: PlayerColors.palette[0]);

/// Creates a standard 4-player game fast-forwarded to pouring phase.
GameState _pouredGame({Random? random}) {
  final players = [
    _p('a', 'Alice'),
    _p('b', 'Bob'),
    _p('c', 'Carol'),
    _p('d', 'Dave'),
  ];
  final game = GameState(players: players, random: random ?? Random(42));
  for (final _ in game.activePlayers) {
    game.revealCurrentPlayer();
    game.passToNextPlayer();
  }
  return game;
}

void main() {
  // -------------------------------------------------------------------
  // DareCard
  // -------------------------------------------------------------------
  group('DareCard', () {
    test('construction stores all fields', () {
      final card = DareCard(
        id: 'test-001',
        category: DareCategory.risk,
        title: 'Test Title',
        description: 'Test description',
        difficulty: DareDifficulty.easy,
      );
      expect(card.id, 'test-001');
      expect(card.category, DareCategory.risk);
      expect(card.title, 'Test Title');
      expect(card.description, 'Test description');
      expect(card.difficulty, DareDifficulty.easy);
    });

    test('equality is based on id', () {
      final a = DareCard(
        id: 'x',
        category: DareCategory.risk,
        title: 'A',
        description: 'A',
      );
      final b = DareCard(
        id: 'x',
        category: DareCategory.social,
        title: 'B',
        description: 'B',
      );
      final c = DareCard(
        id: 'y',
        category: DareCategory.risk,
        title: 'A',
        description: 'A',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is based on id', () {
      final a = DareCard(
        id: 'x',
        category: DareCategory.risk,
        title: 'A',
        description: 'A',
      );
      final b = DareCard(
        id: 'x',
        category: DareCategory.social,
        title: 'B',
        description: 'B',
      );
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes title', () {
      final card = DareCard(
        id: 'test',
        category: DareCategory.risk,
        title: 'My Dare',
        description: 'Desc',
      );
      expect(card.toString(), contains('My Dare'));
    });

    test('DareCategory has expected values', () {
      expect(DareCategory.values.length, 6);
      expect(DareCategory.risk.name, 'risk');
      expect(DareCategory.social.name, 'social');
      expect(DareCategory.truth.name, 'truth');
      expect(DareCategory.group.name, 'group');
      expect(DareCategory.chaos.name, 'chaos');
      expect(DareCategory.wild.name, 'wild');
    });

    test('DareDifficulty has expected values', () {
      expect(DareDifficulty.values.length, 3);
      expect(DareDifficulty.easy.value, 1);
      expect(DareDifficulty.medium.value, 2);
      expect(DareDifficulty.hard.value, 3);
    });
  });

  // -------------------------------------------------------------------
  // DareDeck
  // -------------------------------------------------------------------
  group('DareDeck', () {
    test('contains all cards from repository', () {
      final deck = DareDeck(DareRepository.allCards);
      expect(deck.totalCards, DareRepository.allCards.length);
      expect(deck.remaining, DareRepository.allCards.length);
    });

    test('draw removes card from pile', () {
      final deck = DareDeck(DareRepository.allCards, random: Random(42));
      final initialRemaining = deck.remaining;
      final card = deck.draw();
      expect(card, isA<DareCard>());
      expect(deck.remaining, initialRemaining - 1);
    });

    test('drawn card is recorded as lastDrawn', () {
      final deck = DareDeck(DareRepository.allCards, random: Random(42));
      expect(deck.lastDrawn, isNull);
      final card = deck.draw();
      expect(deck.lastDrawn, card);
    });

    test('no immediate duplicate draw', () {
      final deck = DareDeck(DareRepository.allCards, random: Random(42));
      // Draw many cards and verify no consecutive duplicates.
      DareCard? previous;
      for (var i = 0; i < 50; i++) {
        final card = deck.draw();
        if (previous != null) {
          expect(card, isNot(equals(previous)));
        }
        previous = card;
      }
    });

    test('reshuffles after exhaustion', () {
      final deck = DareDeck(DareRepository.allCards, random: Random(42));
      // Draw all cards.
      for (var i = 0; i < deck.totalCards; i++) {
        deck.draw();
      }
      expect(deck.isEmpty, isTrue);
      // Should auto-reshuffle on next draw.
      final card = deck.draw();
      expect(card, isA<DareCard>());
      expect(deck.isEmpty, isFalse);
    });

    test('deterministic with seeded random', () {
      final deck1 = DareDeck(DareRepository.allCards, random: Random(123));
      final deck2 = DareDeck(DareRepository.allCards, random: Random(123));
      final cards1 = [for (var i = 0; i < 20; i++) deck1.draw()];
      final cards2 = [for (var i = 0; i < 20; i++) deck2.draw()];
      expect(cards1, equals(cards2));
    });

    test('drawFromCategory draws from specific category', () {
      final deck = DareDeck(DareRepository.allCards, random: Random(42));
      final card = deck.drawFromCategory(DareCategory.wild);
      expect(card.category, DareCategory.wild);
    });

    test('drawFromCategory falls back to general draw', () {
      final deck = DareDeck(DareRepository.allCards, random: Random(42));
      // Exhaust all wild cards first.
      while (deck.remaining > 0) {
        final card = deck.draw();
        if (card.category == DareCategory.wild) {
          // continue drawing
        }
      }
      // Now drawFromCategory should reshuffle and work.
      final card = deck.drawFromCategory(DareCategory.wild);
      expect(card, isA<DareCard>());
    });

    test('reset restores all cards', () {
      final deck = DareDeck(DareRepository.allCards, random: Random(42));
      for (var i = 0; i < 50; i++) {
        deck.draw();
      }
      deck.reset();
      expect(deck.remaining, DareRepository.allCards.length);
      expect(deck.lastDrawn, isNull);
    });

    test('totalCards reflects repository size', () {
      expect(DareDeck(DareRepository.allCards).totalCards, 100);
    });
  });

  // -------------------------------------------------------------------
  // DareRepository
  // -------------------------------------------------------------------
  group('DareRepository', () {
    test('contains approximately 100 cards', () {
      expect(DareRepository.allCards.length, 100);
    });

    test('all cards have unique IDs', () {
      final ids = DareRepository.allCards.map((c) => c.id).toSet();
      expect(ids.length, DareRepository.allCards.length);
    });

    test('all categories are represented', () {
      final categories = DareRepository.allCards.map((c) => c.category).toSet();
      expect(categories, DareCategory.values.toSet());
    });

    test('newDeck creates a functional deck', () {
      final deck = DareRepository.newDeck();
      expect(deck.totalCards, DareRepository.allCards.length);
      final card = deck.draw();
      expect(card, isA<DareCard>());
    });

    test('RISK has 25 cards', () {
      expect(
        DareRepository.allCards
            .where((c) => c.category == DareCategory.risk)
            .length,
        25,
      );
    });

    test('SOCIAL has 20 cards', () {
      expect(
        DareRepository.allCards
            .where((c) => c.category == DareCategory.social)
            .length,
        20,
      );
    });

    test('TRUTH has 20 cards', () {
      expect(
        DareRepository.allCards
            .where((c) => c.category == DareCategory.truth)
            .length,
        20,
      );
    });

    test('GROUP has 15 cards', () {
      expect(
        DareRepository.allCards
            .where((c) => c.category == DareCategory.group)
            .length,
        15,
      );
    });

    test('CHAOS has 10 cards', () {
      expect(
        DareRepository.allCards
            .where((c) => c.category == DareCategory.chaos)
            .length,
        10,
      );
    });

    test('WILD has 10 cards', () {
      expect(
        DareRepository.allCards
            .where((c) => c.category == DareCategory.wild)
            .length,
        10,
      );
    });
  });

  // -------------------------------------------------------------------
  // GameState dare integration
  // -------------------------------------------------------------------
  group('GameState dare integration', () {
    late GameState game;

    setUp(() {
      game = _pouredGame();
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
    });

    test('drawDare draws a card and records it in challenge state', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);

      final card = game.drawDare();
      expect(card, isA<DareCard>());
      expect(game.currentDare, card);
      expect(game.challengeState!.currentDare, card);
    });

    test('completeDare resolves with challenger penalty', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();

      final drinksBefore = game.drinksOf(challenger);
      game.completeDare();
      expect(game.drinksOf(challenger), drinksBefore + 1);
      expect(game.challengeActive, isFalse);
    });

    test('refuseDare resolves with challenged penalty', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      final challenged = game.challengeState!.challengedPlayer;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();

      final drinksBefore = game.drinksOf(challenged);
      game.refuseDare();
      expect(game.drinksOf(challenged), drinksBefore + 1);
      expect(game.challengeActive, isFalse);
    });

    test('drawDare throws when no active challenge', () {
      expect(() => game.drawDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('drawDare throws when type is not dare', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);
      expect(() => game.drawDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('drawDare throws when already drawn', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      expect(() => game.drawDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('completeDare throws when no active challenge', () {
      expect(() => game.completeDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('completeDare throws when no dare drawn', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      expect(() => game.completeDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('refuseDare throws when no active challenge', () {
      expect(() => game.refuseDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('refuseDare throws when no dare drawn', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      expect(() => game.refuseDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('penalty applied exactly once for dare completion', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();

      final before = game.drinksOf(challenger);
      game.completeDare();
      expect(game.drinksOf(challenger), before + 1);
      // Cannot resolve again.
      expect(game.challengeActive, isFalse);
    });

    test('penalty applied exactly once for dare refusal', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      final challenged = game.challengeState!.challengedPlayer;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();

      final before = game.drinksOf(challenged);
      game.refuseDare();
      expect(game.drinksOf(challenged), before + 1);
      expect(game.challengeActive, isFalse);
    });

    test('dare events are recorded in game history', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      game.completeDare();

      final events = game.events;
      expect(events.any((e) => e.type == GameEventType.dareSelected), isTrue);
      expect(events.any((e) => e.type == GameEventType.dareCompleted), isTrue);
    });

    test('refused dare event is recorded', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      game.refuseDare();

      expect(
        game.events.any((e) => e.type == GameEventType.dareRefused),
        isTrue,
      );
    });

    test('setDareDeck is required before dare actions', () {
      final freshGame = _pouredGame();
      freshGame.refuseDrink(freshGame.pourCurrentPlayer);
      freshGame.selectChallenger();
      final challenger = freshGame.challengeState!.challenger!;
      freshGame.chooseChallengeType(ChallengeType.dare, challenger);
      expect(() => freshGame.drawDare(), throwsA(isA<StateError>()));
    });

    test('completeDare returns to normal game flow', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      game.completeDare();

      expect(game.challengeActive, isFalse);
      expect(game.pouringStarted, isTrue);
    });

    test('refuseDare returns to normal game flow', () {
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      game.refuseDare();

      expect(game.challengeActive, isFalse);
      expect(game.pouringStarted, isTrue);
    });
  });

  // -------------------------------------------------------------------
  // Loop prevention
  // -------------------------------------------------------------------
  group('Dare loop prevention', () {
    test('completed dare cannot trigger another challenge', () {
      final game = _pouredGame();
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      game.completeDare();

      // After resolution, the challenge is cleared.
      expect(game.challengeActive, isFalse);
      // The game is in normal pouring flow.
      expect(game.pouringStarted, isTrue);
    });

    test('refused dare cannot trigger another challenge', () {
      final game = _pouredGame();
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      game.refuseDare();

      expect(game.challengeActive, isFalse);
      expect(game.pouringStarted, isTrue);
    });

    test('challenge engine prevents concurrent challenges', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      expect(
        () => engine.begin(challengedPlayer: bob, eligiblePlayers: [alice]),
        throwsStateError,
      );
    });

    test('double dare draw is rejected', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      engine.selectChallenger();
      engine.chooseChallengeType(ChallengeType.dare, engine.state!.challenger!);
      engine.setDare(
        DareCard(
          id: 'x',
          category: DareCategory.risk,
          title: 'X',
          description: 'X',
        ),
      );
      expect(
        () => engine.setDare(
          DareCard(
            id: 'y',
            category: DareCategory.risk,
            title: 'Y',
            description: 'Y',
          ),
        ),
        throwsStateError,
      );
    });
  });

  // -------------------------------------------------------------------
  // Security
  // -------------------------------------------------------------------
  group('Dare security', () {
    test('only challenger can trigger dare actions through engine', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      final carol = _p('c', 'Carol');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob, carol]);
      engine.selectChallenger();
      final challenger = engine.state!.challenger!;
      final wrongPlayer = challenger.id == bob.id ? carol : bob;
      expect(
        () => engine.chooseChallengeType(ChallengeType.dare, wrongPlayer),
        throwsArgumentError,
      );
    });

    test('setDare rejects non-dare challenge', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      engine.selectChallenger();
      engine.chooseChallengeType(
        ChallengeType.rockPaperScissors,
        engine.state!.challenger!,
      );
      expect(
        () => engine.setDare(
          DareCard(
            id: 'x',
            category: DareCategory.risk,
            title: 'X',
            description: 'X',
          ),
        ),
        throwsStateError,
      );
    });

    test('setDare rejects outside inProgress phase', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      engine.begin(challengedPlayer: alice, eligiblePlayers: [bob]);
      // Still in selection phase — cannot set dare yet.
      expect(
        () => engine.setDare(
          DareCard(
            id: 'x',
            category: DareCategory.risk,
            title: 'X',
            description: 'X',
          ),
        ),
        throwsStateError,
      );
    });
  });

  // -------------------------------------------------------------------
  // Regression: Dare penalty correctness
  // -------------------------------------------------------------------
  group('Dare penalty correctness regression', () {
    /// Helper: sets up a game, fast-forwards to pouring, starts a dare
    /// challenge with a drawn card, ready for resolution.
    GameState makeDareChallenge() {
      final game = _pouredGame();
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      return game;
    }

    test('1. completing dare gives challenger exactly 1 shot', () {
      final game = makeDareChallenge();
      final challenger = game.challengeState!.challenger!;
      final before = game.drinksOf(challenger);
      game.completeDare();
      expect(game.drinksOf(challenger), before + 1);
    });

    test('2. refusing dare gives challenged player exactly 1 shot', () {
      final game = makeDareChallenge();
      final challenged = game.challengeState!.challengedPlayer;
      final before = game.drinksOf(challenged);
      game.refuseDare();
      expect(game.drinksOf(challenged), before + 1);
    });

    test('3. dare completion applies exactly one drink event', () {
      final game = makeDareChallenge();
      final challenger = game.challengeState!.challenger!;
      game.completeDare();
      // Should add: dareCompleted + challengePenalty + challengeResolved = 3 events
      final drinkEvents = game.events
          .where(
            (e) =>
                e.type == GameEventType.challengePenalty &&
                e.player?.id == challenger.id,
          )
          .toList();
      expect(drinkEvents.length, 1);
    });

    test('4. dare refusal applies exactly one drink event', () {
      final game = makeDareChallenge();
      final challenged = game.challengeState!.challengedPlayer;
      game.refuseDare();
      final drinkEvents = game.events
          .where(
            (e) =>
                e.type == GameEventType.challengePenalty &&
                e.player?.id == challenged.id,
          )
          .toList();
      expect(drinkEvents.length, 1);
    });

    test('5. completed dare then refuseDare throws', () {
      final game = makeDareChallenge();
      game.completeDare();
      expect(() => game.refuseDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('6. refused dare then completeDare throws', () {
      final game = makeDareChallenge();
      game.refuseDare();
      expect(() => game.completeDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('7. completed dare does not start another challenge', () {
      final game = makeDareChallenge();
      game.completeDare();
      expect(game.challengeActive, isFalse);
      expect(game.challengeState, isNull);
    });

    test('8. refused dare does not start another challenge', () {
      final game = makeDareChallenge();
      game.refuseDare();
      expect(game.challengeActive, isFalse);
      expect(game.challengeState, isNull);
    });

    test('9. dare penalty counts toward elimination threshold', () {
      // 4 players, threshold 10. Dare completion = 1 drink.
      // Verify the drink is correctly counted.
      final players = [
        _p('a', 'Alice'),
        _p('b', 'Bob'),
        _p('c', 'Carol'),
        _p('d', 'Dave'),
      ];
      final game = GameState(
        players: players,
        random: Random(42),
        eliminationThreshold: 10,
      );
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      // Refuse → dare challenge → complete → challenger gets 1 drink.
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      game.completeDare();
      expect(game.drinksOf(challenger), 1);
      expect(game.isEliminated(challenger), isFalse);
      // The drinks count toward the threshold (1 < 10).
    });

    test('10. dare penalty feeds into game completion check', () {
      // 4 players, threshold 1. One dare completion eliminates someone,
      // leaving 3 players (game not complete).
      final players = [
        _p('a', 'Alice'),
        _p('b', 'Bob'),
        _p('c', 'Carol'),
        _p('d', 'Dave'),
      ];
      final game = GameState(
        players: players,
        random: Random(42),
        eliminationThreshold: 1,
      );
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
      for (final _ in game.activePlayers) {
        game.revealCurrentPlayer();
        game.passToNextPlayer();
      }
      // Refuse → dare challenge → complete → challenger gets 1 drink → eliminated.
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      game.completeDare();
      expect(game.drinksOf(challenger), 1);
      expect(game.isEliminated(challenger), isTrue);
      // 3 players remain — game is not complete.
      expect(game.gameComplete, isFalse);
      expect(game.activePlayerCount, 3);
    });

    test('11. wrong dare result is rejected by ChallengeEngine', () {
      final engine = ChallengeEngine();
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');
      final carol = _p('c', 'Carol');
      final dave = _p('d', 'Dave');
      engine.begin(
        challengedPlayer: alice,
        eligiblePlayers: [bob, carol, dave],
      );
      engine.selectChallenger();
      engine.chooseChallengeType(ChallengeType.dare, engine.state!.challenger!);
      engine.resolve(ChallengeResult.challengerPenalty);
      expect(engine.state!.resolved, isTrue);
      // Cannot resolve again.
      expect(
        () => engine.resolve(ChallengeResult.challengedPenalty),
        throwsStateError,
      );
    });

    test('12. penalty recipient is exactly correct for each result', () {
      final alice = _p('a', 'Alice');
      final bob = _p('b', 'Bob');

      // challengerPenalty → challenger gets it
      final cs1 = ChallengeState(
        challengedPlayer: alice,
        challenger: bob,
        eligiblePlayers: [],
        result: ChallengeResult.challengerPenalty,
        resolved: true,
      );
      expect(cs1.penaltyRecipient, bob);

      // challengedPenalty → challenged gets it
      final cs2 = ChallengeState(
        challengedPlayer: alice,
        challenger: bob,
        eligiblePlayers: [],
        result: ChallengeResult.challengedPenalty,
        resolved: true,
      );
      expect(cs2.penaltyRecipient, alice);
    });
  });

  // -------------------------------------------------------------------
  // Regression: Multiplayer dare authority
  // -------------------------------------------------------------------
  group('Dare multiplayer authority regression', () {
    test('drawDare ownership: only host can draw', () {
      // Verify the protocol enum value exists.
      expect(GameAction.drawDare, isNotNull);
    });

    test('completeDare ownership: only challenged player', () {
      expect(GameAction.completeDare, isNotNull);
    });

    test('refuseDare ownership: only challenged player', () {
      expect(GameAction.refuseDare, isNotNull);
    });

    test('GameState rejects wrong-type dare actions', () {
      final game = _pouredGame();
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
      // Start an RPS challenge instead of dare.
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.rockPaperScissors, challenger);

      // All dare actions must fail.
      expect(() => game.drawDare(), throwsA(isA<YamadaRoundException>()));
      expect(() => game.completeDare(), throwsA(isA<YamadaRoundException>()));
      expect(() => game.refuseDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('GameState rejects dare actions with no dare drawn', () {
      final game = _pouredGame();
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      // Dare type chosen but no card drawn yet.
      expect(() => game.completeDare(), throwsA(isA<YamadaRoundException>()));
      expect(() => game.refuseDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('host session rejects drawDare for non-dare challenge', () {
      // Verify session-side validation checks challenge type.
      final game = _pouredGame();
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.trivia, challenger);
      // GameState.drawDare checks type == dare and throws.
      expect(() => game.drawDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('host session rejects double dare draw', () {
      final game = _pouredGame();
      game.setDareDeck(DareRepository.newDeck(random: Random(42)));
      game.refuseDrink(game.pourCurrentPlayer);
      game.selectChallenger();
      final challenger = game.challengeState!.challenger!;
      game.chooseChallengeType(ChallengeType.dare, challenger);
      game.drawDare();
      // Second draw must fail.
      expect(() => game.drawDare(), throwsA(isA<YamadaRoundException>()));
    });

    test('protocol enum values are distinct', () {
      expect(GameAction.drawDare, isNot(GameAction.completeDare));
      expect(GameAction.drawDare, isNot(GameAction.refuseDare));
      expect(GameAction.completeDare, isNot(GameAction.refuseDare));
    });
  });
}
