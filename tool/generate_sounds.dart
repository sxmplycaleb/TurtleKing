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
const double _twoPi = 2 * _pi;

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
// YAMADA voice synthesis (M17.3, redesigned in M17.4)
//
// "Yah-mah-DAH!!!" spoken-style clips synthesized with additive harmonic
// voice synthesis: a glottal pulse train (pitch + vibrato) shaped by
// vocal-tract formants, arranged as explicit phoneme segments (see
// `_yamadaVoice`) so the word is clearly intelligible. The Deep Voice has a
// low pitch, dark formants, and a sub-octave "power" body; the Anime Girl
// voice has a high bright pitch, an extended final "daa", and a playful
// exclamation. Both are original synthesized speech — they imitate no
// specific character, voice actor, or copyrighted performance.
// ---------------------------------------------------------------------------

/// One vocal-tract resonance: center frequency, bandwidth, gain.
class _Formant {
  const _Formant(this.freq, this.bw, this.gain);

  final double freq;
  final double bw;
  final double gain;
}

/// Parameters for one "Yamadaa!!!" voice clip.
class _VoiceSpec {
  const _VoiceSpec({
    required this.f0Start,
    required this.f0End,
    required this.vibratoHz,
    required this.vibratoDepth,
    required this.formantsA,
    required this.formantsNasal,
    required this.amp,
    required this.daaDur,
    required this.breath,
    required this.harmonics,
    required this.subGain,
  });

  /// Pitch at the start of "Ya" and at the end of the final "daa!!!".
  final double f0Start;
  final double f0End;
  final double vibratoHz;
  final double vibratoDepth; // fraction of the pitch

  /// The /a/ vowel and /m/ nasal formant sets.
  final List<_Formant> formantsA;
  final List<_Formant> formantsNasal;

  final double amp;

  /// Duration of the final, emphasized "daa!!!" beat (seconds). The YAH and
  /// mah beats use fixed articulatory timing shared by both voices.
  final double daaDur;

  /// Breathiness (noise) mixed into the exclamation, growing toward "!!!".
  final double breath;

  /// Number of pitch harmonics kept.
  final int harmonics;

  /// Sub-octave body gain ("power" for the deep voice).
  final double subGain;
}

/// Resonance gain of [f] under a formant at [freq] with bandwidth [bw].
/// Standard two-pole resonator magnitude response.
double _formantGain(double f, double freq, double bw) {
  final d = freq * freq - f * f;
  return freq * freq / sqrt(d * d + bw * bw * f * f);
}

/// Adds a voiced segment of [count] samples at [start] into [out]: a glottal
/// pulse train at the interpolated pitch (with vibrato) shaped by [formants],
/// normalized per sample so the vowel is stable across harmonic counts.
void _addVowel(
  List<double> out,
  int start,
  int count,
  double f0Start,
  double f0End,
  List<_Formant> formants, {
  required double amp,
  required double vibratoHz,
  required double vibratoDepth,
  required int harmonics,
  double breath = 0,
  double subGain = 0,
  Random? rng,
}) {
  final end = min(start + count, out.length);
  final phases = List<double>.filled(harmonics, 0);
  var subPhase = 0.0;
  for (var i = start; i < end; i++) {
    final t = i / _sampleRate;
    final progress = (i - start) / count;
    final f0 =
        f0Start +
        (f0End - f0Start) * progress +
        vibratoDepth * f0Start * sin(_twoPi * vibratoHz * t);
    var s = 0.0;
    var gainSum = 0.0;
    for (var k = 1; k <= harmonics; k++) {
      final f = k * f0;
      if (f >= _sampleRate / 2) break;
      var g = 0.0;
      for (final formant in formants) {
        g += formant.gain * _formantGain(f, formant.freq, formant.bw);
      }
      // Glottal spectral tilt: higher harmonics roll off.
      g /= 1 + pow(f / 4000, 2.2);
      gainSum += g;
      phases[k - 1] += _twoPi * f / _sampleRate;
      s += g * sin(phases[k - 1]);
    }
    if (gainSum > 0) s /= gainSum;
    // Sub-octave body for chest "power".
    if (subGain > 0) {
      subPhase += _twoPi * (f0 / 2) / _sampleRate;
      s += subGain * sin(subPhase);
    }
    // Breathiness growing toward the "!!!".
    if (breath > 0 && rng != null) {
      s += breath * (0.4 + 1.2 * progress) * (rng.nextDouble() * 2 - 1);
    }
    // Smooth attack/release so syllables blend naturally.
    final attack = (i - start) / _samples(0.010);
    final release = (end - 1 - i) / _samples(0.030);
    final env = min(1.0, min(attack, release));
    out[i] += s * amp * env;
  }
}

