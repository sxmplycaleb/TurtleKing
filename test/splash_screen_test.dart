import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/home_screen.dart';
import 'package:turtle_king/main.dart';
import 'package:turtle_king/settings.dart';
import 'package:turtle_king/splash_screen.dart';

/// Finds the splash's full Turtle King artwork image asset.
Finder splashArtworkFinder() => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName ==
          'assets/branding/turtle_king_splash.png',
);

void main() {
  group('SplashScreen', () {
    testWidgets('shows the full Turtle King artwork on the navy brand color', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: SplashScreen(duration: Duration(seconds: 5))),
      );

      expect(splashArtworkFinder(), findsOneWidget);
      final image = tester.widget<Image>(splashArtworkFinder());
      expect(image.fit, BoxFit.contain);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFF0B263C));
      // No game screen exists behind the splash.
      expect(find.byType(GameStartScreen), findsNothing);
    });

    testWidgets('exposes a semantic label', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(home: SplashScreen(duration: Duration(seconds: 5))),
      );

      expect(find.bySemanticsLabel('Turtle King'), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('transitions to the home screen after its duration', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(duration: Duration(milliseconds: 300)),
        ),
      );

      expect(find.byType(HomeScreen), findsNothing);
      expect(splashArtworkFinder(), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(splashArtworkFinder(), findsNothing);
    });

    testWidgets('the app entry shows the splash before the home screen', (
      tester,
    ) async {
      // Create a settings store with consent already accepted.
      SharedPreferences.setMockInitialValues({
        'settings.legalConsentAccepted': true,
        'settings.legalConsentVersion': '1.0',
      });
      final settings = await SettingsStore.load();
      await tester.pumpWidget(TurtleKingApp(store: settings));

      expect(splashArtworkFinder(), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(splashArtworkFinder(), findsNothing);
    });

    testWidgets('starting the app creates no gameplay screen or state', (
      tester,
    ) async {
      await tester.pumpWidget(const TurtleKingApp());

      // During the splash, no gameplay widgets exist.
      expect(find.byType(GameStartScreen), findsNothing);

      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();

      // Even after reaching home, no game has been started implicitly.
      expect(find.byType(GameStartScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
