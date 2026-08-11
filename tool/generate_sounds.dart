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

/// Short, crisp card/paper "snap": a near-instant-attack noise burst with a
/// fast papery decay, a very short bright snap tick, and a tiny second
/// crackle — immediate and subtle, reading as a card rather than a click.
List<double> _cardReveal(Random rng) {
  final n = _samples(0.08);
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    // Papery body: near-instant attack, fast decay. Gains are kept with
    // headroom (peak ~0.8, not 0 dBFS) so the snap stays subtle and never
    // risks distortion on phone speakers.
    final noise = (rng.nextDouble() * 2 - 1) * exp(-t * 70);
    // Bright "snap" tick.
    final tick = 0.24 * sin(2 * _pi * 2600 * t) * exp(-t * 300);
    // Tiny second crackle ~30 ms in (card edges touching). The envelope is a
    // symmetric spike centered on 30 ms so it decays on both sides — never
    // an exp() blow-up (which would clamp at full scale).
    final crackle = i > _samples(0.024) && i < _samples(0.036)
        ? (rng.nextDouble() * 2 - 1) * exp(-((t - 0.03) * 400).abs())
        : 0.0;
    out[i] = noise * 0.62 + tick + crackle * 0.18;
  }
  return out;
}

/// Very short, soft tactile tap for the handoff — quieter than every major
/// event, with a gentle low body so it reads as a touch on the phone.
List<double> _handoff(Random rng) {
  final n = _samples(0.045);
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    final body = sin(2 * _pi * 170 * t) * exp(-t * 95);
    final noise = (rng.nextDouble() * 2 - 1) * exp(-t * 130);
    out[i] = body * 0.16 + noise * 0.14;
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

// ---------------------------------------------------------------------------
// YAMADA sting (M17.5)
//
// A single, punchy anime/mobile-game "special event" reaction SFX — no
// spoken word, no human voice. A strong bright attack leads a quick upward
// C6 → G6 → C7 leap that rings out as a playful tremolo-shimmering D7 chime
// over a soft C-major body, then fades. It communicates "something special
// just happened!" rather than "someone said YAMADA".
// ---------------------------------------------------------------------------

/// YAMADA sting (M17.5): an original "anime game special-event" reaction
/// SFX with no spoken words. Strong initial attack, upward pitch movement
/// (C6 → G6 → C7), and a distinctive final chime with a playful tremolo
/// shimmer — short and punchy, clearly distinct from the reveal (staccato
/// G-A-C bells + separate ding), the elimination thud, and the victory
/// arpeggio, and faded out so it never cuts off.
List<double> _yamada(Random rng) {
  final n = _samples(0.55);
  final out = List<double>.filled(n, 0);
  // Strong attack + rising leap: quick staccato C6 → G6 → C7 steps.
  const steps = [(1046.5, 0.0), (1567.98, 0.045), (2093.0, 0.09)];
  for (final (freq, at) in steps) {
    final start = _samples(at);
    for (var i = start; i < n && i < start + _samples(0.05); i++) {
      final t = (i - start) / _sampleRate;
      final env = exp(-t * 60);
      out[i] += 0.40 * env * sin(2 * _pi * freq * t);
      out[i] += 0.12 * env * sin(2 * _pi * freq * 2 * t);
    }
  }
  // A crisp noise tick on the attack for the "trigger".
  for (var i = 0; i < _samples(0.03); i++) {
    final p = i / _samples(0.03);
    out[i] += 0.16 * (1 - p) * (rng.nextDouble() * 2 - 1);
  }
  // Final impact/chime: a bright D7 with a playful tremolo shimmer over a
  // soft C-major body, ringing out and fading.
  final chimeStart = _samples(0.12);
  for (var i = chimeStart; i < n; i++) {
    final t = (i - chimeStart) / _sampleRate;
    final tremolo = 1 + 0.25 * sin(2 * _pi * 9 * t);
    final env = exp(-t * 14);
    out[i] += 0.38 * env * tremolo * sin(2 * _pi * 2349.32 * t); // D7
    out[i] += 0.10 * env * tremolo * sin(2 * _pi * 4698.64 * t); // D8
    for (final f in const [1046.5, 1318.51, 1567.98]) {
      out[i] += 0.06 * env * sin(2 * _pi * f * t); // C-major body
    }
  }
  // Fade the last 60 ms to silence.
  final fadeStart = n - _samples(0.06);
  for (var i = fadeStart; i < n; i++) {
    out[i] *= (n - i) / (n - fadeStart);
  }
  return out;
}

/// Bright, satisfying, short anime/game reveal (M17.4): a quick upward bell
/// sparkle — G6 → A6 → C7, staccato and shimmering — that lands on a clean,
/// confirmed high "ding" with a soft magical body underneath. Polished
/// mobile-game UI energy: distinct from the victory arpeggio (different
/// pitches, rhythm, and length) and faded out so it never cuts off.
List<double> _reveal(Random rng) {
  final n = _samples(0.36);
  final out = List<double>.filled(n, 0);
  const bells = [1567.98, 1760.0, 2093.0]; // G6 A6 C7
  // Quick upward sparkle run (three fast bell tones, starting at sample 0 so
  // there is zero leading silence).
  for (var k = 0; k < bells.length; k++) {
    final start = _samples(k * 0.038);
    for (var i = start; i < n && i < start + _samples(0.10); i++) {
      final t = (i - start) / _sampleRate;
      final amp = 0.30 * exp(-t * 45);
      // Bell partials: fundamental + octave + a bright third partial.
      out[i] +=
          amp *
          (sin(2 * _pi * bells[k] * t) +
              0.35 * sin(2 * _pi * bells[k] * 2 * t) +
              0.12 * sin(2 * _pi * bells[k] * 3 * t));
    }
  }
  // Final confirmation: a bright C7 "ding" with a soft magical body.
  final dingStart = _samples(0.135);
  for (var i = dingStart; i < n; i++) {
    final t = (i - dingStart) / _sampleRate;
    final env = exp(-t * 16);
    out[i] +=
        0.38 * env * (sin(2 * _pi * 2093 * t) + 0.30 * sin(2 * _pi * 4186 * t));
    for (final f in const [1046.5, 1318.51, 1567.98]) {
      out[i] += 0.06 * env * sin(2 * _pi * f * t);
    }
  }
  // Fade the last 50 ms to silence.
  final fadeStart = n - _samples(0.05);
  for (var i = fadeStart; i < n; i++) {
    out[i] *= (n - i) / (n - fadeStart);
  }
  return out;
}

/// Unmistakable low penalty impact for elimination: a deep pitch-bending
/// thud with a sharp noise attack plus a decisive second thump.
List<double> _elimination(Random rng) {
  final n = _samples(0.32);
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    // Deep thud with a downward pitch bend (110 Hz → ~65 Hz).
    final freq = 110 - 45 * (t / 0.32);
    final thud = sin(2 * _pi * freq * t) * exp(-t * 18);
    // Sharp noise attack for the impact (gain kept below full scale).
    final attack = i < _samples(0.012)
        ? (rng.nextDouble() * 2 - 1) * (1 - i / _samples(0.012))
        : 0.0;
    // Decisive second thump ~110 ms in.
    final second = i > _samples(0.11) && i < _samples(0.20)
        ? 0.45 * sin(2 * _pi * 80 * (t - 0.11)) * exp(-(t - 0.11) * 28)
        : 0.0;
    out[i] = thud * 0.68 + attack * 0.40 + second;
  }
  return out;
}

