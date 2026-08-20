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
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.legalConsentAccepted,
    required this.legalConsentVersion,
  });

  static const _themeModeKey = 'settings.themeMode';
  static const _colorThemeKey = 'settings.colorTheme';
  static const _cardDesignKey = 'settings.cardDesign';
  static const _soundEnabledKey = 'settings.soundEnabled';
  static const _hapticsEnabledKey = 'settings.hapticsEnabled';
  static const _legalConsentAcceptedKey = 'settings.legalConsentAccepted';
  static const _legalConsentVersionKey = 'settings.legalConsentVersion';

  final SharedPreferences? _prefs;

  /// The selected brightness preference.
  ThemeModePref themeMode;

  /// The selected accent color theme.
  AppColorTheme colorTheme;

  /// The selected card design.
  CardDesign cardDesign;

  /// Whether gameplay sound effects play (default: on).
  bool soundEnabled;

  /// Whether gameplay haptic feedback plays (default: on).
  bool hapticsEnabled;

  /// Whether the legal consent (age + terms/privacy) has been accepted.
  bool legalConsentAccepted;

  /// The version of the legal consent that was accepted.
  /// When this changes, consent must be re-accepted.
  String legalConsentVersion;

  /// The current legal consent version.
  /// Increment this when the legal documents change materially.
  static const currentConsentVersion = '1.0';

  /// Loads the persisted preferences (defaults when unset).
  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if the stored consent version matches the current version.
    // If not, consent must be re-accepted.
    final storedVersion = prefs.getString(_legalConsentVersionKey) ?? '';
    final consentAccepted =
        (prefs.getBool(_legalConsentAcceptedKey) ?? false) &&
        storedVersion == currentConsentVersion;

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
      soundEnabled: prefs.getBool(_soundEnabledKey) ?? true,
      hapticsEnabled: prefs.getBool(_hapticsEnabledKey) ?? true,
      legalConsentAccepted: consentAccepted,
      legalConsentVersion: storedVersion,
    );
  }

  /// An unpersisted store with default values (tests, previews).
  static SettingsStore inMemory() => SettingsStore._(
    prefs: null,
    themeMode: ThemeModePref.system,
    colorTheme: AppColorTheme.turtleKingGold,
    cardDesign: CardDesign.classicPoker,
    soundEnabled: true,
    hapticsEnabled: true,
    legalConsentAccepted: false,
    legalConsentVersion: '',
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

  /// Enables/disables sound effects, persists it, and notifies listeners.
  void setSoundEnabled(bool value) {
    if (value == soundEnabled) return;
    soundEnabled = value;
    _prefs?.setBool(_soundEnabledKey, value);
    notifyListeners();
  }

  /// Enables/disables haptic feedback, persists it, and notifies listeners.
  void setHapticsEnabled(bool value) {
    if (value == hapticsEnabled) return;
    hapticsEnabled = value;
    _prefs?.setBool(_hapticsEnabledKey, value);
    notifyListeners();
  }

  /// Records that the user has accepted the legal consent.
  void acceptLegalConsent() {
    legalConsentAccepted = true;
    legalConsentVersion = currentConsentVersion;
    _prefs?.setBool(_legalConsentAcceptedKey, true);
    _prefs?.setString(_legalConsentVersionKey, currentConsentVersion);
    notifyListeners();
  }

  /// Resets the legal consent state (for testing or privacy compliance).
  void resetLegalConsent() {
    legalConsentAccepted = false;
    legalConsentVersion = '';
    _prefs?.setBool(_legalConsentAcceptedKey, false);
    _prefs?.setString(_legalConsentVersionKey, '');
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
