import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'settings.dart';

/// The gameplay moments that may produce sound/haptic feedback.
///
/// Events are gameplay *events*, never card identities: a [FeedbackEvent]
/// carries no card information, so hidden-card state can never influence
/// which feedback plays.
enum FeedbackEvent {
  /// The current player revealed their one permitted card.
  cardReveal,

  /// The phone was passed to the next viewer.
  handoffPass,

  /// A player shouted YAMADA (admit defeat, drink the cup).
  yamada,

  /// A player held out during pouring.
  holdOut,

  /// Everyone held out and all hands were revealed together.
  roundReveal,

  /// A player reached the drinking threshold and was eliminated.
  elimination,

  /// The game ended and a Turtle King was crowned.
  victory,
}

/// Every bundled sound asset in play order (also used by the asset
/// validation tests and preloading).
const List<String> allSoundAssetPaths = [
  'assets/sounds/card_reveal.wav',
  'assets/sounds/handoff.wav',
  'assets/sounds/hold_out.wav',
  'assets/sounds/yamada.wav',
  'assets/sounds/reveal.wav',
  'assets/sounds/elimination.wav',
  'assets/sounds/victory.wav',
];

/// The haptic intensities used (Flutter's built-in [HapticFeedback]).
enum FeedbackHaptic { selection, light, medium, heavy, vibrate }

/// The (audio asset, haptic) pair for one [FeedbackEvent].
class FeedbackPattern {
  const FeedbackPattern({required this.assetPath, required this.haptic});

  /// The bundled asset that plays for the event.
  final String assetPath;

  final FeedbackHaptic haptic;
}

/// Maps a gameplay event to its feedback pattern.
///
/// Pure and side-effect free so it can be unit-tested directly. The mapping
/// depends only on the event — never on cards, hands, or player identity.
FeedbackPattern feedbackPatternFor(FeedbackEvent event) {
  return switch (event) {
    FeedbackEvent.cardReveal => const FeedbackPattern(
      assetPath: 'assets/sounds/card_reveal.wav',
      haptic: FeedbackHaptic.light,
    ),
    FeedbackEvent.handoffPass => const FeedbackPattern(
      assetPath: 'assets/sounds/handoff.wav',
      haptic: FeedbackHaptic.selection,
    ),
    FeedbackEvent.yamada => const FeedbackPattern(
      assetPath: 'assets/sounds/yamada.wav',
      haptic: FeedbackHaptic.heavy,
    ),
    FeedbackEvent.holdOut => const FeedbackPattern(
      assetPath: 'assets/sounds/hold_out.wav',
      haptic: FeedbackHaptic.light,
    ),
    FeedbackEvent.roundReveal => const FeedbackPattern(
      assetPath: 'assets/sounds/reveal.wav',
      haptic: FeedbackHaptic.medium,
    ),
    FeedbackEvent.elimination => const FeedbackPattern(
      assetPath: 'assets/sounds/elimination.wav',
      haptic: FeedbackHaptic.heavy,
    ),
    FeedbackEvent.victory => const FeedbackPattern(
      assetPath: 'assets/sounds/victory.wav',
      haptic: FeedbackHaptic.vibrate,
    ),
  };
}

/// The optional UX feedback service.
///
/// Presentation only: it never touches [GameState] and is never a source of
/// truth for anything. Failures are swallowed so feedback can never interrupt
/// gameplay.
abstract class GameFeedback {
  /// Plays the feedback for [event], honoring the current sound/haptic
  /// settings. Never throws.
  void play(FeedbackEvent event);
}

/// Plays nothing. Used when no feedback scope is present (e.g. plain widget
/// tests) and as the safe fallback in [GameFeedbackScope.of].
class SilentGameFeedback implements GameFeedback {
  const SilentGameFeedback();

  @override
  void play(FeedbackEvent event) {}
}

