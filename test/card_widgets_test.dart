import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/card.dart';
import 'package:turtle_king/card_widgets.dart';
import 'package:turtle_king/theme.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('PlayingCard', () {
    testWidgets('renders the rank symbol and suit glyph', (tester) async {
      await pumpCard(
        tester,
        const PlayingCard(
          card: Card(suit: Suit.hearts, rank: Rank.ace),
        ),
      );

      // 'A' and '♥' appear in the corner indices (top-left + rotated
      // bottom-right) and the center pip.
      expect(find.text('A'), findsWidgets);
      expect(find.text('♥'), findsWidgets);
      // No other rank text leaks onto the face.
      expect(find.text('Ace'), findsNothing);
    });

    testWidgets('hearts and diamonds render red; spades and clubs dark', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const Row(
          children: [
            PlayingCard(
              card: Card(suit: Suit.diamonds, rank: Rank.queen),
            ),
            PlayingCard(
              card: Card(suit: Suit.spades, rank: Rank.king),
            ),
          ],
        ),
      );

      final red = tester.widgetList<Text>(find.text('♦')).toList();
      expect(red, isNotEmpty);
      for (final text in red) {
        expect(text.style?.color, TurtleKingColors.suitRed);
      }

      final dark = tester.widgetList<Text>(find.text('♠')).toList();
      expect(dark, isNotEmpty);
      for (final text in dark) {
        expect(text.style?.color, TurtleKingColors.suitBlack);
      }
    });

    testWidgets('exposes the card identity through its semantic label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(
        tester,
        const PlayingCard(
          card: Card(suit: Suit.clubs, rank: Rank.seven),
        ),
      );

      expect(find.bySemanticsLabel('7 of Clubs'), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('uses a responsive default width', (tester) async {
      await pumpCard(
        tester,
        const PlayingCard(
          card: Card(suit: Suit.hearts, rank: Rank.ten),
        ),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text('10'), matching: find.byType(Container))
            .first,
      );
      expect(container.constraints?.maxWidth, greaterThan(0));
    });
  });

  group('CardBack', () {
    testWidgets('renders no rank, suit, or card identity', (tester) async {
      await pumpCard(tester, const CardBack());

      for (final glyph in ['A', '2', 'K', '♥', '♦', '♣', '♠']) {
        expect(find.text(glyph), findsNothing);
      }
      expect(find.textContaining('Hearts'), findsNothing);
    });

    testWidgets('is labeled "Card back" for accessibility', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester, const CardBack());

      expect(find.bySemanticsLabel('Card back'), findsOneWidget);
      // The back carries no card-name semantics.
      expect(find.bySemanticsLabel('Ace of Hearts'), findsNothing);

      semantics.dispose();
    });
  });

  group('CardFace', () {
    testWidgets('wraps a PlayingCard and exposes its card', (tester) async {
      const card = Card(suit: Suit.clubs, rank: Rank.king);
      await pumpCard(tester, const CardFace(card: card));

      expect(find.byType(PlayingCard), findsOneWidget);
      expect(tester.widget<CardFace>(find.byType(CardFace)).card, card);
    });
  });
}
