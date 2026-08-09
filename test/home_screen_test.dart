import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/home_screen.dart';
import 'package:turtle_king/how_to_play_screen.dart';
import 'package:turtle_king/main.dart';
import 'package:turtle_king/player_setup_screen.dart';
import 'package:turtle_king/turtle_art.dart';

void main() {
  group('HomeScreen', () {
    testWidgets('shows Turtle King branding and turtle art', (tester) async {
      await tester.pumpWidget(const TurtleKingApp());

      expect(find.text('Turtle King'), findsOneWidget);
      expect(find.text('Pass & Play Card Game'), findsOneWidget);
      expect(find.byType(TurtleArt), findsOneWidget);
    });

    testWidgets('shows a New Game button', (tester) async {
      await tester.pumpWidget(const TurtleKingApp());

      expect(find.widgetWithText(FilledButton, 'New Game'), findsOneWidget);
    });

    testWidgets('New Game navigates to the player setup screen', (
      tester,
    ) async {
      await tester.pumpWidget(const TurtleKingApp());

      await tester.tap(find.text('New Game'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerSetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('shows a How to Play button', (tester) async {
      await tester.pumpWidget(const TurtleKingApp());

      expect(
        find.widgetWithText(OutlinedButton, 'How to Play'),
        findsOneWidget,
      );
    });

    testWidgets('How to Play opens the rules screen and back returns home', (
      tester,
    ) async {
      await tester.pumpWidget(const TurtleKingApp());

      await tester.tap(find.text('How to Play'));
      await tester.pumpAndSettle();

      expect(find.byType(HowToPlayScreen), findsOneWidget);
      expect(find.byType(PlayerSetupScreen), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(HowToPlayScreen), findsNothing);
      expect(find.text('New Game'), findsOneWidget);
    });
  });
}
