import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/feedback.dart';

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
    // The whole set stays lightweight (~115 KB today).
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
