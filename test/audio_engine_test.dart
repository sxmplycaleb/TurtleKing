import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/feedback.dart';
import 'package:turtle_king/settings.dart';

/// A fake audioplayers *player* platform. Substituting it for the real
/// method-channel implementation lets the real [AudioplayersEngine] /
/// `AudioPool` / `AudioPlayer` code run end-to-end deterministically, with no
/// audio hardware, no plugins, and no real asset loading.
class FakePlayerPlatform extends AudioplayersPlatformInterface {
  final List<String> created = [];
  final List<String> disposed = [];
  final List<String> resumed = [];
  final List<String> stopped = [];
  final Map<String, String> sources = {};

  bool failResume = false;
  bool failSetSourceUrl = false;

  final Map<String, StreamController<AudioEvent>> _streams = {};

  @override
  Future<void> create(String playerId) async {
    created.add(playerId);
    _streams[playerId] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _streams[playerId]!.stream;

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    if (failSetSourceUrl) throw StateError('setSourceUrl failed');
    sources[playerId] = url;
    // The real platform reports once the source is ready to play; the
    // AudioPlayer's preparation future waits for this event.
    _streams[playerId]!.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> resume(String playerId) async {
    if (failResume) throw StateError('resume failed');
    resumed.add(playerId);
    // Simulate a short sound finishing so the pool recycles its player (the
    // real platform emits this when playback completes). Delivered on a later
    // microtask so the AudioPool has attached its onPlayerComplete listener
    // by the time the event arrives.
    scheduleMicrotask(() {
      _streams[playerId]?.add(
        const AudioEvent(eventType: AudioEventType.complete),
      );
    });
  }

  @override
  Future<void> stop(String playerId) async => stopped.add(playerId);

  @override
  Future<void> dispose(String playerId) async => disposed.add(playerId);

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration position) async {}

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {}

  @override
  Future<void> setAudioContext(
    String playerId,
    AudioContext audioContext,
  ) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<int?> getDuration(String playerId) async => null;

  @override
  Future<int?> getCurrentPosition(String playerId) async => null;

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

/// A fake audioplayers *global* platform (used once per app, before any
/// player exists).
class FakeGlobalPlatform extends GlobalAudioplayersPlatformInterface {
  int initCalls = 0;

  @override
  Future<void> init() async {
    initCalls++;
  }

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
}

/// A fake [AudioCache] that records which asset paths the engine asks for
/// and can simulate a missing/unreadable asset. No real file system access.
class FakeAudioCache extends AudioCache {
  final List<String> requested = [];
  bool failLoads = false;

  @override
  Future<String> loadPath(String fileName) async {
    if (failLoads) throw StateError('asset unavailable');
    requested.add(fileName);
    return '/fake/cache/$fileName';
  }
}

/// The asset path relative to the bundle root that audioplayers receives.
String _relativeAssetPath(String assetPath) => assetPath.startsWith('assets/')
    ? assetPath.substring('assets/'.length)
    : assetPath;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlayerPlatform playerPlatform;
  late FakeGlobalPlatform globalPlatform;
  late FakeAudioCache audioCache;

  setUp(() {
    playerPlatform = FakePlayerPlatform();
    globalPlatform = FakeGlobalPlatform();
    audioCache = FakeAudioCache();
    AudioplayersPlatformInterface.instance = playerPlatform;
    GlobalAudioplayersPlatformInterface.instance = globalPlatform;
    AudioCache.instance = audioCache;
    // Keep the failure paths fast: the real default is 30 s.
    AudioPlayer.preparationTimeout = const Duration(milliseconds: 500);
  });