/// Synthesizes one intelligible "Yah-mah-DAH!!!" clip from [spec] using an
/// explicit phoneme-segment approach (M17.4). Articulatory timing:
///
///     /j/  YAH      /m/  mah    closure /d/  DAH!!!
///     35ms 150ms    50ms 110ms  30ms     8ms  (daaDur)
///
/// YAH + mah are glued into one two-beat "YAMA" unit (no gap between the
/// syllables; the /m/ nasal is a brief amplitude dip, not a separate beat),
/// while a real stop-consonant closure gap before the /d/ makes the final
/// "DAH" snap as its own decisive beat. Consonants are clearly articulated —
/// a rising /j/ fricative, a nasal /m/ hum, a broadband /d/ release — and the
/// /a/ vowels use a clear F1 so the word never collapses into "yuh-muh-duh".
List<double> _yamadaVoice(Random rng, _VoiceSpec spec) {
  // Articulatory timing (seconds), shared by both voices — the character
  // difference comes from pitch, formants, and the extended final "daa".
  const jGlide = 0.035; // /j/ fricative glide into YAH
  const yahDur = 0.15; // YAH vowel
  const mNasal = 0.05; // /m/ nasal closure (lips together)
  const mahDur = 0.11; // second /a/ vowel ("mah")
  const closure = 0.030; // stop occlusion: silence before the /d/
  const dBurst = 0.008; // /d/ release transient

  final yahStart = 0;
  final yahEnd = _samples(jGlide + yahDur);
  final mStart = yahEnd;
  final mEnd = mStart + _samples(mNasal);
  final mahEnd = mEnd + _samples(mahDur);
  final dStart = mahEnd + _samples(closure);
  final daaStart = dStart + _samples(dBurst);
  final n = daaStart + _samples(spec.daaDur);
  final out = List<double>.filled(n, 0);
  final f0 = spec.f0Start;
  final f0End = spec.f0End;
  final f0Span = f0End - f0;

  // /j/ glide: a fricative that swells and hands off to the vowel, so "Ya"
  // reads with an explicit initial consonant rather than a bare "Ah".
  for (var i = 0; i < _samples(jGlide); i++) {
    final p = i / _samples(jGlide);
    out[i] += 0.16 * sin(_pi * p) * (rng.nextDouble() * 2 - 1);
  }

  // YAH: the stressed first beat — a strong, clear /a/ vowel.
  _addVowel(
    out,
    yahStart,
    yahEnd - yahStart,
    f0 * 1.02,
    f0 * 1.08,
    spec.formantsA,
    amp: spec.amp * 0.95,
    vibratoHz: spec.vibratoHz,
    vibratoDepth: spec.vibratoDepth,
    harmonics: spec.harmonics,
    subGain: spec.subGain,
  );

  // /m/ nasal: lips closed — low, dull sonorant with a slight pitch dip,
  // directly glued to YAH so the pair reads as one "YAMA" unit.
  _addVowel(
    out,
    mStart,
    mEnd - mStart,
    f0 * 1.06,
    f0 * 0.98,
    spec.formantsNasal,
    amp: spec.amp * 0.5,
    vibratoHz: spec.vibratoHz,
    vibratoDepth: spec.vibratoDepth,
    harmonics: spec.harmonics,
  );

  // mah: the /a/ tail of the YAMA beat, lighter than YAH.
  _addVowel(
    out,
    mEnd,
    mahEnd - mEnd,
    f0 * 0.99,
    f0 + f0Span * 0.22,
    spec.formantsA,
    amp: spec.amp * 0.8,
    vibratoHz: spec.vibratoHz,
    vibratoDepth: spec.vibratoDepth,
    harmonics: spec.harmonics,
    subGain: spec.subGain,
  );

  // Stop occlusion: the 30 ms before [dStart] is left silent so the /d/
  // reads as a true stop consonant.

  // /d/ release: a crisp broadband transient, then the vowel immediately.
  for (var i = dStart; i < daaStart; i++) {
    final p = (i - dStart) / _samples(dBurst);
    out[i] += 0.28 * (1 - p) * (rng.nextDouble() * 2 - 1);
  }

  // DAH!!!: the emphasized final beat — strong attack, rising pitch,
  // vibrato, and breath that grows toward the "!!!".
  _addVowel(
    out,
    daaStart,
    n - daaStart,
    f0 + f0Span * 0.35,
    f0End,
    spec.formantsA,
    amp: spec.amp * 1.15,
    vibratoHz: spec.vibratoHz,
    vibratoDepth: spec.vibratoDepth,
    harmonics: spec.harmonics,
    breath: spec.breath,
    subGain: spec.subGain,
    rng: rng,
  );

  return out;
}