/// The minimal playback surface the service needs, abstracted so tests can
/// substitute a fake without touching real audio hardware.
///
/// The engine receives only bundled-asset *paths* — never card identity,
/// hands, or player information — so hidden-card state can never influence
/// which audio plays.
abstract class SoundEngine {
  /// Loads the bundled asset at [assetPath], returning a sound id (> -1) or
  /// -1 on failure.
  Future<int> load(String assetPath);

  /// Plays a previously loaded sound id.
  Future<int> play(int soundId);

  /// Releases native resources.
  void dispose();
}

/// [SoundEngine] backed by `audioplayers` ([AudioPool] per asset).
///
/// `audioplayers` is the actively-maintained successor to the discontinued
/// `soundpool` package (incompatible with current Flutter: its legacy v1
/// plugin API was removed). Each asset gets one small pool of pre-loaded
/// players, so the same sound can be replayed (and briefly overlap) without
/// creating a new native player per event. On Android it uses media3/
/// ExoPlayer; on iOS/macOS AVAudioPlayer.
class AudioplayersEngine implements SoundEngine {
  final List<AudioPool> _pools = [];

  /// Maps a declared asset path (`assets/sounds/x.wav`) to the path
  /// `audioplayers` resolves relative to the asset root (`sounds/x.wav`).
  static String _assetSourcePath(String assetPath) =>
      assetPath.startsWith('assets/')
      ? assetPath.substring('assets/'.length)
      : assetPath;

  @override
  Future<int> load(String assetPath) async {
    try {
      final pool = await AudioPool.createFromAsset(
        path: _assetSourcePath(assetPath),
        // One pre-loaded player plus room for a brief overlap.
        minPlayers: 1,
        maxPlayers: 2,
      );
      _pools.add(pool);
      return _pools.length - 1;
    } catch (_) {
      // Missing/unreadable asset: report failure so playback degrades to
      // silence instead of crashing.
      return -1;
    }
  }

  @override
  Future<int> play(int soundId) async {
    final pool = _pools[soundId];
    await pool.start(volume: 1.0);
    return soundId;
  }

  @override
  void dispose() {
    // Fire-and-forget: releasing the players must never block or throw out
    // of dispose. Safe to call multiple times (the pools list is cleared).
    for (final pool in _pools) {
      try {
        unawaited(pool.dispose());
      } catch (_) {}
    }
    _pools.clear();
  }
}

/// The real feedback implementation: bundled WAV assets played through a
/// [SoundEngine] (default [AudioplayersEngine]) plus Flutter's built-in
/// haptics.
///
/// Reads the sound/haptic toggles live from the [SettingsStore] at call time,
/// so toggling a setting takes effect immediately. Both hooks are injectable
/// for tests (recording fakes); the defaults use the sound engine, which
/// fails gracefully when audio is unavailable.
///
/// The engine is created lazily on the first sound request and the service
/// must be [dispose]d (releases the engine) when it is no longer needed.
class GameFeedbackService implements GameFeedback {
  GameFeedbackService(
    this._store, {
    void Function(String assetPath)? playSound,
    void Function(FeedbackHaptic haptic)? playHaptic,
    SoundEngine? engine,
  }) {
    // Assignments are in the body so the analyzer does not demand
    // initializing formals for the injectable hooks (their public names
    // intentionally differ from the private fields).
    _playSound = playSound;
    _playHaptic = playHaptic;
    _engine = engine;
  }

  final SettingsStore _store;

  /// Injectable sound/haptic hooks; when null the defaults (asset engine /
  /// platform haptics) are used. Resolved at call time because the default
  /// sound path needs [this].
  void Function(String assetPath)? _playSound;
  void Function(FeedbackHaptic haptic)? _playHaptic;

  SoundEngine? _engine;
  final Map<String, int> _soundIds = {};
  bool _initFailed = false;
  bool _disposed = false;

