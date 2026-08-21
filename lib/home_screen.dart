import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';
import 'game_save.dart';
import 'game_start_screen.dart';
import 'game_state.dart';
import 'how_to_play_screen.dart';
import 'multiplayer/driver.dart';
import 'multiplayer/menu_screen.dart';
import 'other_games/other_games_section.dart';
import 'other_games/play_count_store.dart';
import 'player_setup_screen.dart';
import 'settings_screen.dart';

/// The Turtle King home screen.
///
/// Pure branding plus the resume entry point: when a resumable game exists,
/// a prominent Resume Game card is shown with only safe summary information
/// (round, active players, cup size, current player). No game state is
/// created here — a saved game is only decoded to summarize it, and only
/// after the user explicitly chooses Resume is it handed to the game screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.saveStore});

  /// Optional save store. When null the screen builds its own from
  /// [SharedPreferences]; when no persistence is available (e.g. widget
  /// tests without mocked preferences) the home screen simply shows the
  /// normal flow.
  final GameSaveStore? saveStore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GameSaveStore? _store;
  GameState? _saved;
  GameSaveException? _saveError;
  Map<String, int> _playCounts = {};

  @override
  void initState() {
    super.initState();
    if (widget.saveStore case final store?) {
      _store = store;
      _loadSavedGame();
    } else {
      _initStore();
    }
  }

  Future<void> _initStore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _store = GameSaveStore(prefs);
      _loadSavedGame();
    } catch (_) {
      // No persistence available; show the normal flow without resume.
    }
    _loadPlayCounts();
  }

  Future<void> _loadPlayCounts() async {
    try {
      final store = await PlayCountStore.load();
      setState(() {
        _playCounts = store.allCounts();
      });
    } catch (_) {
      // No persistence available; show games in catalog order.
    }
  }

  void _loadSavedGame() {
    final store = _store;
    if (store == null) return;
    GameState? saved;
    GameSaveException? error;
    try {
      saved = store.load();
      if (saved != null && saved.gameComplete) {
        // A completed game is never resumable; drop the stale save.
        store.clear();
        saved = null;
      }
    } on GameSaveException catch (caught) {
      error = caught;
    }
    _saved = saved;
    _saveError = error;
  }

  Future<void> _discardSave() async {
    await _store?.clear();
    if (!mounted) return;
    setState(() {
      _saved = null;
      _saveError = null;
    });
  }

  void _startNewGame() {
    // A fresh game replaces any old save.
    _store?.clear();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PlayerSetupScreen()));
  }

  void _resumeGame() {
    final saved = _saved;
    if (saved == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GameStartScreen(driver: LocalDriver(saved), saveStore: _store),
      ),
    );
  }

  void _openHowToPlay() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen()));
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scale the logo with the screen width so it fits small phones and
    // stays prominent on larger ones.
    final logoSize = (MediaQuery.sizeOf(context).width * 0.4).clamp(
      140.0,
      200.0,
    );

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/branding/turtle_king_emblem.png',
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                      semanticLabel: 'Turtle King logo',
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Turtle King',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pass & Play Card Game',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Version caption: read from the package metadata, never
                    // hardcoded (see app_version.dart).
                    const AppVersionText(),
                    const SizedBox(height: 32),
                    if (_saveError != null) ...[
                      _SaveErrorCard(
                        onDiscard: _discardSave,
                        message: _saveError!.message,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_saved != null) ...[
                      _ResumeCard(game: _saved!, onResume: _resumeGame),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      onPressed: _startNewGame,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                        textStyle: theme.textTheme.titleMedium,
                      ),
                      child: const Text('New Game'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _openHowToPlay,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                        textStyle: theme.textTheme.titleMedium,
                      ),
                      child: const Text('How to Play'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MultiplayerMenuScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.group),
                      label: const Text('Multiplayer'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                        textStyle: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 32),
                    OtherGamesSection(playCounts: _playCounts),
                  ],
                ),
              ),
            ),
            // Settings entry, kept out of the way of the branding column.
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: _openSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The prominent resume entry: safe summary + Resume action.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.game, required this.onResume});

  final GameState game;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = game.gameComplete ? null : game.currentPlayer;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Game in progress',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Round ${game.roundNumber} · ${game.activePlayerCount} '
              'player${game.activePlayerCount == 1 ? '' : 's'} · '
              '${game.cupSize.label} cup',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (current != null) ...[
              const SizedBox(height: 4),
              Text(
                '${current.name} to play',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume Game'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the stored save is corrupt or from an unsupported version.
class _SaveErrorCard extends StatelessWidget {
  const _SaveErrorCard({required this.onDiscard, required this.message});

  final VoidCallback onDiscard;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Saved game cannot be resumed',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onDiscard,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              child: const Text('Discard Save'),
            ),
          ],
        ),
      ),
    );
  }
}