  /// Lets the real-async engine work (streams, futures, platform calls) run
  /// to completion inside a widget-test body.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
  }

  /// Fires [service].play([event]) inside the real-async zone so the whole
  /// load/play chain completes deterministically.
  Future<void> playAndSettle(
    WidgetTester tester,
    GameFeedbackService service,
    FeedbackEvent event,
  ) async {
    await tester.runAsync(() async {
      service.play(event);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
  }

  /// Calls [service].preload() inside the real-async zone so the full
  /// preload chain completes deterministically.
  Future<void> preloadAndSettle(
    WidgetTester tester,
    GameFeedbackService service,
  ) async {
    await tester.runAsync(() async {
      service.preload();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
  }

  /// Disposes [engine] inside the real-async zone so the async player
  /// teardown (stream closes, platform calls) fully completes before the
  /// test ends — otherwise the players' frame callbacks outlive the test.
  Future<void> disposeEngine(
    WidgetTester tester,
    AudioplayersEngine engine,
  ) async {
    await tester.runAsync(() async {
      engine.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  }

  /// Disposes [service] (which releases its engine) inside the real-async
  /// zone; see [disposeEngine].
  Future<void> disposeService(
    WidgetTester tester,
    GameFeedbackService service,
  ) async {
    await tester.runAsync(() async {
      service.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  }

  group('FeedbackEvent → bundled asset', () {
    test('every event maps to a distinct, declared, on-disk asset', () {
      final seen = <String>{};
      for (final event in FeedbackEvent.values) {
        final path = feedbackPatternFor(event).assetPath;
        expect(path, startsWith('assets/sounds/'));
        expect(allSoundAssetPaths, contains(path));
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
        seen.add(path);
      }
      expect(seen.length, FeedbackEvent.values.length);
    });

    testWidgets('the real engine is asked only for the declared assets', (
      tester,
    ) async {
      final store = SettingsStore.inMemory();
      final engine = AudioplayersEngine();
      final service = GameFeedbackService(store, engine: engine);

      // Start the plays inside the real-async zone so the full load/play
      // chains complete deterministically (see [playAndSettle]).
      await tester.runAsync(() async {
        for (final event in FeedbackEvent.values) {
          service.play(event);
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });

      final declared = allSoundAssetPaths.map(_relativeAssetPath).toSet();
      expect(audioCache.requested, isNotEmpty);
      for (final path in audioCache.requested) {
        expect(declared, contains(path), reason: 'unexpected audio path');
      }
      // Every event actually reached the audio layer.
      expect(audioCache.requested.toSet(), containsAll(declared));
      expect(tester.takeException(), isNull);

      // Release the players so no frame callbacks outlive the test.
      await disposeService(tester, service);
    });
  });

  group('AudioplayersEngine contract', () {
    testWidgets('load() preloads each asset into its own pool id', (
      tester,
    ) async {
      final engine = AudioplayersEngine();
      for (var i = 0; i < allSoundAssetPaths.length; i++) {
        final id = await tester.runAsync(
          () => engine.load(allSoundAssetPaths[i]),
        );
        expect(id, i);
      }
      expect(audioCache.requested, hasLength(allSoundAssetPaths.length));
      expect(playerPlatform.created, isNotEmpty);
      await disposeEngine(tester, engine);
    });

    testWidgets('play() resumes the preloaded pool for that asset', (
      tester,
    ) async {
      final engine = AudioplayersEngine();
      final id = (await tester.runAsync(
        () => engine.load('assets/sounds/victory.wav'),
      ))!;
      expect(id, 0);
      expect(audioCache.requested, ['sounds/victory.wav']);

      final before = playerPlatform.resumed.length;
      await tester.runAsync(() => engine.play(id));

      expect(playerPlatform.resumed.length, greaterThan(before));
      expect(playerPlatform.sources, isNotEmpty);
      await disposeEngine(tester, engine);
    });

    testWidgets('a missing asset fails load() with -1 and never crashes', (
      tester,
    ) async {
      final engine = AudioplayersEngine();
      audioCache.failLoads = true;

      final id = await tester.runAsync(
        () => engine.load('assets/sounds/does_not_exist.wav'),
      );
      expect(id, -1);
      expect(tester.takeException(), isNull);

      // Gameplay through the service also degrades to silence + haptics.
      final haptics = <FeedbackHaptic>[];
      final store = SettingsStore.inMemory();
      final service = GameFeedbackService(
        store,
        engine: engine,
        playHaptic: haptics.add,
      );
      await playAndSettle(tester, service, FeedbackEvent.cardReveal);

      expect(tester.takeException(), isNull);
      expect(haptics, [FeedbackHaptic.light]);
      await disposeService(tester, service);
    });

    testWidgets('a playback failure is swallowed and cannot reach gameplay', (
      tester,
    ) async {
      final store = SettingsStore.inMemory();
      final engine = AudioplayersEngine();
      final service = GameFeedbackService(store, engine: engine);

      await playAndSettle(tester, service, FeedbackEvent.yamada); // Preloads.

      playerPlatform.failResume = true;
      await playAndSettle(tester, service, FeedbackEvent.yamada);

      expect(tester.takeException(), isNull);
      await disposeService(tester, service);
    });

    testWidgets('preload() creates one ready pool per asset before gameplay', (
      tester,
    ) async {
      final store = SettingsStore.inMemory();
      final engine = AudioplayersEngine();
      final service = GameFeedbackService(store, engine: engine);

      await preloadAndSettle(tester, service);

      // Every bundled asset is preloaded into its own pool, ready to play.
      expect(
        audioCache.requested,
        allSoundAssetPaths.map(_relativeAssetPath).toList(),
      );
      expect(playerPlatform.created, hasLength(allSoundAssetPaths.length));

      // A play after preload reuses the pool — no new load, no new pool.
      await playAndSettle(tester, service, FeedbackEvent.cardReveal);
      expect(audioCache.requested, hasLength(allSoundAssetPaths.length));
      expect(playerPlatform.created, hasLength(allSoundAssetPaths.length));
      expect(playerPlatform.resumed, isNotEmpty);

      await disposeService(tester, service);
    });

    testWidgets('rapid repeated plays reuse the preloaded pool', (
      tester,
    ) async {
      final store = SettingsStore.inMemory();
      final engine = AudioplayersEngine();
      final service = GameFeedbackService(store, engine: engine);

      // Preload every asset, exactly as the game screen does before play.
      await preloadAndSettle(tester, service);
      expect(audioCache.requested, hasLength(allSoundAssetPaths.length));
      expect(playerPlatform.created, hasLength(allSoundAssetPaths.length));

      // Ten rapid replays (quick sequential actions, the real gameplay
      // pattern) must reuse the one victory pool and never re-initialize it.
      for (var i = 0; i < 10; i++) {
        await playAndSettle(tester, service, FeedbackEvent.victory);
      }

      expect(audioCache.requested, hasLength(allSoundAssetPaths.length));
      expect(playerPlatform.created, hasLength(allSoundAssetPaths.length));
      expect(playerPlatform.resumed, hasLength(10));
      expect(tester.takeException(), isNull);
      await disposeService(tester, service);
    });

    testWidgets('dispose() releases every native player', (tester) async {
      final engine = AudioplayersEngine();
      await tester.runAsync(() => engine.load('assets/sounds/card_reveal.wav'));
      await tester.runAsync(() => engine.load('assets/sounds/victory.wav'));
      expect(playerPlatform.created, hasLength(2));

      await disposeEngine(tester, engine);

      expect(
        playerPlatform.disposed.toSet(),
        containsAll(playerPlatform.created.toSet()),
      );

      // Service-level: after dispose, play() is a silent no-op.
      final store = SettingsStore.inMemory();
      final service = GameFeedbackService(store, engine: engine);
      await disposeService(tester, service);
      service.play(FeedbackEvent.victory);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('sound/haptic gating with the real engine', () {
    testWidgets('sound off → zero playback requests, haptics still play', (
      tester,
    ) async {
      final haptics = <FeedbackHaptic>[];
      final store = SettingsStore.inMemory()..setSoundEnabled(false);
      final engine = AudioplayersEngine();
      final service = GameFeedbackService(
        store,
        engine: engine,
        playHaptic: haptics.add,
      );

      service.play(FeedbackEvent.cardReveal);
      await settle(tester);

      expect(audioCache.requested, isEmpty);
      expect(playerPlatform.resumed, isEmpty);
      expect(haptics, [FeedbackHaptic.light]);
      await disposeService(tester, service);
    });

    testWidgets('haptics off → sound still plays through the engine', (
      tester,
    ) async {
      final haptics = <FeedbackHaptic>[];
      final store = SettingsStore.inMemory()..setHapticsEnabled(false);
      final engine = AudioplayersEngine();
      final service = GameFeedbackService(
        store,
        engine: engine,
        playHaptic: haptics.add,
      );

      await preloadAndSettle(tester, service);
      expect(audioCache.requested, hasLength(allSoundAssetPaths.length));

      await playAndSettle(tester, service, FeedbackEvent.cardReveal);

      expect(haptics, isEmpty);
      // The preloaded pool was reused — no new asset request.
      expect(audioCache.requested, hasLength(allSoundAssetPaths.length));
      expect(playerPlatform.resumed, isNotEmpty);
      await disposeService(tester, service);
    });
  });
}
