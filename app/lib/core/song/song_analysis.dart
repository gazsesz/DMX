import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import '../../models/song_show.dart';

/// What offline analysis finds in a song.
class SongAnalysis {
  /// Tempo, beat-grid offset (where beat 0 falls, ms) and how sure we are of
  /// the tempo (0..1: how much the best candidate stands out).
  final double bpm;
  final int beatOffsetMs;
  final double tempoConfidence;

  /// Energy per bar (four beats), 0..1, from the beat-grid start; `lowBand`
  /// is the bass-only version — a kick dropping in or out shows there first.
  final List<double> barLevel;
  final List<double> barLow;

  /// Sections found, in beats, bar-aligned and labelled by what they do.
  final List<SongSection> sections;

  const SongAnalysis({
    required this.bpm,
    required this.beatOffsetMs,
    required this.tempoConfidence,
    required this.barLevel,
    required this.barLow,
    required this.sections,
  });
}

const _frame = 1024;
const _hop = 256;

/// Analyses mono [samples] taken at [sampleRate]: tempo, beat grid and
/// sections. Pure, so it runs in an isolate and is tested on synthetic audio.
///
/// This is a heuristic, not a transcription: tempo from the autocorrelation of
/// the onset curve, the grid phase from the best-fitting comb, sections from
/// bar-level energy and bass presence. It will be wrong on some songs, which
/// is why everything it produces is editable afterwards.
SongAnalysis analyzeSong(Float32List samples, int sampleRate) {
  final frames = _spectrogram(samples, sampleRate);
  final hopSec = _hop / sampleRate;
  if (frames.length < 64) {
    return const SongAnalysis(bpm: 120, beatOffsetMs: 0, tempoConfidence: 0, barLevel: [], barLow: [], sections: []);
  }

  final novelty = _novelty(frames);
  final tempo = _estimateTempo(novelty, hopSec);
  final grid = _refineGrid(novelty, hopSec, tempo.bpm);
  // The onset curve peaks while a transient is still entering the analysis
  // window, so beats read early by most of a window; measured on synthetic
  // clicks it is ~0.7 of the window length.
  final offsetSec = (grid.offsetSec + 0.7 * _frame / sampleRate) % (60 / grid.bpm);
  final beatSec = 60 / grid.bpm;

  // Bar-level energy on the grid.
  final bars = ((frames.length * hopSec - offsetSec) / (beatSec * 4)).floor();
  final level = List<double>.filled(math.max(bars, 0), 0);
  final low = List<double>.filled(math.max(bars, 0), 0);
  final counts = List<int>.filled(math.max(bars, 0), 0);
  for (var i = 0; i < frames.length; i++) {
    final t = i * hopSec - offsetSec;
    if (t < 0) continue;
    final bar = (t / (beatSec * 4)).floor();
    if (bar >= bars) break;
    level[bar] += frames[i].total;
    low[bar] += frames[i].low;
    counts[bar]++;
  }
  for (var b = 0; b < bars; b++) {
    if (counts[b] > 0) {
      level[b] /= counts[b];
      low[b] /= counts[b];
    }
  }
  final normLevel = _normalise(level);
  final normLow = _normalise(low);

  return SongAnalysis(
    bpm: grid.bpm,
    beatOffsetMs: (offsetSec * 1000).round(),
    tempoConfidence: tempo.confidence,
    barLevel: normLevel,
    barLow: normLow,
    sections: segmentSections(normLevel, normLow),
  );
}

class _Frame {
  final double total;
  final double low;
  final Float64List mags;
  _Frame(this.total, this.low, this.mags);
}

List<_Frame> _spectrogram(Float32List samples, int sampleRate) {
  // Bass is everything under ~150 Hz: a kick's body, a sub bass — not a pad.
  final lowBins = math.max(2, (150 / (sampleRate / _frame)).round());
  final fft = FFT(_frame);
  final window = Float64List.fromList([
    for (var i = 0; i < _frame; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / (_frame - 1)),
  ]);
  final frames = <_Frame>[];
  final buffer = Float64List(_frame);
  for (var start = 0; start + _frame <= samples.length; start += _hop) {
    for (var i = 0; i < _frame; i++) {
      buffer[i] = samples[start + i] * window[i];
    }
    final spectrum = fft.realFft(buffer);
    final mags = Float64List(_frame ~/ 2);
    var total = 0.0;
    var low = 0.0;
    for (var k = 1; k < _frame ~/ 2; k++) {
      final c = spectrum[k];
      final m = math.sqrt(c.x * c.x + c.y * c.y);
      mags[k] = m;
      total += m;
      if (k < lowBins) low += m;
    }
    frames.add(_Frame(total, low, mags));
  }
  return frames;
}

