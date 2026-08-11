// Generates the Turtle King sound-effect assets as original, in-repo WAV
// files (no third-party audio). All sounds are synthesized here from basic
// waveforms — sine/sawtooth tones, noise bursts, and decay envelopes — so
// the project owns 100% of the audio and no external licensing applies.
//
// Run from the project root:
//
//     dart run tool/generate_sounds.dart
//
// Output: assets/sounds/*.wav (16-bit PCM, mono, 22050 Hz).
//
// These files are committed so the app never needs to regenerate them at
// build or runtime. Re-running the script reproduces byte-identical output.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int _sampleRate = 22050;
const double _pi = 3.141592653589793;

/// One synthesized sound: name (without extension) + sample builder.
class _Sound {
  const _Sound(this.name, this.builder);

  final String name;
  final List<double> Function(Random rng) builder;
}

/// Short, papery card "snap": a noise burst with a fast decay plus a soft
/// high tick so it reads as a card, not a generic click.
List<double> _cardReveal(Random rng) {
  final n = _samples(0.09);
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    final decay = exp(-t * 42);
    final noise = (rng.nextDouble() * 2 - 1) * decay;
    final tick = 0.35 * sin(2 * _pi * 1850 * t) * exp(-t * 90);
    out[i] = noise * 0.75 + tick;
  }
  return out;
}

/// Very soft, neutral tap for the handoff — quiet and short.
List<double> _handoff(Random rng) {
  final n = _samples(0.055);
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    out[i] = (rng.nextDouble() * 2 - 1) * 0.28 * exp(-t * 85);
  }
  return out;
}

/// Positive confirmation: two ascending sine blips (C5 → E5).
List<double> _holdOut(Random rng) {
  const blip = 0.11;
  final n = _samples(0.30);
  final out = List<double>.filled(n, 0);
  void add(int startSample, double freq, double amp) {
    for (var i = startSample; i < n && i < startSample + _samples(blip); i++) {
      final t = (i - startSample) / _sampleRate;
      out[i] += amp * sin(2 * _pi * freq * t) * exp(-t * 26);
    }
  }

  add(0, 523.25, 0.5);
  add(_samples(0.13), 659.25, 0.5);
  return out;
}

/// Dramatic, comedic "wah": a descending sawtooth slide with light vibrato.
List<double> _yamada(Random rng) {
  final n = _samples(0.48);
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    final progress = i / n;
    final base = 720 - 520 * progress; // 720 Hz → 200 Hz
    final freq = base + 12 * sin(2 * _pi * 9 * t); // subtle vibrato
    final saw = (2 * (t * freq - (t * freq).floor()) - 1);
    out[i] = saw * 0.34 * (0.5 + 0.5 * sin(_pi * progress));
  }
  return out;
}

/// Suspense riser for the group reveal: an ascending sine sweep with a
/// rising shimmer harmonic.
List<double> _reveal(Random rng) {
  final n = _samples(0.62);
  final out = List<double>.filled(n, 0);
  var phase = 0.0;
  var phase2 = 0.0;
  for (var i = 0; i < n; i++) {
    final progress = i / n;
    final freq = 180 + 760 * progress; // 180 Hz → 940 Hz
    phase += 2 * _pi * freq / _sampleRate;
    phase2 += 2 * _pi * freq * 2 / _sampleRate;
    final envelope = 0.55 * (0.35 + 0.65 * progress);
    out[i] = sin(phase) * envelope + 0.22 * sin(phase2) * envelope * progress;
  }
  return out;
}

/// Low, heavy thud for elimination: a 100 Hz decaying tone plus a noise
/// transient.
List<double> _elimination(Random rng) {
  final n = _samples(0.34);
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    final decay = exp(-t * 16);
    final thud = sin(2 * _pi * 100 * t) * decay;
    final transient = i < _samples(0.015)
        ? (rng.nextDouble() * 2 - 1) * (1 - i / _samples(0.015))
        : 0.0;
    out[i] = thud * 0.85 + transient * 0.5;
  }
  return out;
}

/// Celebratory victory arpeggio: C5 → E5 → G5 → C6 with quick decay.
List<double> _victory(Random rng) {
  const note = 0.16;
  final n = _samples(0.72);
  final out = List<double>.filled(n, 0);
  const notes = [523.25, 659.25, 783.99, 1046.5];
  for (var k = 0; k < notes.length; k++) {
    final start = _samples(k * 0.17);
    for (var i = start; i < n && i < start + _samples(note); i++) {
      final t = (i - start) / _sampleRate;
      final amp =
          0.42 * exp(-t * 22) * (1 + 0.18 * sin(2 * _pi * notes[k] * 2 * t));
      out[i] += amp * sin(2 * _pi * notes[k] * t);
    }
  }
  return out;
}

int _samples(double seconds) => (seconds * _sampleRate).round();

/// Writes [samples] as a 16-bit PCM mono WAV file at [path].
void _writeWav(String path, List<double> samples) {
  final bytes = ByteData(44 + samples.length * 2);

  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  bytes.setUint32(4, 36 + samples.length * 2, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // PCM chunk size
  bytes.setUint16(20, 1, Endian.little); // PCM format
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, _sampleRate, Endian.little);
  bytes.setUint32(28, _sampleRate * 2, Endian.little); // byte rate
  bytes.setUint16(32, 2, Endian.little); // block align
  bytes.setUint16(34, 16, Endian.little); // bits per sample
  writeString(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    var v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(44 + i * 2, v, Endian.little);
  }

  File(path).writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  final sounds = <_Sound>[
    _Sound('card_reveal', _cardReveal),
    _Sound('handoff', _handoff),
    _Sound('hold_out', _holdOut),
    _Sound('yamada', _yamada),
    _Sound('reveal', _reveal),
    _Sound('elimination', _elimination),
    _Sound('victory', _victory),
  ];

  final dir = Directory('assets/sounds');
  dir.createSync(recursive: true);

  var totalBytes = 0;
  for (final sound in sounds) {
    final samples = sound.builder(Random(42)); // seeded: reproducible output
    final path = '${dir.path}/${sound.name}.wav';
    _writeWav(path, samples);
    final size = File(path).lengthSync();
    totalBytes += size;
    stdout.writeln(
      'wrote $path (${samples.length} samples, '
      '${(samples.length / _sampleRate).toStringAsFixed(2)}s, $size bytes)',
    );
  }
  stdout.writeln('total: $totalBytes bytes');
}
