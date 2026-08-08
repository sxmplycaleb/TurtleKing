import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/card.dart';

void main() {
  group('Rank values', () {
    test('Ace has value 1', () {
      expect(Rank.ace.value, 1);
    });

    test('numeric ranks have their face values', () {
      expect(Rank.two.value, 2);
      expect(Rank.three.value, 3);
      expect(Rank.four.value, 4);
      expect(Rank.five.value, 5);
      expect(Rank.six.value, 6);
      expect(Rank.seven.value, 7);
      expect(Rank.eight.value, 8);
      expect(Rank.nine.value, 9);
      expect(Rank.ten.value, 10);
    });

    test('Jack has value 11', () {
      expect(Rank.jack.value, 11);
    });

    test('Queen has value 12', () {
      expect(Rank.queen.value, 12);
    });

    test('King has value 13', () {
      expect(Rank.king.value, 13);
    });
  });

  group('Suits and ranks', () {
    test('there are exactly four suits', () {
      expect(Suit.values, hasLength(4));
      expect(
        Suit.values.map((suit) => suit.label),
        ['Hearts', 'Diamonds', 'Clubs', 'Spades'],
      );
    });

    test('there are exactly thirteen ranks', () {
      expect(Rank.values, hasLength(13));
    });
  });

  group('Card', () {
    test('derives its numeric value from the rank', () {
      const ace = Card(suit: Suit.hearts, rank: Rank.ace);
      const king = Card(suit: Suit.spades, rank: Rank.king);
      expect(ace.value, 1);
      expect(king.value, 13);
    });

    test('display name is "Rank of Suit"', () {
      expect(
        const Card(suit: Suit.hearts, rank: Rank.ace).displayName,
        'Ace of Hearts',
      );
      expect(
        const Card(suit: Suit.clubs, rank: Rank.seven).displayName,
        '7 of Clubs',
      );
      expect(
        const Card(suit: Suit.spades, rank: Rank.king).displayName,
        'King of Spades',
      );
    });

    test('every card has a unique display name', () {
      final names = [
        for (final suit in Suit.values)
          for (final rank in Rank.values)
            Card(suit: suit, rank: rank).displayName,
      ];
      expect(names.toSet(), hasLength(52));
    });

    test('equal cards compare equal and share a hash code', () {
      const a = Card(suit: Suit.hearts, rank: Rank.ace);
      const b = Card(suit: Suit.hearts, rank: Rank.ace);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('cards with different suits or ranks are not equal', () {
      const aceOfHearts = Card(suit: Suit.hearts, rank: Rank.ace);
      const aceOfSpades = Card(suit: Suit.spades, rank: Rank.ace);
      const twoOfHearts = Card(suit: Suit.hearts, rank: Rank.two);

      expect(aceOfHearts, isNot(equals(aceOfSpades)));
      expect(aceOfHearts, isNot(equals(twoOfHearts)));
    });

    test('toString returns the display name', () {
      const card = Card(suit: Suit.diamonds, rank: Rank.ten);
      expect(card.toString(), '10 of Diamonds');
    });
  });
}