/// Positive spectral flux on a log-compressed spectrum — a curve that spikes
/// where something new starts (a kick, a snare, a hat).
List<double> _novelty(List<_Frame> frames) {
  final out = List<double>.filled(frames.length, 0);
  for (var i = 1; i < frames.length; i++) {
    var flux = 0.0;
    final a = frames[i].mags;
    final b = frames[i - 1].mags;
    for (var k = 1; k < a.length; k++) {
      final d = math.log(1 + 100 * a[k]) - math.log(1 + 100 * b[k]);
      if (d > 0) flux += d;
    }
    out[i] = flux;
  }
  // Remove the slow trend so only the pulses are left.
  const w = 20;
  final cleaned = List<double>.filled(out.length, 0);
  for (var i = 0; i < out.length; i++) {
    final from = math.max(0, i - w);
    final to = math.min(out.length, i + w + 1);
    var sum = 0.0;
    for (var j = from; j < to; j++) {
      sum += out[j];
    }
    cleaned[i] = math.max(0, out[i] - sum / (to - from));
  }
  return cleaned;
}

class _Tempo {
  final double bpm;
  final double confidence;
  const _Tempo(this.bpm, this.confidence);
}

/// Tempo from the autocorrelation of the onset curve, between 70 and 180 BPM,
/// preferring the 90–150 range when a candidate and its double/half are close
/// (the usual octave ambiguity).
_Tempo _estimateTempo(List<double> novelty, double hopSec) {
  const minBpm = 70.0;
  const maxBpm = 180.0;
  final minLag = (60 / maxBpm / hopSec).floor();
  final maxLag = (60 / minBpm / hopSec).ceil();
  final ac = List<double>.filled(maxLag + 2, 0);
  for (var lag = minLag - 1; lag <= maxLag + 1; lag++) {
    var sum = 0.0;
    for (var i = lag; i < novelty.length; i++) {
      sum += novelty[i] * novelty[i - lag];
    }
    ac[lag] = sum / (novelty.length - lag);
  }
  // Emphasise lags that are also strong at 2x and 4x (a steady pulse).
  double score(int lag) {
    var s = ac[lag];
    if (lag * 2 <= maxLag + 1) s += 0.5 * ac[lag * 2];
    return s;
  }

  var bestLag = minLag;
  var best = -1.0;
  var total = 0.0;
  for (var lag = minLag; lag <= maxLag; lag++) {
    final s = score(lag);
    total += s;
    if (s > best) {
      best = s;
      bestLag = lag;
    }
  }
  // Sub-lag precision by parabolic interpolation around the peak.
  var refined = bestLag.toDouble();
  if (bestLag > minLag && bestLag < maxLag) {
    final a = score(bestLag - 1);
    final b = score(bestLag);
    final c = score(bestLag + 1);
    final denom = a - 2 * b + c;
    if (denom != 0) refined += 0.5 * (a - c) / denom;
  }
  var bpm = 60 / (refined * hopSec);
  while (bpm < 85) {
    bpm *= 2;
  }
  while (bpm > 175) {
    bpm /= 2;
  }
  final mean = total / (maxLag - minLag + 1);
  final confidence = mean <= 0 ? 0.0 : ((best / mean - 1) / 6).clamp(0.0, 1.0);
  return _Tempo(double.parse(bpm.toStringAsFixed(1)), confidence);
}


List<double> _normalise(List<double> values) {
  if (values.isEmpty) return values;
  // Log scale, then stretch the 5th–95th percentile to 0..1, so a quiet song
  // and a loud one segment the same way.
  final logs = [for (final v in values) math.log(v + 1e-9)];
  final sorted = [...logs]..sort();
  final lo = sorted[(sorted.length * 0.05).floor()];
  final hi = sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())];
  final span = hi - lo;
  if (span <= 1e-9) return List<double>.filled(values.length, 0.5);
  return [for (final l in logs) ((l - lo) / span).clamp(0.0, 1.0)];
}

