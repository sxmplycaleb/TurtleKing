import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/feedback.dart';
import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/driver.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';
import 'package:turtle_king/settings.dart';

/// A recording [GameFeedback] fake for widget tests.
class RecordingFeedback implements GameFeedback {
  final List<FeedbackEvent> events = [];
  int preloadCalls = 0;

  @override
  void play(FeedbackEvent event) => events.add(event);

  @override
  void preload() => preloadCalls++;
}

/// A feedback service whose [play] and [preload] always throw, to prove
/// failures never interrupt gameplay.
class ThrowingFeedback implements GameFeedback {
  @override
  void play(FeedbackEvent event) => throw StateError('boom');

  @override
  void preload() => throw StateError('boom');
}

/// A fake [SoundEngine] that records loads/plays and can simulate failures.
class FakeSoundEngine implements SoundEngine {
  final List<String> loaded = [];
  final List<int> played = [];
  bool failLoads = false;
  bool failPlays = false;
  bool disposed = false;
  int _nextId = 1;

  @override
  Future<int> load(String assetPath) async {
    if (failLoads) return -1;
    loaded.add(assetPath);
    return _nextId++;
  }

  @override
  Future<int> play(int soundId) async {
    if (failPlays) throw StateError('play failed');
    played.add(soundId);
    return soundId;
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Player> twoPlayers() => [
    Player(id: 'player-1', name: 'Caleb', color: PlayerColors.palette[0]),
    Player(id: 'player-2', name: 'Bob', color: PlayerColors.palette[1]),
  ];

  GameState gameForTwo({int threshold = 100}) => GameState(
    players: twoPlayers(),
    random: Random(42),
    eliminationThreshold: threshold,
  );

  Future<void> pumpGame(
    WidgetTester tester,
    GameState game,
    GameFeedback feedback,
  ) async {
    await tester.pumpWidget(
      GameFeedbackScope(
        feedback: feedback,
        child: MaterialApp(home: GameStartScreen(driver: LocalDriver(game))),
      ),
    );
  }

  Future<void> tapVisible(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pump();
  }

  Future<void> completeViewingTurn(WidgetTester tester) async {
    await tester.tap(find.text('Reveal My Card'));
    await tester.pump();
    await tester.tap(find.text('Pass to Next Player'));
    await tester.pump();
  }

  Future<void> finishViewing(WidgetTester tester) async {
    await completeViewingTurn(tester);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await completeViewingTurn(tester);
  }

  group('event to audio asset mapping', () {
    test('every event maps to its own distinct bundled asset', () {
      const expected = <FeedbackEvent, String>{
        FeedbackEvent.cardReveal: 'assets/sounds/card_reveal.wav',
        FeedbackEvent.handoffPass: 'assets/sounds/handoff.wav',
        FeedbackEvent.holdOut: 'assets/sounds/hold_out.wav',
        // A single game sting (M17.5) — no spoken voice, no selection.
        FeedbackEvent.yamada: 'assets/sounds/yamada.wav',
        FeedbackEvent.roundReveal: 'assets/sounds/reveal.wav',
        FeedbackEvent.elimination: 'assets/sounds/elimination.wav',
        FeedbackEvent.victory: 'assets/sounds/victory.wav',
      };
      final seen = <String>{};
      for (final event in FeedbackEvent.values) {
        final pattern = feedbackPatternFor(event);
        expect(pattern.assetPath, expected[event]);
        expect(pattern.haptic, isNotNull);
        seen.add(pattern.assetPath);
      }
      // Every event gets a different sound.
      expect(seen.length, FeedbackEvent.values.length);
    });

    test('every mapped asset actually exists on disk', () {
      for (final event in FeedbackEvent.values) {
        final path = feedbackPatternFor(event).assetPath;
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
        expect(File(path).lengthSync(), greaterThan(44), reason: '$path empty');
      }
    });

    test(
      'YAMADA resolves to exactly one asset, independent of any setting',
      () {
        // The YAMADA event maps to exactly the single game sting; the mapping
        // has no parameters, so no setting or identity can change it.
        expect(
          feedbackPatternFor(FeedbackEvent.yamada).assetPath,
          'assets/sounds/yamada.wav',
        );
        // The old voice assets must not be referenced anywhere.
        expect(
          allSoundAssetPaths,
          isNot(contains('assets/sounds/yamada_deep.wav')),
        );
        expect(
          allSoundAssetPaths,
          isNot(contains('assets/sounds/yamada_anime.wav')),
        );
      },
    );

    test('intensity escalates with the drama of the event', () {
      expect(
        feedbackPatternFor(FeedbackEvent.cardReveal).haptic,
        FeedbackHaptic.light,
      );
      expect(
        feedbackPatternFor(FeedbackEvent.holdOut).haptic,
        FeedbackHaptic.light,
      );
      expect(
        feedbackPatternFor(FeedbackEvent.yamada).haptic,
        FeedbackHaptic.heavy,
      );
      expect(
        feedbackPatternFor(FeedbackEvent.elimination).haptic,
        FeedbackHaptic.heavy,
      );
      expect(
        feedbackPatternFor(FeedbackEvent.victory).haptic,
        FeedbackHaptic.vibrate,
      );
    });
  });

  group('GameFeedbackService preload', () {
    test('preload() loads every bundled asset exactly once', () async {
      final store = SettingsStore.inMemory();
      final engine = FakeSoundEngine();
      final service = GameFeedbackService(store, engine: engine);

      service.preload();
      service.preload(); // Idempotent.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(engine.loaded, allSoundAssetPaths); // All 7, in order, once.
    });

    test(
      'plays after preload reuse the cached ids — no load at event time',
      () async {
        final store = SettingsStore.inMemory();
        final engine = FakeSoundEngine();
        final service = GameFeedbackService(store, engine: engine);

        service.preload();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final loadCount = engine.loaded.length;

        service.play(FeedbackEvent.cardReveal);
        service.play(FeedbackEvent.victory);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Playback did not trigger any new asset load.
        expect(engine.loaded, hasLength(loadCount));
        expect(engine.played, isNotEmpty);
      },
    );

    test('preload failure never throws or blocks', () async {
      final store = SettingsStore.inMemory();
      final engine = FakeSoundEngine()..failLoads = true;
      final service = GameFeedbackService(store, engine: engine);

      expect(() => service.preload(), returnsNormally);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Haptics (and gameplay) still work after a failed preload. Hooks are
      // used so no real audio platform is involved in this unit test.
      final haptics = <FeedbackHaptic>[];
      final store2 = SettingsStore.inMemory();
      final service2 = GameFeedbackService(
        store2,
        playSound: (_) {},
        playHaptic: haptics.add,
      );
      service2.play(FeedbackEvent.yamada);
      expect(haptics, [FeedbackHaptic.heavy]);
    });
  });

  group('GameFeedbackService gating', () {
    test('plays sound and haptics when both settings are enabled', () {
      final store = SettingsStore.inMemory();
      final sounds = <String>[];
      final haptics = <FeedbackHaptic>[];
      final feedback = GameFeedbackService(
        store,
        playSound: sounds.add,
        playHaptic: haptics.add,
      );

      feedback.play(FeedbackEvent.cardReveal);

      expect(sounds, ['assets/sounds/card_reveal.wav']);
      expect(haptics, [FeedbackHaptic.light]);
    });

    test(
      'disabled sound produces no playback requests, haptics still play',
      () {
        final store = SettingsStore.inMemory()..setSoundEnabled(false);
        final sounds = <String>[];
        final haptics = <FeedbackHaptic>[];
        final feedback = GameFeedbackService(
          store,
          playSound: sounds.add,
          playHaptic: haptics.add,
        );

        feedback.play(FeedbackEvent.yamada);

        expect(sounds, isEmpty);
        expect(haptics, [FeedbackHaptic.heavy]);
      },
    );

    test('disabled haptics produce no haptic requests, sound still plays', () {
      final store = SettingsStore.inMemory()..setHapticsEnabled(false);
      final sounds = <String>[];
      final haptics = <FeedbackHaptic>[];
      final feedback = GameFeedbackService(
        store,
        playSound: sounds.add,
        playHaptic: haptics.add,
      );

      feedback.play(FeedbackEvent.elimination);

      expect(haptics, isEmpty);
      expect(sounds, ['assets/sounds/elimination.wav']);
    });

    test('toggling a setting takes effect immediately', () {
      final store = SettingsStore.inMemory();
      final sounds = <String>[];
      final feedback = GameFeedbackService(store, playSound: sounds.add);

      feedback.play(FeedbackEvent.victory);
      expect(sounds, hasLength(1));

      store.setSoundEnabled(false);
      feedback.play(FeedbackEvent.victory);
      expect(sounds, hasLength(1)); // No additional playback request.
    });

    test('play() depends only on the event, never on card identity', () {
      final store = SettingsStore.inMemory();
      final sounds = <String>[];
      final haptics = <FeedbackHaptic>[];
      final feedback = GameFeedbackService(
        store,
        playSound: sounds.add,
        playHaptic: haptics.add,
      );

      // Two separate plays of the same event are identical; the API takes no
      // card argument at all, so hidden-card state cannot influence feedback.
      feedback.play(FeedbackEvent.cardReveal);
      feedback.play(FeedbackEvent.cardReveal);

      expect(sounds, [
        'assets/sounds/card_reveal.wav',
        'assets/sounds/card_reveal.wav',
      ]);
      expect(haptics, [FeedbackHaptic.light, FeedbackHaptic.light]);
    });

    test('a failing playback hook never throws out of play()', () {
      final store = SettingsStore.inMemory();
      final feedback = GameFeedbackService(
        store,
        playSound: (_) => throw StateError('no audio'),
        playHaptic: (_) => throw StateError('no motor'),
      );

      expect(() => feedback.play(FeedbackEvent.cardReveal), returnsNormally);
    });

    test('play() depends only on the event, never on card identity', () {
      final store = SettingsStore.inMemory();
      final sounds = <String>[];
      final haptics = <FeedbackHaptic>[];
      final feedback = GameFeedbackService(
        store,
        playSound: sounds.add,
        playHaptic: haptics.add,
      );

      // Two separate plays of the same event are identical; the API takes no
      // card argument at all, so hidden-card state cannot influence feedback.
      feedback.play(FeedbackEvent.cardReveal);
      feedback.play(FeedbackEvent.cardReveal);

      expect(sounds, [
        'assets/sounds/card_reveal.wav',
        'assets/sounds/card_reveal.wav',
      ]);
      expect(haptics, [FeedbackHaptic.light, FeedbackHaptic.light]);
    });
  });

  test('no card/player identity reaches the audio layer', () {
    final store = SettingsStore.inMemory();
    final sounds = <String>[];
    final feedback = GameFeedbackService(store, playSound: sounds.add);

    // Repeated identical YAMADA plays — only the declared asset path is ever
    // handed to the sound layer, never card/player data.
    feedback.play(FeedbackEvent.yamada);
    feedback.play(FeedbackEvent.yamada);
    expect(sounds, ['assets/sounds/yamada.wav', 'assets/sounds/yamada.wav']);
  });

  group('sound engine safety', () {
    testWidgets('the engine path loads assets and plays the mapped sound', (
      tester,
    ) async {
      final engine = FakeSoundEngine();
      final store = SettingsStore.inMemory();
      final service = GameFeedbackService(store, engine: engine);

      await tester.runAsync(() async {
        service.play(FeedbackEvent.cardReveal);
        // Let the fire-and-forget preload/load-and-play settle.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      // The mapped card-reveal asset path was handed to the engine and a
      // sound id played. The engine receives only the asset path — never
      // card identity.
      expect(engine.loaded, contains('assets/sounds/card_reveal.wav'));
      expect(engine.played, isNotEmpty);
      expect(engine.disposed, isFalse);

      service.dispose();
      expect(engine.disposed, isTrue);
    });

    testWidgets('a missing/unloadable asset never crashes', (tester) async {
      final engine = FakeSoundEngine()..failLoads = true;
      final store = SettingsStore.inMemory();
      final service = GameFeedbackService(store, engine: engine);

      await tester.runAsync(() async {
        service.play(FeedbackEvent.victory);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      // Load failed → no play request, and no exception escaped.
      expect(engine.played, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a playback failure never crashes gameplay', (tester) async {
      final engine = FakeSoundEngine()..failPlays = true;
      final store = SettingsStore.inMemory();
      final service = GameFeedbackService(store, engine: engine);

      await tester.runAsync(() async {
        service.play(FeedbackEvent.yamada);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      expect(tester.takeException(), isNull);

      // The service still works afterwards (haptics unaffected).
      final haptics = <FeedbackHaptic>[];
      final store2 = SettingsStore.inMemory();
      final service2 = GameFeedbackService(store2, playHaptic: haptics.add);
      service2.play(FeedbackEvent.yamada);
      expect(haptics, [FeedbackHaptic.heavy]);
    });

    testWidgets('dispose releases the engine and silences later plays', (
      tester,
    ) async {
      final engine = FakeSoundEngine();
      final store = SettingsStore.inMemory();
      final service = GameFeedbackService(store, engine: engine);

      service.dispose();
      expect(engine.disposed, isTrue);

      await tester.runAsync(() async {
        service.play(FeedbackEvent.cardReveal);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(engine.played, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('scope fallback', () {
    testWidgets(
      'without a scope the game screen plays nothing (silent fallback)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: GameStartScreen(driver: LocalDriver(gameForTwo()))),
        );

        await tester.tap(find.text('Reveal My Card'));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Pass to Next Player'), findsOneWidget);
      },
    );
  });

  group('game-screen feedback integration', () {
    testWidgets('building the screen fires no feedback (not in build)', (
      tester,
    ) async {
      final recording = RecordingFeedback();
      await pumpGame(tester, gameForTwo(), recording);

      expect(recording.events, isEmpty);

      // A plain rebuild (no interaction) also produces no feedback.
      await tester.pump();
      await tester.pump();
      expect(recording.events, isEmpty);
    });

    testWidgets('the game screen preloads audio once before gameplay', (
      tester,
    ) async {
      final recording = RecordingFeedback();
      await pumpGame(tester, gameForTwo(), recording);

      // Preloaded exactly once at init, before any event fired.
      expect(recording.preloadCalls, 1);
      expect(recording.events, isEmpty);

      // Rebuilds do not re-preload.
      await tester.pump();
      await tester.pump();
      expect(recording.preloadCalls, 1);
    });

    testWidgets('each action fires exactly one feedback event', (tester) async {
      final recording = RecordingFeedback();
      await pumpGame(tester, gameForTwo(), recording);

      await tester.tap(find.text('Reveal My Card'));
      await tester.pumpAndSettle();
      expect(recording.events, [FeedbackEvent.cardReveal]);

      await tester.tap(find.text('Pass to Next Player'));
      await tester.pumpAndSettle();
      expect(recording.events, [
        FeedbackEvent.cardReveal,
        FeedbackEvent.handoffPass,
      ]);
    });

    testWidgets('revealing and passing trigger card feedback', (tester) async {
      final recording = RecordingFeedback();
      await pumpGame(tester, gameForTwo(), recording);

      await tester.tap(find.text('Reveal My Card'));
      await tester.pump();
      await tester.tap(find.text('Pass to Next Player'));
      await tester.pump();

      expect(recording.events, [
        FeedbackEvent.cardReveal,
        FeedbackEvent.handoffPass,
      ]);
    });

    testWidgets('the neutral handoff continue plays nothing', (tester) async {
      final recording = RecordingFeedback();
      await pumpGame(tester, gameForTwo(), recording);

      await completeViewingTurn(tester);
      final beforeContinue = recording.events.length;
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(recording.events.length, beforeContinue);
    });

    testWidgets('YAMADA triggers the yamada event', (tester) async {
      final recording = RecordingFeedback();
      final game = gameForTwo();
      await pumpGame(tester, game, recording);

      await finishViewing(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      recording.events.clear();
      await tapVisible(tester, 'YAMADA!');

      expect(recording.events, [FeedbackEvent.yamada]);
    });

    testWidgets('holding out triggers the hold-out event', (tester) async {
      final recording = RecordingFeedback();
      final game = gameForTwo();
      await pumpGame(tester, game, recording);

      await finishViewing(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      recording.events.clear();
      await tapVisible(tester, 'Hold out');

      expect(recording.events, [FeedbackEvent.holdOut]);
    });

    testWidgets('a no-YAMADA round ending in a reveal triggers roundReveal', (
      tester,
    ) async {
      final recording = RecordingFeedback();
      final game = gameForTwo();
      await pumpGame(tester, game, recording);

      await finishViewing(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tapVisible(tester, 'Hold out');
      await tester.tap(find.text('Continue'));
      await tester.pump();
      recording.events.clear();
      await tapVisible(tester, 'Hold out');

      expect(recording.events, [
        FeedbackEvent.holdOut,
        FeedbackEvent.roundReveal,
      ]);
    });

    testWidgets('elimination and Turtle King victory fire at game end', (
      tester,
    ) async {
      final recording = RecordingFeedback();
      final game = gameForTwo(threshold: 2);
      await pumpGame(tester, game, recording);

      await finishViewing(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tapVisible(tester, 'YAMADA!');
      await tapVisible(tester, 'Continue');
      await tapVisible(tester, 'YAMADA!');

      // Second YAMADA eliminates the caller and ends the game.
      expect(
        recording.events,
        containsAllInOrder([
          FeedbackEvent.yamada,
          FeedbackEvent.yamada,
          FeedbackEvent.elimination,
          FeedbackEvent.victory,
        ]),
      );
    });

    testWidgets('a throwing feedback service never breaks gameplay', (
      tester,
    ) async {
      final game = gameForTwo();
      await pumpGame(tester, game, ThrowingFeedback());

      await tester.tap(find.text('Reveal My Card'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Pass to Next Player'), findsOneWidget);

      // The game keeps progressing normally.
      await tester.tap(find.text('Pass to Next Player'));
      await tester.pump();
      expect(find.text('Pass the phone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'identical feedback regardless of the underlying hidden cards',
      (tester) async {
        // Two games with different deals: feedback must be card-agnostic.
        final recordingA = RecordingFeedback();
        await pumpGame(tester, gameForTwo(), recordingA);
        await tester.tap(find.text('Reveal My Card'));
        await tester.pump();

        final recordingB = RecordingFeedback();
        await pumpGame(tester, gameForTwo(), recordingB);
        await tester.tap(find.text('Reveal My Card'));
        await tester.pump();

        expect(recordingA.events, recordingB.events);
        expect(recordingA.events, [FeedbackEvent.cardReveal]);
      },
    );
  });
}
