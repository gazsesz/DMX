/// Turns a run of beat timestamps into a tempo.
///
/// The naive version — average the gaps — is what put the first live gig
/// permanently in the "slower" zone. Onset detection misses a beat here and
/// there in a dense mix, and every missed beat contributes a gap of *twice*
/// the real one. Averaging those in drags the reported tempo down hard: a
/// single miss in eight beats already costs about 12%, and a handful puts a
/// 128 BPM track below 100, where a Smart Program reads it as a slow song
/// and stays there.
///
/// So instead: take the median gap, which a few outliers can't move, then
/// fold each gap back onto it. A gap close to twice the median is one
/// missed beat, not a slow passage; a gap close to half is a double
/// trigger. Both are corrected rather than averaged in, and anything that
/// doesn't fit either story is dropped.
library;

/// Estimated tempo, or null when there isn't enough to say.
class TempoEstimate {
  final double bpm;

  /// How many of the gaps agreed with the median once folded — a rough
  /// confidence, useful for deciding whether to trust the number.
  final int agreeingIntervals;
  final int totalIntervals;

  /// The tempo the beats themselves keep, before [bpm] was pulled back into
  /// the plausible range by octaves — what a grid laid over those very
  /// beats has to use. Same as [bpm] unless that correction happened.
  final double pulseBpm;

  const TempoEstimate({
    required this.bpm,
    required this.agreeingIntervals,
    required this.totalIntervals,
    double? pulseBpm,
  }) : pulseBpm = pulseBpm ?? bpm;

  /// Most gaps told the same story.
  bool get isConfident => totalIntervals > 0 && agreeingIntervals / totalIntervals >= 0.6;
}

/// How far a gap may sit from its folded target and still count. A live
/// drummer (or a detector's timing jitter) moves by a few percent; 25%
/// tolerates that without letting a genuinely different tempo through.
const _tolerance = 0.25;

/// The largest miss we'll try to fold back — beyond four consecutive missed
/// beats, guessing does more harm than admitting we lost the thread.
const _maxFold = 4;

/// Estimates tempo from consecutive beat times.
///
/// Returns null with fewer than three beats, or if nothing agrees.
TempoEstimate? estimateTempo(List<DateTime> beatTimes, {double minBpm = 40, double maxBpm = 220}) {
  if (beatTimes.length < 3) return null;

  final gaps = <double>[];
  for (var i = 1; i < beatTimes.length; i++) {
    final ms = beatTimes[i].difference(beatTimes[i - 1]).inMicroseconds / 1000;
    if (ms > 0) gaps.add(ms);
  }
  if (gaps.length < 2) return null;

  final sorted = [...gaps]..sort();
  final median = sorted.length.isOdd
      ? sorted[sorted.length ~/ 2]
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
  if (median <= 0) return null;

  final folded = <double>[];
  for (final gap in gaps) {
    final candidate = _fold(gap, median);
    if (candidate != null) folded.add(candidate);
  }
  if (folded.isEmpty) return null;

  final meanMs = folded.reduce((a, b) => a + b) / folded.length;
  if (meanMs <= 0) return null;
  var bpm = 60000 / meanMs;
  final pulseBpm = bpm;

  // Pull an octave error back into the plausible range. A detector that
  // fires on every eighth note reports 256 BPM for a 128 BPM track; one
  // that catches every other beat reports 64.
  while (bpm > maxBpm) {
    bpm /= 2;
  }
  while (bpm < minBpm) {
    bpm *= 2;
  }

  return TempoEstimate(
    bpm: bpm,
    agreeingIntervals: folded.length,
    totalIntervals: gaps.length,
    pulseBpm: pulseBpm,
  );
}

/// Maps [gap] onto the beat [median] describes, or null if it fits no
/// sensible multiple or division of it.
double? _fold(double gap, double median) {
  // A gap that *is* the beat, or n beats' worth because n-1 were missed.
  for (var n = 1; n <= _maxFold; n++) {
    final target = median * n;
    if ((gap - target).abs() <= target * _tolerance) return gap / n;
  }
  // Or a fraction of it, from a double trigger between two real beats.
  for (var n = 2; n <= _maxFold; n++) {
    final target = median / n;
    if ((gap - target).abs() <= target * _tolerance) return gap * n;
  }
  return null;
}

/// How much of [beatTimes] sits on one steady grid of about [bpm] — 0..1.
///
/// [estimateTempo]'s folding is generous on purpose (a missed beat or a
/// double trigger is folded back in rather than averaged), and that same
/// generosity makes it agree with almost anything: random onsets — a quiet
/// room's noise floor, people talking, a glass put down — fold onto *some*
/// multiple of their own median nearly every time, so a run of them reads
/// as "confident" about nine times in ten. This asks the question folding
/// can't: do the beats actually line up, one after another, on a single
/// pulse? A grid of the estimated period (searched ±5% around it, since the
/// folded mean is skewed by any extra hits) is anchored on each beat in
/// turn, and the best share of beats within ±10% of a period of a grid line
/// wins. Missed beats cost nothing here (an empty grid slot is fine); only
/// hits that land off the pulse do.
double pulseRegularity(List<DateTime> beatTimes, double bpm) {
  if (beatTimes.length < 2 || bpm <= 0) return 0;
  final first = beatTimes.first;
  final ms = [for (final t in beatTimes) t.difference(first).inMicroseconds / 1000];
  var best = 0;
  for (var k = -10; k <= 10; k++) {
    final period = 60000 / (bpm * (1 + k * 0.005));
    for (final anchor in ms) {
      var hits = 0;
      for (final t in ms) {
        var phase = ((t - anchor) / period) % 1.0;
        if (phase < 0) phase += 1;
        if (phase <= _gridTolerance || phase >= 1 - _gridTolerance) hits++;
      }
      if (hits > best) best = hits;
    }
  }
  return best / ms.length;
}

const _gridTolerance = 0.1;

/// The fewest beats [isSteadyPulse] will judge — fewer than this and even
/// random hits line up often enough to fool it.
const steadyPulseMinBeats = 6;

/// The share of beats that must sit on one grid — tuned on simulated beat
/// streams: random onsets at 1–4 a second pass about 1 window in 50, while
/// a real track with 30% of its kicks missed and 15% stray hits still
/// passes four times in five.
const steadyPulseRegularity = 0.75;

/// The fastest pulse [isSteadyPulse] believes. The detector won't fire
/// twice within 250 ms, so dense noise — typing, chatter, a busy hi-hat
/// line the detector can't keep up with — comes out as a run of hits about
/// that far apart: regular, but only because of the cap. No kick drum
/// a Smart Program follows sits up there (drum & bass is ~174).
const steadyPulseMaxBpm = 190.0;

/// Whether [beatTimes] is a real, steady pulse rather than a confident-
/// looking pile of random onsets — see [pulseRegularity].
bool isSteadyPulse(List<DateTime> beatTimes, TempoEstimate? estimate) {
  if (estimate == null || !estimate.isConfident) return false;
  if (beatTimes.length < steadyPulseMinBeats) return false;
  if (estimate.pulseBpm > steadyPulseMaxBpm) return false;
  return pulseRegularity(beatTimes, estimate.pulseBpm) >= steadyPulseRegularity;
}
