import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/legal/onboarding_store.dart';
import 'package:turtle_king/main.dart';
import 'package:turtle_king/other_games/game_catalog.dart';
import 'package:turtle_king/other_games/game_preview_screen.dart';
import 'package:turtle_king/settings.dart';

/// Pumps the full app and advances past the splash screen.
Future<void> pumpHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'settings.legalConsentAccepted': true,
    'settings.legalConsentVersion': '1.0',
  });
  final settings = await SettingsStore.load();
  final onboarding = OnboardingStore.inMemory()..completeOnboarding();
  await tester.pumpWidget(
    TurtleKingApp(store: settings, onboarding: onboarding),
  );
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pumpAndSettle();
}

void main() {
  group('Game catalog', () {
    test('catalog has 6 games', () {
      expect(gameCatalog.length, 6);
    });

    test('all games are Coming Soon', () {
      for (final game in gameCatalog) {
        expect(game.status, GameStatus.comingSoon);
        expect(game.isAvailable, isFalse);
      }
    });

    test('games are in correct order', () {
      expect(gameCatalog[0].name, 'Choose a Topic');
      expect(gameCatalog[1].name, 'Shots & Ladders');
      expect(gameCatalog[2].name, 'Guess the Word or Take a Shot');
      expect(gameCatalog[3].name, 'Spell or Take a Shot');
      expect(gameCatalog[4].name, "Don't Say the Same Word");
      expect(gameCatalog[5].name, 'Ludo');
    });

    test('all games have required fields', () {
      for (final game in gameCatalog) {
        expect(game.name.isNotEmpty, isTrue);
        expect(game.description.isNotEmpty, isTrue);
        expect(game.artworkAsset.isNotEmpty, isTrue);
      }
    });

    test('some games have detailed descriptions', () {
      final withDetails = gameCatalog.where(
        (g) => g.detailedDescription != null,
      );
      expect(withDetails.length, greaterThanOrEqualTo(2));
    });
  });

  group('OtherGamesSection', () {
    testWidgets('shows OTHER GAMES in uppercase', (tester) async {
      await pumpHome(tester);

      expect(find.text('OTHER GAMES'), findsOneWidget);
    });

    testWidgets('is collapsed by default — game cards hidden', (tester) async {
      await pumpHome(tester);

      expect(find.text('Choose a Topic'), findsNothing);
      expect(find.text('Shots & Ladders'), findsNothing);
      expect(find.text('COMING SOON'), findsNothing);
    });

    testWidgets('tapping OTHER GAMES expands the section', (tester) async {
      await pumpHome(tester);

      await tester.ensureVisible(find.text('OTHER GAMES'));
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();

      expect(find.text('Choose a Topic'), findsOneWidget);
      expect(find.text('Shots & Ladders'), findsOneWidget);
      expect(find.text('Guess the Word or Take a Shot'), findsOneWidget);
      expect(find.text('Spell or Take a Shot'), findsOneWidget);
      expect(find.text("Don't Say the Same Word"), findsOneWidget);
      expect(find.text('Ludo'), findsOneWidget);
    });

    testWidgets('expanded section shows COMING SOON for all games', (
      tester,
    ) async {
      await pumpHome(tester);

      await tester.ensureVisible(find.text('OTHER GAMES'));
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();

      expect(find.text('COMING SOON'), findsNWidgets(6));
    });

    testWidgets('tapping OTHER GAMES again collapses the section', (
      tester,
    ) async {
      await pumpHome(tester);

      await tester.ensureVisible(find.text('OTHER GAMES'));

      // Expand
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a Topic'), findsOneWidget);

      // Collapse
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a Topic'), findsNothing);
    });

    testWidgets('tapping a game opens the preview screen', (tester) async {
      await pumpHome(tester);

      await tester.ensureVisible(find.text('OTHER GAMES'));
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Choose a Topic'));
      await tester.tap(find.text('Choose a Topic'));
      await tester.pumpAndSettle();

      expect(find.byType(GamePreviewScreen), findsOneWidget);
    });
  });

  group('GamePreviewScreen', () {
    testWidgets('shows game name and description', (tester) async {
      final game = gameCatalog[0];
      await tester.pumpWidget(MaterialApp(home: GamePreviewScreen(game: game)));

      // The game name appears in both the AppBar title and the body.
      expect(find.text(game.name), findsWidgets);
      expect(find.text(game.description), findsOneWidget);
    });

    testWidgets('shows COMING SOON badge', (tester) async {
      final game = gameCatalog[0];
      await tester.pumpWidget(MaterialApp(home: GamePreviewScreen(game: game)));

      expect(find.text('COMING SOON'), findsOneWidget);
    });

    testWidgets('shows not available message for coming soon games', (
      tester,
    ) async {
      final game = gameCatalog[0];
      await tester.pumpWidget(MaterialApp(home: GamePreviewScreen(game: game)));

      expect(
        find.text("This game isn't available yet.\nCheck back soon."),
        findsOneWidget,
      );
    });

    testWidgets('shows detailed description when present', (tester) async {
      final game = gameCatalog[0]; // Has detailedDescription
      await tester.pumpWidget(MaterialApp(home: GamePreviewScreen(game: game)));

      expect(find.text('How it works'), findsOneWidget);
      expect(find.textContaining('5 seconds'), findsOneWidget);
    });

    testWidgets('does not show detailed description when absent', (
      tester,
    ) async {
      final game = gameCatalog[1]; // Shots and Ladders — no detailedDescription
      await tester.pumpWidget(MaterialApp(home: GamePreviewScreen(game: game)));

      expect(find.text('How it works'), findsNothing);
    });

    testWidgets('back button returns to previous screen', (tester) async {
      final game = gameCatalog[0];
      // Push GamePreviewScreen on top of a dummy home so a back button appears.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GamePreviewScreen(game: game),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      // Open the preview screen.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(GamePreviewScreen), findsOneWidget);

      // Tap the back button.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(GamePreviewScreen), findsNothing);
    });

    testWidgets('no play or join button exists', (tester) async {
      final game = gameCatalog[0];
      await tester.pumpWidget(MaterialApp(home: GamePreviewScreen(game: game)));

      expect(find.text('Play'), findsNothing);
      expect(find.text('Join'), findsNothing);
      expect(find.text('Start'), findsNothing);
    });
  });
}
