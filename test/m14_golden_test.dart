import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/card.dart';
import 'package:turtle_king/card_widgets.dart';
import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/home_screen.dart';
import 'package:turtle_king/multiplayer/driver.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';
import 'package:turtle_king/settings.dart';
import 'package:turtle_king/settings_screen.dart';
import 'package:turtle_king/theme.dart';

Future<void> loadRoboto() async {
  Future<ByteData> load(String name) async {
    final bytes = File(
      'C:/src/flutter/bin/cache/artifacts/material_fonts/$name',
    ).readAsBytesSync();
    return ByteData.view(bytes.buffer);
  }

  final loader = FontLoader('Roboto')
    ..addFont(load('roboto-regular.ttf'))
    ..addFont(load('roboto-medium.ttf'))
    ..addFont(load('roboto-bold.ttf'))
    ..addFont(load('roboto-black.ttf'));
  await loader.load();
}

Future<void> phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('m14 golden preview', (tester) async {
    await loadRoboto();
    await phone(tester);

    // --- Settings, light (gold) ---
    var store = SettingsStore.inMemory();
    await tester.pumpWidget(
      SettingsScope(
        store: store,
        child: MaterialApp(theme: buildTheme(), home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('m14_preview/01_settings_light.png'),
    );

    // --- Settings, dark (gold) ---
    store = SettingsStore.inMemory()..setThemeMode(ThemeModePref.dark);
    await tester.pumpWidget(
      SettingsScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(),
          darkTheme: buildTheme(brightness: Brightness.dark),
          themeMode: ThemeMode.dark,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('m14_preview/02_settings_dark.png'),
    );

    // --- Home, light + dark ---
    await tester.pumpWidget(
      MaterialApp(theme: buildTheme(), home: const HomeScreen()),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('m14_preview/03_home_light.png'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('m14_preview/04_home_dark.png'),
    );

    // --- Card designs (faces + backs), light ---
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final design in CardDesign.values) ...[
                  PlayingCard(
                    card: const Card(suit: Suit.diamonds, rank: Rank.ten),
                    width: 46,
                    style: CardStyle.forDesign(design),
                  ),
                  const SizedBox(width: 10),
                  CardBack(width: 46, style: CardStyle.forDesign(design)),
                  const SizedBox(width: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('m14_preview/05_cards.png'),
    );

    // --- Game pour turn, dark gold (baseline) ---
    Future<void> pumpGame(
      AppColorTheme colorTheme,
      Brightness brightness,
    ) async {
      final game = GameState(
        players: [
          Player(id: 'p1', name: 'Caleb', color: PlayerColors.palette[0]),
          Player(id: 'p2', name: 'Bob', color: PlayerColors.palette[1]),
        ],
        random: Random(42),
        eliminationThreshold: 100,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(
            colorTheme: colorTheme,
            brightness: brightness,
            cardDesign: CardDesign.turtleKing,
          ),
          home: GameStartScreen(driver: LocalDriver(game)),
        ),
      );
      await tester.pumpAndSettle();
      // Drive to the pour turn.
      for (final label in [
        'Reveal My Card',
        'Pass to Next Player',
        'Continue',
        'Reveal My Card',
        'Pass to Next Player',
        'Continue',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
    }

    await pumpGame(AppColorTheme.turtleKingGold, Brightness.dark);
    await expectLater(
      find.byType(GameStartScreen),
      matchesGoldenFile('m14_preview/06_game_dark_gold.png'),
    );

    await pumpGame(AppColorTheme.emerald, Brightness.dark);
    await expectLater(
      find.byType(GameStartScreen),
      matchesGoldenFile('m14_preview/07_game_dark_emerald.png'),
    );

    await pumpGame(AppColorTheme.oceanBlue, Brightness.dark);
    await expectLater(
      find.byType(GameStartScreen),
      matchesGoldenFile('m14_preview/08_game_dark_ocean.png'),
    );

    await pumpGame(AppColorTheme.royalPurple, Brightness.dark);
    await expectLater(
      find.byType(GameStartScreen),
      matchesGoldenFile('m14_preview/09_game_dark_purple.png'),
    );

    await pumpGame(AppColorTheme.crimson, Brightness.dark);
    await expectLater(
      find.byType(GameStartScreen),
      matchesGoldenFile('m14_preview/10_game_dark_crimson.png'),
    );

    await pumpGame(AppColorTheme.turtleKingGold, Brightness.light);
    await expectLater(
      find.byType(GameStartScreen),
      matchesGoldenFile('m14_preview/11_game_light_gold.png'),
    );
  });
}
