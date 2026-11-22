import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dmx_controller/core/song/fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake "song": a melody of random notes (with harmonics) changing every
/// 150–400 ms, plus a little noise — enough spectral structure to fingerprint.
Float32List _song(int seed, double seconds) {
  final rnd = math.Random(seed);
  final n = (seconds * fingerprintSampleRate).round();
  final out = Float32List(n);
  var i = 0;
  while (i < n) {
    final len = ((0.15 + rnd.nextDouble() * 0.25) * fingerprintSampleRate).round();
    final f1 = 150 + rnd.nextDouble() * 1500;
    final f2 = 300 + rnd.nextDouble() * 3000;
    for (var k = 0; k < len && i < n; k++, i++) {
      final t = i / fingerprintSampleRate;
      out[i] = 0.4 * math.sin(2 * math.pi * f1 * t) +
          0.2 * math.sin(4 * math.pi * f1 * t) +
          0.25 * math.sin(2 * math.pi * f2 * t) +
          0.05 * (rnd.nextDouble() - 0.5);
    }
  }
  return out;
}

Float32List _clip(Float32List song, double fromSec, double seconds, {double gain = 0.3, double noise = 0.1, int seed = 9}) {
  final rnd = math.Random(seed);
  final from = (fromSec * fingerprintSampleRate).round();
  final n = (seconds * fingerprintSampleRate).round();
  return Float32List.fromList([
    for (var i = 0; i < n; i++) song[from + i] * gain + noise * (rnd.nextDouble() - 0.5),
  ]);
}

/// Plays [song] [rate] times faster with the pitch kept (a DJ's master
/// tempo) — crude: resample, which also shifts pitch; used only for small
/// rates where the ±1 frame tolerance should still carry it.
Float32List _faster(Float32List song, double rate) {
  final n = (song.length / rate).floor();
  return Float32List.fromList([for (var i = 0; i < n; i++) song[(i * rate).floor()]]);
}

void main() {
  final songs = [for (var s = 0; s < 4; s++) _song(s + 1, 60)];
  final index = FingerprintIndex.fromSamples(songs);

  test('finds the right song and position from a noisy, quiet clip', () {
    final match = index.query(_clip(songs[2], 23.4, 6));
    expect(match, isNotNull);
    expect(match!.song, 2);
    expect(match.offsetSec, closeTo(23.4, 0.1));
  });

  test('finds every song at several places', () {
    for (var s = 0; s < songs.length; s++) {
      for (final at in [3.0, 31.7, 50.2]) {
        final match = index.query(_clip(songs[s], at, 6, seed: s * 7 + at.round()));
        expect(match?.song, s, reason: 'song $s at $at');
        expect(match!.offsetSec, closeTo(at, 0.1));
      }
    }
  });

  test('an unknown song is not recognised', () {
    final other = _song(99, 20);
    expect(index.query(_clip(other, 5, 6)), isNull);
  });

  test('silence and plain noise are not recognised', () {
    expect(index.query(Float32List(6 * fingerprintSampleRate)), isNull);
    final rnd = math.Random(3);
    final noise = Float32List.fromList([for (var i = 0; i < 6 * fingerprintSampleRate; i++) rnd.nextDouble() - 0.5]);
    expect(index.query(noise), isNull);
  });

  test('a slightly faster deck (+1 %) is still found', () {
    final fast = _faster(songs[1], 1.01);
    final match = index.query(_clip(fast, 20 / 1.01, 6));
    expect(match?.song, 1);
  });

  test('mic PCM is averaged down to the fingerprint rate', () {
    final pcm = ByteData(16);
    for (var i = 0; i < 8; i++) {
      pcm.setInt16(i * 2, i < 4 ? 16384 : -16384, Endian.little);
    }
    final out = downsampleMicPcm(pcm.buffer.asUint8List());
    expect(out, [0.5, -0.5]);
  });
}
