import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/home_screen.dart';
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

      expect(
        find.widgetWithText(FilledButton, 'New Game'),
        findsOneWidget,
      );
    });

    testWidgets('New Game navigates to the player setup screen', (tester) async {
      await tester.pumpWidget(const TurtleKingApp());

      await tester.tap(find.text('New Game'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerSetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });
  });
}
