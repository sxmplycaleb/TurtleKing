import 'package:flutter/material.dart';

import 'feedback.dart';
import 'legal/onboarding_guard.dart';
import 'legal/onboarding_store.dart';
import 'settings.dart';
import 'splash_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load persisted preferences and onboarding state before the first frame.
  final settings = await SettingsStore.load();
  final onboarding = await OnboardingStore.load();
  runApp(TurtleKingApp(store: settings, onboarding: onboarding));
}

/// Root widget for the Turtle King app.
///
/// Listens to the [SettingsStore] and rebuilds the Material theme from the
/// selected theme mode, accent color theme, and card design. Purely
/// presentational: no [GameState] is created here.
class TurtleKingApp extends StatefulWidget {
  const TurtleKingApp({super.key, this.store, this.onboarding});

  /// The settings store; when null an in-memory store with defaults is used
  /// (e.g. in widget tests).
  final SettingsStore? store;

  /// The onboarding store; when null an in-memory store is used.
  final OnboardingStore? onboarding;

  @override
  State<TurtleKingApp> createState() => _TurtleKingAppState();
}

class _TurtleKingAppState extends State<TurtleKingApp> {
  late final SettingsStore _store = widget.store ?? SettingsStore.inMemory();
  late final OnboardingStore _onboarding =
      widget.onboarding ?? OnboardingStore.inMemory();

  /// Owned here (created once, disposed with the app) so the audio engine is
  /// never recreated per rebuild and its resources are released.
  GameFeedbackService? _feedback;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onSettingsChanged);
    _onboarding.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onSettingsChanged);
    _onboarding.removeListener(_onSettingsChanged);
    _feedback?.dispose();
    _feedback = null;
    super.dispose();
  }

  void _onSettingsChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // The feedback service reads the sound/haptic toggles live from the
    // store, so toggling them takes effect immediately. Created lazily so
    // the audio engine is never initialized during app startup.
    final feedback = _feedback ??= GameFeedbackService(_store);
    return SettingsScope(
      store: _store,
      child: GameFeedbackScope(
        feedback: feedback,
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
          home: OnboardingGuard(
            store: _onboarding,
            builder: (_) => const SplashScreen(),
          ),
        ),
      ),
    );
  }
}