/// Celebratory victory resolution: a bright C-major arpeggio (C5 → E5 → G5
/// → C6) with a sparkle shimmer that resolves into a short sustained
/// C-major chord — clearly distinct from YAMADA and elimination. The tail is
/// faded out so the resolution ends in silence, never a hard cut.
List<double> _victory(Random rng) {
  const note = 0.15;
  final n = _samples(0.75);
  final out = List<double>.filled(n, 0);
  const notes = [523.25, 659.25, 783.99, 1046.5];
  for (var k = 0; k < notes.length; k++) {
    final start = _samples(k * 0.16);
    for (var i = start; i < n && i < start + _samples(note); i++) {
      final t = (i - start) / _sampleRate;
      final amp =
          0.42 * exp(-t * 24) * (1 + 0.16 * sin(2 * _pi * notes[k] * 2 * t));
      out[i] += amp * sin(2 * _pi * notes[k] * t);
    }
  }
  // Resolution: a short sustained C-major chord.
  final chordStart = _samples(0.58);
  for (var i = chordStart; i < n; i++) {
    final t = (i - chordStart) / _sampleRate;
    final env = exp(-t * 18);
    for (final f in notes) {
      out[i] += 0.16 * env * sin(2 * _pi * f * t);
    }
  }
  // Fade the last 70 ms so the chord resolves to silence, not a click.
  final fadeStart = n - _samples(0.07);
  for (var i = fadeStart; i < n; i++) {
    out[i] *= (n - i) / (n - fadeStart);
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
