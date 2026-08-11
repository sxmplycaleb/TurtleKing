import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';
import 'package:turtle_king/settings.dart';
import 'package:turtle_king/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsStore defaults', () {
    test('an in-memory store starts with the Turtle King defaults', () {
      final store = SettingsStore.inMemory();
      expect(store.themeMode, ThemeModePref.system);
      expect(store.colorTheme, AppColorTheme.turtleKingGold);
      expect(store.cardDesign, CardDesign.classicPoker);
      // Sound and haptics default to enabled.
      expect(store.soundEnabled, isTrue);
      expect(store.hapticsEnabled, isTrue);
    });

    test('loading with empty prefs returns the defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await SettingsStore.load();
      expect(store.themeMode, ThemeModePref.system);
      expect(store.colorTheme, AppColorTheme.turtleKingGold);
      expect(store.cardDesign, CardDesign.classicPoker);
      expect(store.soundEnabled, isTrue);
      expect(store.hapticsEnabled, isTrue);
    });
  });

  group('SettingsStore selection', () {
    test('setters update the value and notify listeners', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await SettingsStore.load();
      var notifications = 0;
      store.addListener(() => notifications++);

      store.setThemeMode(ThemeModePref.dark);
      store.setColorTheme(AppColorTheme.oceanBlue);
      store.setCardDesign(CardDesign.noir);

      expect(store.themeMode, ThemeModePref.dark);
      expect(store.colorTheme, AppColorTheme.oceanBlue);
      expect(store.cardDesign, CardDesign.noir);
      expect(notifications, 3);
    });

    test('setting the same value does not notify or rewrite', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await SettingsStore.load();
      var notifications = 0;
      store.addListener(() => notifications++);

      store.setThemeMode(ThemeModePref.system);

      expect(notifications, 0);
    });
  });

  group('SettingsStore persistence', () {
    test('preferences survive a simulated app restart', () async {
      SharedPreferences.setMockInitialValues({});

      var store = await SettingsStore.load();
      store.setThemeMode(ThemeModePref.dark);
      store.setColorTheme(AppColorTheme.emerald);
      store.setCardDesign(CardDesign.turtleKing);

      // A fresh load is the same as the app starting again.
      store = await SettingsStore.load();
      expect(store.themeMode, ThemeModePref.dark);
      expect(store.colorTheme, AppColorTheme.emerald);
      expect(store.cardDesign, CardDesign.turtleKing);
    });

    test('light and system modes persist too', () async {
      SharedPreferences.setMockInitialValues({});
      var store = await SettingsStore.load();
      store.setThemeMode(ThemeModePref.light);
      store = await SettingsStore.load();
      expect(store.themeMode, ThemeModePref.light);

      store.setThemeMode(ThemeModePref.system);
      store = await SettingsStore.load();
      expect(store.themeMode, ThemeModePref.system);
    });

    test('unrecognized stored values fall back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        'settings.themeMode': 'neon',
        'settings.colorTheme': 'turtleKingGold',
        'settings.cardDesign': 'classicPoker',
      });
      final store = await SettingsStore.load();
      expect(store.themeMode, ThemeModePref.system);
      expect(store.colorTheme, AppColorTheme.turtleKingGold);
      expect(store.cardDesign, CardDesign.classicPoker);
      expect(store.soundEnabled, isTrue);
      expect(store.hapticsEnabled, isTrue);
    });

    test(
      'sound and haptic toggles persist across a simulated restart',
      () async {
        SharedPreferences.setMockInitialValues({});

        var store = await SettingsStore.load();
        store.setSoundEnabled(false);
        store.setHapticsEnabled(false);

        store = await SettingsStore.load();
        expect(store.soundEnabled, isFalse);
        expect(store.hapticsEnabled, isFalse);

        store.setSoundEnabled(true);
        store.setHapticsEnabled(true);
        store = await SettingsStore.load();
        expect(store.soundEnabled, isTrue);
        expect(store.hapticsEnabled, isTrue);
      },
    );

    test('a stale stored YAMADA voice key is ignored (M17.5 removal)', () async {
      // M17.5 removed the YAMADA voice setting. A leftover key from an older
      // install must not break loading or alter any other preference.
      SharedPreferences.setMockInitialValues({
        'settings.yamadaVoice': 'animeGirl',
        'settings.soundEnabled': false,
      });
      final store = await SettingsStore.load();
      // The removed setting is simply gone; sound/haptics still load normally.
      expect(store.soundEnabled, isFalse);
      expect(store.hapticsEnabled, isTrue);
    });
  });

  group('separation from gameplay state', () {
    test('changing preferences never mutates an existing GameState', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await SettingsStore.load();
      final game = GameState(
        players: [
          Player(id: 'p1', name: 'Caleb', color: PlayerColors.palette[0]),
          Player(id: 'p2', name: 'Bob', color: PlayerColors.palette[1]),
        ],
      );
      final before = game.players.length;
      final remaining = game.remainingCards;

      store.setThemeMode(ThemeModePref.dark);
      store.setColorTheme(AppColorTheme.crimson);
      store.setCardDesign(CardDesign.noir);
      store.setSoundEnabled(false);
      store.setHapticsEnabled(false);

      // The game state is untouched by presentation changes.
      expect(game.players.length, before);
      expect(game.remainingCards, remaining);
      expect(game.roundNumber, 1);
      expect(game.gameComplete, isFalse);
    });
  });
}
