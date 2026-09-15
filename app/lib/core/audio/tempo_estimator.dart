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

  const TempoEstimate({
    required this.bpm,
    required this.agreeingIntervals,
    required this.totalIntervals,
  });

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
