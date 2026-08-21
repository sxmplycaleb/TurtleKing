import 'package:shared_preferences/shared_preferences.dart';

import 'game_catalog.dart';

/// Persists game play counts locally.
///
/// Only available games should have their counts incremented. Coming Soon
/// games always have a count of 0.
class PlayCountStore {
  PlayCountStore._({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  static const _prefix = 'play_count_';

  /// Load play counts from persistent storage.
  static Future<PlayCountStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayCountStore._(prefs: prefs);
  }

  /// In-memory store for testing.
  factory PlayCountStore.inMemory() {
    return PlayCountStore._prefsOnly(_FakePrefs());
  }

  PlayCountStore._prefsOnly(SharedPreferences prefs) : _prefs = prefs;

  /// Returns the play count for the given game [id].
  int count(String id) => _prefs.getInt('$_prefix$id') ?? 0;

  /// Increments the play count for the given game [id].
  ///
  /// Only call this when an actual game session starts — not when a preview
  /// is opened or when the Other Games section is expanded.
  void increment(String id) {
    final current = count(id);
    _prefs.setInt('$_prefix$id', current + 1);
  }

  /// Returns play counts for all games in the catalog, keyed by [GameEntry.id].
  Map<String, int> allCounts() {
    final counts = <String, int>{};
    for (final game in gameCatalog) {
      counts[game.id] = count(game.id);
    }
    return counts;
  }
}

/// Minimal in-memory SharedPreferences implementation for testing.
class _FakePrefs implements SharedPreferences {
  final Map<String, Object> _data = {};

  @override
  Set<String> getKeys() => _data.keys.toSet();

  @override
  Object? get(String key) => _data[key];

  @override
  String? getString(String key) => _data[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  int? getInt(String key) => _data[key] as int?;

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  double? getDouble(String key) => _data[key] as double?;

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) => _data[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  List<String>? getStringList(String key) => _data[key] as List<String>?;

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  Future<void> reload() async {}

  @override
  Future<bool> commit() async => true;
}