/// Deep Voice: low, dark, powerful, playful-dramatic "Yah-mah-DAH!!!".
/// Clear /a/ formants (F1 ~720 Hz), a reduced sub-octave so the vowels are
/// not masked, and a strong rising final beat — the voice stays present on
/// phone speakers without disappearing into low frequencies.
List<double> _yamadaDeep(Random rng) {
  return _yamadaVoice(
    rng,
    const _VoiceSpec(
      f0Start: 105,
      f0End: 165,
      vibratoHz: 4.5,
      vibratoDepth: 0.018,
      formantsA: [
        _Formant(720, 90, 1.0),
        _Formant(1180, 130, 0.85),
        _Formant(2500, 200, 0.45),
        _Formant(3300, 260, 0.25),
      ],
      formantsNasal: [
        _Formant(250, 100, 1.0),
        _Formant(1050, 180, 0.5),
        _Formant(2200, 250, 0.35),
      ],
      amp: 0.5,
      daaDur: 0.55,
      breath: 0.015,
      harmonics: 30,
      subGain: 0.14,
    ),
  );
}

/// Anime Girl voice: bright, energetic, playful-dramatic "Yah-mah-DAAH!!!"
/// with an extended final "daa". Clear /a/ formants and gentler high-formant
/// gains and breath than before keep it bright but never harsh or piercing.
/// Original synthesis — no specific character or voice actor is imitated.
List<double> _yamadaAnime(Random rng) {
  return _yamadaVoice(
    rng,
    const _VoiceSpec(
      f0Start: 300,
      f0End: 440,
      vibratoHz: 6.0,
      vibratoDepth: 0.025,
      formantsA: [
        _Formant(830, 110, 1.0),
        _Formant(1450, 140, 0.9),
        _Formant(2800, 240, 0.55),
        _Formant(3850, 300, 0.35),
      ],
      formantsNasal: [
        _Formant(300, 110, 1.0),
        _Formant(1200, 190, 0.5),
        _Formant(2400, 260, 0.4),
      ],
      amp: 0.46,
      daaDur: 0.72,
      breath: 0.02,
      harmonics: 24,
      subGain: 0.06,
    ),
  );
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
    _Sound('yamada_deep', _yamadaDeep),
    _Sound('yamada_anime', _yamadaAnime),
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
