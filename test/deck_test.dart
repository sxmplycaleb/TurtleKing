import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/card.dart';
import 'package:turtle_king/deck.dart';

void main() {
  group('Deck creation', () {
    List<Card> allCards() => Deck().deal(52);

    test('a new deck contains exactly 52 cards', () {
      expect(Deck().remainingCards, 52);
    });

    test('a new deck contains all four suits', () {
      final suits = allCards().map((card) => card.suit).toSet();
      expect(suits, Suit.values.toSet());
    });

    test('a new deck contains all thirteen ranks', () {
      final ranks = allCards().map((card) => card.rank).toSet();
      expect(ranks, Rank.values.toSet());
    });

    test('every suit appears exactly 13 times', () {
      final cards = allCards();
      for (final suit in Suit.values) {
        expect(cards.where((card) => card.suit == suit), hasLength(13));
      }
    });

    test('every rank appears exactly 4 times', () {
      final cards = allCards();
      for (final rank in Rank.values) {
        expect(cards.where((card) => card.rank == rank), hasLength(4));
      }
    });

    test('every suit/rank combination exists exactly once', () {
      final cards = allCards();
      for (final suit in Suit.values) {
        for (final rank in Rank.values) {
          expect(
            cards.where((card) => card.suit == suit && card.rank == rank),
            hasLength(1),
          );
        }
      }
    });

    test('a new deck has no duplicate cards', () {
      expect(allCards().toSet(), hasLength(52));
    });
  });

  group('Shuffle', () {
    test('preserves all 52 cards', () {
      final deck = Deck();
      deck.shuffle();
      expect(deck.remainingCards, 52);
    });

    test('preserves card uniqueness', () {
      final deck = Deck();
      deck.shuffle();
      expect(deck.deal(52).toSet(), hasLength(52));
    });

    test('does not create or remove cards', () {
      final deck = Deck();
      deck.shuffle();
      final shuffled = deck.deal(52).toSet();
      final fresh = Deck().deal(52).toSet();
      expect(shuffled, fresh);
    });

    test('is deterministic for a given random seed', () {
      final a = Deck(random: Random(42))..shuffle();
      final b = Deck(random: Random(42))..shuffle();
      expect(a.deal(52), b.deal(52));
    });
  });

  group('Dealing', () {
    test('dealing one card returns exactly one card', () {
      final deck = Deck();
      final card = deck.dealOne();
      expect(card, isA<Card>());
    });

    test('dealing one card reduces the remaining count from 52 to 51', () {
      final deck = Deck();
      deck.dealOne();
      expect(deck.remainingCards, 51);
    });

    test('dealt cards are removed from the deck', () {
      final deck = Deck();
      final first = deck.dealOne();
      final rest = deck.deal(deck.remainingCards);

      expect(rest, isNot(contains(first)));
      expect({first, ...rest}, Deck().deal(52).toSet());
    });

    test('dealing two cards reduces the remaining count from 52 to 50', () {
      final deck = Deck();
      deck.deal(2);
      expect(deck.remainingCards, 50);
    });

    test('dealing multiple cards returns the requested number', () {
      final deck = Deck();
      final cards = deck.deal(7);
      expect(cards, hasLength(7));
      expect(deck.remainingCards, 45);
    });

    test('dealing zero cards returns an empty list and changes nothing', () {
      final deck = Deck();
      expect(deck.deal(0), isEmpty);
      expect(deck.remainingCards, 52);
    });

    test('a fresh deck deals Ace of Hearts first', () {
      final deck = Deck();
      expect(deck.dealOne(), const Card(suit: Suit.hearts, rank: Rank.ace));
    });

    test('dealing one card at a time yields all 52 unique cards', () {
      final deck = Deck();
      final dealt = <Card>[
        for (var i = 0; i < 52; i++) deck.dealOne(),
      ];
      expect(dealt.toSet(), hasLength(52));
      expect(deck.remainingCards, 0);
    });

    test('dealing more cards than available throws EmptyDeckException', () {
      final deck = Deck();
      expect(() => deck.deal(53), throwsA(isA<EmptyDeckException>()));
    });

    test('dealing from an empty deck throws EmptyDeckException', () {
      final deck = Deck()..deal(52);
      expect(() => deck.dealOne(), throwsA(isA<EmptyDeckException>()));
      expect(() => deck.deal(1), throwsA(isA<EmptyDeckException>()));
    });

    test('dealing a negative count throws ArgumentError', () {
      final deck = Deck();
      expect(() => deck.deal(-1), throwsArgumentError);
    });
  });

  group('Reset', () {
    test('restores 52 cards after dealing', () {
      final deck = Deck()..deal(10);
      deck.reset();
      expect(deck.remainingCards, 52);
    });

    test('restores the complete standard deck', () {
      final deck = Deck()..deal(7);
      deck.reset();
      final cards = deck.deal(52);
      expect(cards.toSet(), Deck().deal(52).toSet());
      expect(cards.toSet(), hasLength(52));
    });

    test('removes the previous deck state', () {
      final deck = Deck();
      final dealt = deck.deal(5);
      deck.reset();
      final cards = deck.deal(52);
      for (final card in dealt) {
        expect(cards, contains(card));
      }
    });
  });
}
