import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/home_screen.dart';
import 'package:turtle_king/how_to_play_screen.dart';
import 'package:turtle_king/legal/onboarding_store.dart';
import 'package:turtle_king/main.dart';
import 'package:turtle_king/player_setup_screen.dart';
import 'package:turtle_king/settings.dart';

/// Creates an [OnboardingStore] that is already fully completed.
OnboardingStore _completedOnboarding() {
  final store = OnboardingStore.inMemory();
  store.completeOnboarding();
  return store;
}

/// Pumps the full app and advances past the splash screen so the home
/// screen is on stage.
Future<void> pumpHome(WidgetTester tester) async {
  // Create a settings store with consent already accepted.
  SharedPreferences.setMockInitialValues({
    'settings.legalConsentAccepted': true,
    'settings.legalConsentVersion': '1.0',
  });
  final settings = await SettingsStore.load();
  await tester.pumpWidget(
    TurtleKingApp(store: settings, onboarding: _completedOnboarding()),
  );
  // Advance past the splash timer and its fade transition.
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pumpAndSettle();
}

/// Finds the home screen's Turtle King emblem image asset.
Finder emblemFinder() => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName ==
          'assets/branding/turtle_king_emblem.png',
);

void main() {
  group('HomeScreen', () {
    testWidgets('shows Turtle King branding and the emblem', (tester) async {
      await pumpHome(tester);

      expect(find.text('Turtle King'), findsOneWidget);
      expect(find.text('Pass & Play Card Game'), findsOneWidget);
      expect(emblemFinder(), findsOneWidget);
    });

    testWidgets('the emblem asset renders at a positive size', (tester) async {
      await pumpHome(tester);

      final image = tester.widget<Image>(emblemFinder());
      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('the logo exposes a semantic label', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHome(tester);

      expect(find.bySemanticsLabel('Turtle King logo'), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('the home screen renders in the dark theme without errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E7D32),
              brightness: Brightness.dark,
            ),
          ),
          home: const HomeScreen(),
        ),
      );

      expect(emblemFinder(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a New Game button', (tester) async {
      await pumpHome(tester);

      expect(find.widgetWithText(FilledButton, 'New Game'), findsOneWidget);
    });

    testWidgets('New Game navigates to the player setup screen', (
      tester,
    ) async {
      await pumpHome(tester);

      await tester.tap(find.text('New Game'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerSetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('shows a How to Play button', (tester) async {
      await pumpHome(tester);

      expect(
        find.widgetWithText(OutlinedButton, 'How to Play'),
        findsOneWidget,
      );
    });

    testWidgets('How to Play opens the rules screen and back returns home', (
      tester,
    ) async {
      await pumpHome(tester);

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
