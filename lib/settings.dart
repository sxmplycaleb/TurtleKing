import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// How the app picks its brightness: follow the device, or force a mode.
enum ThemeModePref {
  system('System'),
  light('Light'),
  dark('Dark');

  const ThemeModePref(this.label);

  /// Human-readable name shown in settings.
  final String label;
}

/// The single source of truth for presentation preferences.
///
/// Deliberately separate from [GameState]: preferences only describe how the
/// UI looks (theme mode, accent color theme, card design) and never touch
/// cards, hands, rounds, drinks, eliminations, or winner state.
///
/// Preferences persist via [SharedPreferences] when loaded with [load];
/// [inMemory] provides an unpersisted store for tests and previews.
class SettingsStore extends ChangeNotifier {
  SettingsStore._({
    required this._prefs,
    required this.themeMode,
    required this.colorTheme,
    required this.cardDesign,
  });

  static const _themeModeKey = 'settings.themeMode';
  static const _colorThemeKey = 'settings.colorTheme';
  static const _cardDesignKey = 'settings.cardDesign';

  final SharedPreferences? _prefs;

  /// The selected brightness preference.
  ThemeModePref themeMode;

  /// The selected accent color theme.
  AppColorTheme colorTheme;

  /// The selected card design.
  CardDesign cardDesign;

  /// Loads the persisted preferences (defaults when unset).
  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsStore._(
      prefs: prefs,
      themeMode: _readEnum(
        prefs.getString(_themeModeKey),
        ThemeModePref.values,
        ThemeModePref.system,
      ),
      colorTheme: _readEnum(
        prefs.getString(_colorThemeKey),
        AppColorTheme.values,
        AppColorTheme.turtleKingGold,
      ),
      cardDesign: _readEnum(
        prefs.getString(_cardDesignKey),
        CardDesign.values,
        CardDesign.classicPoker,
      ),
    );
  }

  /// An unpersisted store with default values (tests, previews).
  static SettingsStore inMemory() => SettingsStore._(
    prefs: null,
    themeMode: ThemeModePref.system,
    colorTheme: AppColorTheme.turtleKingGold,
    cardDesign: CardDesign.classicPoker,
  );

  static T _readEnum<T extends Enum>(
    String? stored,
    List<T> values,
    T fallback,
  ) {
    if (stored == null) return fallback;
    for (final value in values) {
      if (value.name == stored) return value;
    }
    return fallback;
  }

  void _persist(String key, String value) {
    _prefs?.setString(key, value);
  }

  /// Sets the theme mode, persists it, and notifies listeners.
  void setThemeMode(ThemeModePref value) {
    if (value == themeMode) return;
    themeMode = value;
    _persist(_themeModeKey, value.name);
    notifyListeners();
  }

  /// Sets the accent color theme, persists it, and notifies listeners.
  void setColorTheme(AppColorTheme value) {
    if (value == colorTheme) return;
    colorTheme = value;
    _persist(_colorThemeKey, value.name);
    notifyListeners();
  }

  /// Sets the card design, persists it, and notifies listeners.
  void setCardDesign(CardDesign value) {
    if (value == cardDesign) return;
    cardDesign = value;
    _persist(_cardDesignKey, value.name);
    notifyListeners();
  }
}

/// Exposes the app-wide [SettingsStore] to the widget tree.
///
/// Dependents rebuild when the store changes (e.g. the Settings screen
/// re-renders its selected states; the root rebuilds the Material theme).
class SettingsScope extends InheritedNotifier<SettingsStore> {
  const SettingsScope({
    super.key,
    required SettingsStore store,
    required super.child,
  }) : super(notifier: store);

  /// The nearest [SettingsStore], registering a dependency.
  static SettingsStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'No SettingsScope found above this context.');
    return scope!.notifier!;
  }
}
