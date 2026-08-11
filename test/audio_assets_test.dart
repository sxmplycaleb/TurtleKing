import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/feedback.dart';
import 'package:turtle_king/settings.dart';

/// Measured stats for one 16-bit mono 22050 Hz WAV: duration, RMS, peak,
/// leading silence, and the loudest sample in the final millisecond.
({double duration, double rms, double peak, double leadMs, double tailPeak})
_wavStats(String path) {
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  final dataSize = bd.getUint32(40, Endian.little);
  final n = dataSize ~/ 2;
  var sumSq = 0.0;
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    final v = bd.getInt16(44 + i * 2, Endian.little) / 32768.0;
    sumSq += v * v;
    if (v.abs() > peak) peak = v.abs();
  }
  final rms = math.sqrt(sumSq / n);
  final threshold = math.max(peak * 0.01, 0.005);
  var first = 0;
  while (first < n &&
      (bd.getInt16(44 + first * 2, Endian.little) / 32768.0).abs() <
          threshold) {
    first++;
  }
  final lastMsStart = n - (0.001 * 22050).round();
  var tailPeak = 0.0;
  for (var i = lastMsStart; i < n; i++) {
    final v = (bd.getInt16(44 + i * 2, Endian.little) / 32768.0).abs();
    if (v > tailPeak) tailPeak = v;
  }
  return (
    duration: n / 22050,
    rms: rms,
    peak: peak,
    leadMs: first / 22050 * 1000,
    tailPeak: tailPeak,
  );
}

/// Validates the bundled sound assets: files exist, are small, are declared
/// in pubspec, and every feedback event points at a real asset. No audio is
/// decoded or played here.
void main() {
  test('all eight feedback assets exist as small, non-empty WAV files', () {
    expect(allSoundAssetPaths, hasLength(8));
    var total = 0;
    for (final path in allSoundAssetPaths) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path missing');
      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(44), reason: '$path is empty/truncated');
      expect(bytes.length, lessThan(64 * 1024), reason: '$path too large');
      // WAV RIFF magic.
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      total += bytes.length;
    }
    // The whole set stays lightweight (~186 KB today).
    expect(total, lessThan(256 * 1024));
  });

  test('the YAMADA voice assets satisfy the 0.8–1.5 s duration spec', () {
    for (final voice in YamadaVoice.values) {
      final path = yamadaAssetPath(voice);
      final bytes = File(path).readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      final data = ByteData.sublistView(bytes);
      final dataSize = data.getUint32(40, Endian.little); // data chunk size
      final seconds = (dataSize ~/ 2) / 22050; // 16-bit mono @ 22050 Hz
      expect(
        seconds,
        inInclusiveRange(0.8, 1.5),
        reason: '$path is ${seconds.toStringAsFixed(2)}s',
      );
    }
  });

  test('every feedback event maps to a declared, existing asset', () {
    for (final event in FeedbackEvent.values) {
      // The YAMADA event must resolve to one of the two voice assets for
      // every possible voice selection.
      final voices = event == FeedbackEvent.yamada
          ? YamadaVoice.values
          : const <YamadaVoice>[YamadaVoice.deep];
      for (final voice in voices) {
        final path = feedbackPatternFor(event, yamadaVoice: voice).assetPath;
        expect(path, startsWith('assets/sounds/'));
        expect(allSoundAssetPaths, contains(path));
        expect(File(path).existsSync(), isTrue, reason: '$path missing');
      }
    }
  });

  test('hold_out.wav is the preserved, approved asset (M17.2)', () {
    // M17.2 pins the exact bytes of the approved Hold Out sound so it can
    // never be replaced or regenerated differently by accident.
    final bytes = File('assets/sounds/hold_out.wav').readAsBytesSync();
    expect(bytes.length, 13274);
    expect(
      sha256.convert(bytes).toString(),
      '5db1bd3390776a040cf479470513a23d0ab02a616e50172d208386bfc7829bad',
    );
  });

  test('the two YAMADA voices map to two distinct assets', () {
    expect(
      yamadaAssetPath(YamadaVoice.deep),
      isNot(yamadaAssetPath(YamadaVoice.animeGirl)),
    );
    final deep = File(yamadaAssetPath(YamadaVoice.deep)).readAsBytesSync();
    final anime = File(
      yamadaAssetPath(YamadaVoice.animeGirl),
    ).readAsBytesSync();
    expect(
      sha256.convert(deep).toString(),
      isNot(sha256.convert(anime).toString()),
    );
  });

  test('all eight event sounds are distinct from one another', () {
    final hashes = <String>{};
    final durationsInSamples = <int>{};
    for (final path in allSoundAssetPaths) {
      final bytes = File(path).readAsBytesSync();
      hashes.add(sha256.convert(bytes).toString());
      final data = ByteData.sublistView(bytes);
      final dataSize = data.getUint32(40, Endian.little); // data chunk size
      durationsInSamples.add(dataSize ~/ 2); // 16-bit mono samples
    }
    // No two events share the same audio bytes or the same length, so every
    // sound is perceptually distinct (different content, different timing).
    expect(hashes, hasLength(allSoundAssetPaths.length));
    expect(durationsInSamples, hasLength(allSoundAssetPaths.length));
  });

  test('both YAMADA voices are intelligible-grade: instant, unclipped, '
      'clearly audible, and fade cleanly (M17.4)', () {
    for (final voice in YamadaVoice.values) {
      final s = _wavStats(yamadaAssetPath(voice));
      // 0.8–1.5 s duration spec (also asserted above).
      expect(s.duration, inInclusiveRange(0.8, 1.5));
      // Zero leading silence — the word starts immediately, no latency.
      expect(s.leadMs, lessThan(2), reason: '$voice leading silence');
      // No clipping and no full-scale samples.
      expect(s.peak, lessThan(0.98), reason: '$voice peak');
      // Clearly audible on phone speakers (comparable to hold-out/victory).
      expect(s.rms, greaterThan(0.06), reason: '$voice level');
      // Clean fade at the end — the final millisecond is near-silent.
      expect(s.tailPeak, lessThan(0.01), reason: '$voice tail');
    }
  });

  test('reveal.wav meets the M17.4 spec (short, bright, clean reveal)', () {
    const path = 'assets/sounds/reveal.wav';
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path missing');
    final bytes = file.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
    final s = _wavStats(path);
    // Target ~0.3–0.5 s.
    expect(s.duration, inInclusiveRange(0.30, 0.50));
    // Zero leading silence.
    expect(s.leadMs, lessThan(2));
    // No clipping.
    expect(s.peak, lessThan(0.98));
    // Audible presence for a group reveal moment.
    expect(s.rms, greaterThan(0.05));
    // Fades to silence, never a hard cut.
    expect(s.tailPeak, lessThan(0.01));
  });

  test('no sound asset is referenced without being bundled in pubspec', () {
    // The directory-level declaration bundles every file inside it.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/sounds/'));
    // And the sounds directory actually contains exactly the referenced set.
    final onDisk = Directory('assets/sounds')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.wav'))
        .map((f) => f.path.replaceAll('\\', '/'))
        .toSet();
    expect(onDisk, allSoundAssetPaths.toSet());
  });
}
