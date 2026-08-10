import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/card_widgets.dart';
import 'package:turtle_king/main.dart';
import 'package:turtle_king/settings.dart';
import 'package:turtle_king/settings_screen.dart';
import 'package:turtle_king/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsStore> storeWithPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SettingsStore.load();
  }

  Future<void> pumpSettings(WidgetTester tester, SettingsStore store) async {
    await tester.pumpWidget(
      SettingsScope(
        store: store,
        child: MaterialApp(theme: buildTheme(), home: const SettingsScreen()),
      ),
    );
  }

  group('SettingsScreen', () {
    testWidgets('renders the sections and title', (tester) async {
      await pumpSettings(tester, await storeWithPrefs());

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Color Theme'), findsOneWidget);
      expect(find.text('Cards'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Turtle King Gold'), findsOneWidget);
    });

    testWidgets('selecting a theme mode updates the store', (tester) async {
      final store = await storeWithPrefs();
      await pumpSettings(tester, store);

      await tester.tap(find.text('Dark'));
      await tester.pump();

      expect(store.themeMode, ThemeModePref.dark);
    });

    testWidgets('selecting a color theme updates the store and shows a check', (
      tester,
    ) async {
      final store = await storeWithPrefs();
      await pumpSettings(tester, store);

      // The default Gold swatch is selected (check marker), Emerald is not.
      Finder tileFor(String label) => find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first;
      expect(
        find.descendant(
          of: tileFor('Turtle King Gold'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tileFor('Emerald'),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );

      await tester.ensureVisible(find.text('Emerald'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emerald'));
      await tester.pump();

      expect(store.colorTheme, AppColorTheme.emerald);
      expect(
        find.descendant(
          of: tileFor('Emerald'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tileFor('Turtle King Gold'),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
    });

    testWidgets('selecting a card design updates the store', (tester) async {
      final store = await storeWithPrefs();
      await pumpSettings(tester, store);

      await tester.ensureVisible(find.text('Noir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Noir'));
      await tester.pump();

      expect(store.cardDesign, CardDesign.noir);
    });

    testWidgets('shows face and back previews for every design', (
      tester,
    ) async {
      await pumpSettings(tester, await storeWithPrefs());

      expect(find.byType(PlayingCard), findsNWidgets(3));
      expect(find.byType(CardBack), findsNWidgets(3));
    });

    testWidgets('preview card backs are labeled only "Card back"', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpSettings(tester, await storeWithPrefs());

      // Every design's back is a generic card back — no hidden identity.
      expect(find.bySemanticsLabel('Card back'), findsNWidgets(3));
      // The only card identity comes from the face-up sample previews
      // (one per design), never from a back.
      expect(find.bySemanticsLabel('Ace of Spades'), findsNWidgets(3));

      semantics.dispose();
    });

    testWidgets('is scrollable on a small phone without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpSettings(tester, await storeWithPrefs());
      expect(tester.takeException(), isNull);

      // Lower sections are reachable by scrolling.
      await tester.scrollUntilVisible(find.text('Classic Poker'), 200);
      expect(tester.takeException(), isNull);
      expect(find.text('Classic Poker'), findsOneWidget);
    });
  });

  group('app-wide application', () {
    Future<void> pumpAppToHome(WidgetTester tester, SettingsStore store) async {
      await tester.pumpWidget(TurtleKingApp(store: store));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
    }

    testWidgets('the home screen opens Settings', (tester) async {
      await pumpAppToHome(tester, await storeWithPrefs());

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('the MaterialApp themeMode follows the store', (tester) async {
      final store = await storeWithPrefs();
      await tester.pumpWidget(TurtleKingApp(store: store));

      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app().themeMode, ThemeMode.system);

      store.setThemeMode(ThemeModePref.dark);
      await tester.pump();

      expect(app().themeMode, ThemeMode.dark);
      expect(app().darkTheme!.brightness, Brightness.dark);

      store.setThemeMode(ThemeModePref.light);
      await tester.pump();
      expect(app().themeMode, ThemeMode.light);
      expect(app().theme!.brightness, Brightness.light);
    });

    testWidgets('color theme and card design flow into the theme', (
      tester,
    ) async {
      final store = await storeWithPrefs();
      await tester.pumpWidget(TurtleKingApp(store: store));

      store.setColorTheme(AppColorTheme.oceanBlue);
      store.setCardDesign(CardDesign.noir);
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final table = app.theme!.extension<GameTableStyle>()!;
      expect(table.accent, AppColorTheme.oceanBlue.accent);
      expect(app.darkTheme!.extension<CardStyle>()!.design, CardDesign.noir);
    });
  });
}
