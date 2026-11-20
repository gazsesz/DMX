import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Audio fingerprints for recognising a known song through the microphone:
/// the loudest spectral peaks of each moment, paired up into "landmarks"
/// (frequency of one peak, frequency of a later one, time between them).
/// A landmark doesn't care how loud the room is or what the speaker does to
/// the tone, only that the same notes come at the same distances — so a few
/// seconds of a song heard in a club share many landmarks with the file, all
/// at the same time offset, while other songs only share a scatter.
///
/// Everything here is pure maths on samples at [fingerprintSampleRate], so
/// it runs in an isolate and in tests.
const fingerprintSampleRate = 11025;

/// ~93 ms frames, half overlapped: ~21.5 frames per second.
const _frame = 1024;
const _hop = 512;

/// Seconds per fingerprint frame.
const fingerprintFrameSec = _hop / fingerprintSampleRate;

/// The analysed range: ~110 Hz – 4 kHz, where music has its notes and a
/// phone microphone still hears well. Split into bands so every register
/// gets peaks, not just the bass.
const _bands = [10, 20, 40, 80, 160, 380];

/// How far apart in time a pair of peaks may be, in frames (~1.5 s).
const _maxPairDt = 32;

/// How many later peaks each peak is paired with.
const _fanOut = 5;

/// A peak has to stand this far (natural log) above its frame's average.
const _peakFloor = 1.2;

class _Peak {
  final int t;
  final int bin;
  const _Peak(this.t, this.bin);
}

/// The spectral peaks of [samples]: per frame, per band, the strongest bin
/// when it clearly beats the frame's average and is the loudest of its band
/// within ±2 frames.
List<_Peak> _peaks(Float32List samples) {
  final frames = samples.length < _frame ? 0 : 1 + (samples.length - _frame) ~/ _hop;
  if (frames == 0) return const [];
  final fft = FFT(_frame);
  final window = Window.hanning(_frame);
  final buffer = Float64List(_frame);
  final bandCount = _bands.length - 1;
  final bandBin = Int32List(frames * bandCount);
  final bandValue = Float64List(frames * bandCount);
  final keep = List<bool>.filled(frames * bandCount, false);

  for (var f = 0; f < frames; f++) {
    final start = f * _hop;
    for (var i = 0; i < _frame; i++) {
      buffer[i] = samples[start + i] * window[i];
    }
    final spectrum = fft.realFft(buffer);
    var sum = 0.0;
    final logs = Float64List(_bands.last);
    for (var b = _bands.first; b < _bands.last; b++) {
      final c = spectrum[b];
      final mag = math.log(1e-9 + math.sqrt(c.x * c.x + c.y * c.y));
      logs[b] = mag;
      sum += mag;
    }
    final mean = sum / (_bands.last - _bands.first);
    for (var band = 0; band < bandCount; band++) {
      var best = _bands[band];
      for (var b = _bands[band] + 1; b < _bands[band + 1]; b++) {
        if (logs[b] > logs[best]) best = b;
      }
      final index = f * bandCount + band;
      bandBin[index] = best;
      bandValue[index] = logs[best];
      keep[index] = logs[best] > mean + _peakFloor;
    }
  }

  final peaks = <_Peak>[];
  for (var f = 0; f < frames; f++) {
    for (var band = 0; band < bandCount; band++) {
      final index = f * bandCount + band;
      if (!keep[index]) continue;
      final value = bandValue[index];
      var isMax = true;
      for (var d = -2; d <= 2 && isMax; d++) {
        final g = f + d;
        if (d == 0 || g < 0 || g >= frames) continue;
        if (bandValue[g * bandCount + band] > value) isMax = false;
      }
      if (isMax) peaks.add(_Peak(f, bandBin[index]));
    }
  }
  return peaks;
}

int _hash(int f1, int f2, int dt) => (f1 << 15) | (f2 << 6) | dt;

/// Landmarks of [samples] as `(hash << 20) | frame` values, in time order.
List<int> fingerprintLandmarks(Float32List samples) {
  final peaks = _peaks(samples);
  final out = <int>[];
  for (var i = 0; i < peaks.length; i++) {
    final a = peaks[i];
    var paired = 0;
    for (var j = i + 1; j < peaks.length && paired < _fanOut; j++) {
      final b = peaks[j];
      final dt = b.t - a.t;
      if (dt <= 0) continue;
      if (dt > _maxPairDt) break;
      out.add((_hash(a.bin, b.bin, dt) << 20) | a.t);
      paired++;
    }
  }
  return out;
}

/// Where a clip was found: which song, and where in that song the clip
/// started.
class FingerprintMatch {
  final int song;

  /// The song position at the clip's first sample, in seconds.
  final double offsetSec;

  /// Landmarks agreeing on this song and offset.
  final int votes;

  /// The best agreement any other song (or another offset) found.
  final int runnerUp;