  /// Creates the engine lazily (never during construction) and preloads all
  /// assets so the first play has no latency. Failures disable audio.
  void _ensureEngine() {
    if (_engine != null || _initFailed || _disposed) return;
    try {
      final engine = AudioplayersEngine();
      _engine = engine;
      unawaited(_preloadAll(engine));
    } catch (_) {
      _initFailed = true;
    }
  }

  Future<void> _preloadAll(SoundEngine engine) async {
    for (final assetPath in allSoundAssetPaths) {
      try {
        final id = await engine.load(assetPath);
        if (id > -1) _soundIds[assetPath] = id;
      } catch (_) {
        // Missing/unreadable asset: skip it; plays degrade to silence.
      }
    }
  }

  Future<void> _loadAndPlay(SoundEngine engine, String assetPath) async {
    try {
      final id = await engine.load(assetPath);
      if (id > -1) {
        _soundIds[assetPath] = id;
        await engine.play(id);
      }
    } catch (_) {
      // Unavailable audio must never crash or block gameplay.
    }
  }

  /// Plays a preloaded sound, swallowing async playback failures so an audio
  /// failure can never surface as an unhandled error or interrupt gameplay.
  Future<void> _play(SoundEngine engine, int soundId) async {
    try {
      await engine.play(soundId);
    } catch (_) {
      // Playback failure must never crash or block gameplay.
    }
  }

  void _playAsset(String assetPath) {
    _ensureEngine();
    final engine = _engine;
    if (engine == null || _disposed) return;
    final id = _soundIds[assetPath];
    if (id != null) {
      unawaited(_play(engine, id));
    } else {
      // Not preloaded yet (e.g. a play raced the preload): load-and-play.
      unawaited(_loadAndPlay(engine, assetPath));
    }
  }

  static Future<void> _defaultPlayHaptic(FeedbackHaptic haptic) async {
    try {
      switch (haptic) {
        case FeedbackHaptic.selection:
          await HapticFeedback.selectionClick();
        case FeedbackHaptic.light:
          await HapticFeedback.lightImpact();
        case FeedbackHaptic.medium:
          await HapticFeedback.mediumImpact();
        case FeedbackHaptic.heavy:
          await HapticFeedback.heavyImpact();
        case FeedbackHaptic.vibrate:
          await HapticFeedback.vibrate();
      }
    } catch (_) {
      // No haptic support: silently ignore.
    }
  }

  @override
  void play(FeedbackEvent event) {
    // Never throw: feedback is an optional UX enhancement and must not
    // interrupt gameplay, even if a hook (or the platform) fails.
    final pattern = feedbackPatternFor(event);
    if (_store.soundEnabled) {
      try {
        (_playSound ?? _playAsset)(pattern.assetPath);
      } catch (_) {}
    }
    if (_store.hapticsEnabled) {
      try {
        (_playHaptic ?? _defaultPlayHaptic)(pattern.haptic);
      } catch (_) {}
    }
  }

  /// Releases the sound engine. Safe to call multiple times; [play] becomes
  /// a silent no-op afterwards.
  void dispose() {
    _disposed = true;
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      try {
        engine.dispose();
      } catch (_) {}
    }
  }
}

/// Exposes the app-wide [GameFeedback] to the widget tree.
///
/// The scope is optional: [of] returns a silent service when absent, so
/// screens that render without a scope (widget tests, previews) simply play
/// nothing. The feedback service reads the settings store live, so the scope
/// never needs to rebuild when toggles change.
class GameFeedbackScope extends InheritedWidget {
  const GameFeedbackScope({
    super.key,
    required this.feedback,
    required super.child,
  });

  final GameFeedback feedback;

  /// The nearest [GameFeedback], or a silent no-op when none is provided.
  static GameFeedback of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<GameFeedbackScope>();
    return scope?.feedback ?? const SilentGameFeedback();
  }

  @override
  bool updateShouldNotify(GameFeedbackScope oldWidget) =>
      feedback != oldWidget.feedback;
}