/// Splits a song into labelled sections from per-bar [level] and bass
/// presence [low] (both 0..1). Boundaries are placed on a 4-bar grid where the
/// energy changes; each stretch is then named by how loud it is and what
/// surrounds it.
List<SongSection> segmentSections(List<double> level, List<double> low) {
  final bars = level.length;
  if (bars < 8) return const [];

  // Blend: the bass tells drops from breaks even when the highs keep going.
  final feature = [for (var i = 0; i < bars; i++) 0.5 * level[i] + 0.5 * low[i]];

  double mean(int from, int to) {
    final a = from.clamp(0, bars);
    final b = to.clamp(0, bars);
    if (b <= a) return 0;
    var s = 0.0;
    for (var i = a; i < b; i++) {
      s += feature[i];
    }
    return s / (b - a);
  }

  // Candidate boundaries every 4 bars where the next 4 bars differ from the
  // previous 4; keep only local maxima of the difference above a threshold.
  const step = 4;
  final scores = <int, double>{};
  for (var b = step; b <= bars - step; b += step) {
    scores[b] = (mean(b, b + step) - mean(b - step, b)).abs();
  }
  final boundaries = <int>[0];
  for (final entry in scores.entries) {
    final b = entry.key;
    final prev = scores[b - step] ?? 0;
    final next = scores[b + step] ?? 0;
    if (entry.value >= 0.18 && entry.value >= prev && entry.value >= next) boundaries.add(b);
  }
  boundaries.add(bars);

  // Merge anything shorter than 8 bars into its neighbour.
  var i = 1;
  while (i < boundaries.length - 1) {
    if (boundaries[i] - boundaries[i - 1] < 8) {
      boundaries.removeAt(i);
    } else {
      i++;
    }
  }
  if (boundaries.length > 2 && boundaries[boundaries.length - 1] - boundaries[boundaries.length - 2] < 8) {
    boundaries.removeAt(boundaries.length - 2);
  }

  final means = [for (var s = 0; s < boundaries.length - 1; s++) mean(boundaries[s], boundaries[s + 1])];
  final sortedMeans = [...means]..sort();
  final high = sortedMeans[(sortedMeans.length * 0.55).floor().clamp(0, sortedMeans.length - 1)];

  final kinds = <SongSectionKind>[];
  for (var s = 0; s < means.length; s++) {
    final isHigh = means[s] >= high && means[s] >= 0.55;
    final nextHigh = s + 1 < means.length && means[s + 1] >= high && means[s + 1] >= 0.55;
    final first = s == 0;
    final last = s == means.length - 1;
    if (isHigh) {
      kinds.add(SongSectionKind.drop);
    } else if (nextHigh && !first && means[s] > (s > 0 ? means[s - 1] : 0) - 0.05) {
      kinds.add(SongSectionKind.build);
    } else if (first) {
      kinds.add(SongSectionKind.intro);
    } else if (last) {
      kinds.add(SongSectionKind.outro);
    } else {
      kinds.add(SongSectionKind.breakdown);
    }
  }
  // A song that starts straight in the drop has no intro; an intro that is
  // also followed by a drop is a build of its own — leave as classified.

  return [
    for (var s = 0; s < means.length; s++)
      SongSection(
        startBeat: boundaries[s] * 4.0,
        lengthBeats: (boundaries[s + 1] - boundaries[s]) * 4.0,
        kind: kinds[s],
      ),
  ];
}

/// Fine-tunes tempo and grid phase together: over a whole song a 0.5% tempo
/// error is half a beat of drift, so the coarse autocorrelation figure is
/// only a starting point. Scores a comb of beat positions (onset curve read
/// with linear interpolation) for tempos within ±1.5 BPM and every phase.
({double bpm, double offsetSec}) _refineGrid(List<double> novelty, double hopSec, double coarseBpm) {
  final duration = novelty.length * hopSec;
  double at(double t) {
    final x = t / hopSec;
    final i = x.floor();
    if (i < 0 || i + 1 >= novelty.length) return 0;
    final f = x - i;
    return novelty[i] * (1 - f) + novelty[i + 1] * f;
  }

  var bestBpm = coarseBpm;
  var bestShift = 0.0;
  var best = -1.0;
  for (var bpm = coarseBpm - 1.5; bpm <= coarseBpm + 1.5001; bpm += 0.05) {
    final beatSec = 60 / bpm;
    const phases = 32;
    for (var s = 0; s < phases; s++) {
      final shift = beatSec * s / phases;
      var sum = 0.0;
      var n = 0;
      for (var t = shift; t < duration; t += beatSec) {
        sum += at(t);
        n++;
      }
      final score = n == 0 ? 0.0 : sum / n;
      if (score > best) {
        best = score;
        bestBpm = bpm;
        bestShift = shift;
      }
    }
  }
  return (bpm: double.parse(bestBpm.toStringAsFixed(2)), offsetSec: bestShift);
}