  const FingerprintMatch({required this.song, required this.offsetSec, required this.votes, required this.runnerUp});

  @override
  String toString() => 'FingerprintMatch(song $song @ ${offsetSec.toStringAsFixed(2)} s, $votes vs $runnerUp)';
}

/// Every known song's landmarks in one sorted list, for lookups by hash:
/// each entry is `(hash << 32) | (song << 20) | frame`.
class FingerprintIndex {
  /// Fewer agreeing landmarks than this is noise.
  static const minVotes = 10;

  final Int64List _entries;
  final int songCount;

  FingerprintIndex._(this._entries, this.songCount);

  /// Builds an index from each song's [fingerprintLandmarks].
  factory FingerprintIndex.fromLandmarks(List<List<int>> songs) {
    var total = 0;
    for (final s in songs) {
      total += s.length;
    }
    final entries = Int64List(total);
    var k = 0;
    for (var song = 0; song < songs.length; song++) {
      for (final l in songs[song]) {
        final hash = l >> 20;
        final t = l & 0xFFFFF;
        entries[k++] = (hash << 32) | (song << 20) | t;
      }
    }
    entries.sort();
    return FingerprintIndex._(entries, songs.length);
  }

  /// Builds an index straight from the songs' samples.
  factory FingerprintIndex.fromSamples(List<Float32List> songs) =>
      FingerprintIndex.fromLandmarks([for (final s in songs) fingerprintLandmarks(s)]);

  int get size => _entries.length;

  int _lowerBound(int key) {
    var lo = 0, hi = _entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_entries[mid] < key) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Finds [clip] (samples at [fingerprintSampleRate]) among the songs, or
  /// null when nothing agrees clearly enough.
  FingerprintMatch? query(Float32List clip) => queryLandmarks(fingerprintLandmarks(clip));

  FingerprintMatch? queryLandmarks(List<int> landmarks) {
    if (landmarks.isEmpty || _entries.isEmpty) return null;
    // Votes per (song, offset in frames); the offset is shifted to stay
    // positive in the key.
    const shift = 1 << 19;
    final votes = <int, int>{};
    for (final l in landmarks) {
      final hash = l >> 20;
      final tq = l & 0xFFFFF;
      final dt = hash & 0x3F;
      // A DJ's tempo change stretches the gaps a little: accept ±1 frame.
      for (final d in const [0, -1, 1]) {
        final ndt = dt + d;
        if (ndt <= 0 || ndt > _maxPairDt) continue;
        final h = (hash & ~0x3F) | ndt;
        final from = _lowerBound(h << 32);
        for (var i = from; i < _entries.length; i++) {
          final e = _entries[i];
          if (e >> 32 != h) break;
          final song = (e >> 20) & 0xFFF;
          final ts = e & 0xFFFFF;
          final key = (song << 21) | (ts - tq + shift);
          votes[key] = (votes[key] ?? 0) + 1;
        }
      }
    }
    if (votes.isEmpty) return null;
    // Neighbouring offsets count together (the clip rarely starts exactly
    // on a frame boundary).
    var bestKey = -1, best = 0;
    final scored = <int, int>{};
    for (final entry in votes.entries) {
      final score = entry.value + (votes[entry.key - 1] ?? 0) + (votes[entry.key + 1] ?? 0);
      scored[entry.key] = score;
      if (score > best) {
        best = score;
        bestKey = entry.key;
      }
    }
    final bestSong = bestKey >> 21;
    final bestOffset = (bestKey & ((1 << 21) - 1)) - shift;
    var runnerUp = 0;
    for (final entry in scored.entries) {
      final song = entry.key >> 21;
      final offset = (entry.key & ((1 << 21) - 1)) - shift;
      if (song == bestSong && (offset - bestOffset).abs() <= 2) continue;
      if (entry.value > runnerUp) runnerUp = entry.value;
    }
    if (best < minVotes || best < runnerUp * 2) return null;
    return FingerprintMatch(
      song: bestSong,
      offsetSec: bestOffset * fingerprintFrameSec,
      votes: best,
      runnerUp: runnerUp,
    );
  }
}

/// Microphone PCM (16-bit little-endian at 44.1 kHz) down to
/// [fingerprintSampleRate]: every four samples averaged, a crude but real
/// low-pass before dropping to a quarter of the rate.
Float32List downsampleMicPcm(Uint8List pcm16) {
  final data = ByteData.sublistView(pcm16);
  final samples = pcm16.length ~/ 2;
  final out = Float32List(samples ~/ 4);
  for (var i = 0; i < out.length; i++) {
    var sum = 0;
    for (var k = 0; k < 4; k++) {
      sum += data.getInt16((i * 4 + k) * 2, Endian.little);
    }
    out[i] = sum / 4 / 32768;
  }
  return out;
}
