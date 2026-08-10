import 'package:flutter/material.dart';

import 'settings.dart';
import 'splash_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the persisted personalization preferences before the first frame.
  final settings = await SettingsStore.load();
  runApp(TurtleKingApp(store: settings));
}

/// Root widget for the Turtle King app.
///
/// Listens to the [SettingsStore] and rebuilds the Material theme from the
/// selected theme mode, accent color theme, and card design. Purely
/// presentational: no [GameState] is created here.
class TurtleKingApp extends StatefulWidget {
  const TurtleKingApp({super.key, this.store});

  /// The settings store; when null an in-memory store with defaults is used
  /// (e.g. in widget tests).
  final SettingsStore? store;

  @override
  State<TurtleKingApp> createState() => _TurtleKingAppState();
}

class _TurtleKingAppState extends State<TurtleKingApp> {
  late final SettingsStore _store = widget.store ?? SettingsStore.inMemory();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      store: _store,
      child: MaterialApp(
        title: 'Turtle King',
        theme: buildTheme(
          colorTheme: _store.colorTheme,
          cardDesign: _store.cardDesign,
        ),
        darkTheme: buildTheme(
          colorTheme: _store.colorTheme,
          brightness: Brightness.dark,
          cardDesign: _store.cardDesign,
        ),
        themeMode: switch (_store.themeMode) {
          ThemeModePref.system => ThemeMode.system,
          ThemeModePref.light => ThemeMode.light,
          ThemeModePref.dark => ThemeMode.dark,
        },
        home: const SplashScreen(),
      ),
    );
  }
}
