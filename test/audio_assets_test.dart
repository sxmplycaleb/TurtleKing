import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/feedback.dart';

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
  test('all seven feedback assets exist as small, non-empty WAV files', () {
    expect(allSoundAssetPaths, hasLength(7));
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

  test('every feedback event maps to a declared, existing asset', () {
    for (final event in FeedbackEvent.values) {
      final path = feedbackPatternFor(event).assetPath;
      expect(path, startsWith('assets/sounds/'));
      expect(allSoundAssetPaths, contains(path));
      expect(File(path).existsSync(), isTrue, reason: '$path missing');
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

  test('the old YAMADA voice assets are removed (M17.5)', () {
    // The two voice clips are gone; the YAMADA event uses a single sting.
    expect(File('assets/sounds/yamada_deep.wav').existsSync(), isFalse);
    expect(File('assets/sounds/yamada_anime.wav').existsSync(), isFalse);
    expect(File('assets/sounds/yamada.wav').existsSync(), isTrue);
    expect(
      allSoundAssetPaths,
      isNot(contains('assets/sounds/yamada_deep.wav')),
    );
    expect(
      allSoundAssetPaths,
      isNot(contains('assets/sounds/yamada_anime.wav')),
    );
  });

  test('all seven event sounds are distinct from one another', () {
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

  test(
    'yamada.wav meets the M17.5 quality spec (short, punchy game sting)',
    () {
      const path = 'assets/sounds/yamada.wav';
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path missing');
      final bytes = file.readAsBytesSync();
      // Valid WAV header (RIFF, PCM, mono, 22050 Hz, 16-bit).
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      final header = ByteData.sublistView(bytes);
      expect(header.getUint16(20, Endian.little), 1); // PCM
      expect(header.getUint16(22, Endian.little), 1); // mono
      expect(header.getUint32(24, Endian.little), 22050); // sample rate
      expect(header.getUint16(34, Endian.little), 16); // bits per sample
      final s = _wavStats(path);
      // Short and punchy — ~0.4–0.8 s.
      expect(s.duration, inInclusiveRange(0.40, 0.80));
      // Zero leading silence.
      expect(s.leadMs, lessThan(2));
      // No clipping / full-scale samples.
      expect(s.peak, lessThan(0.98));
      // Clearly audible for the most dramatic event (above hold-out/victory).
      expect(s.rms, greaterThan(0.08));
      // Clean fade at the end — the final millisecond is near-silent.
      expect(s.tailPeak, lessThan(0.01));
    },
  );

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
