import 'dart:math' as math;

/// The rolling "what counts as normal in this room" that an onset has to
/// stand out from: an exponential moving mean and variance of the onset
/// strength, so the beat threshold is `mean + k·stddev` — a statistical
/// outlier test that stays calibrated to however loud and eventful the
/// music actually is.
///
/// The statistics are deliberately plain. Winsorising the frames on the way
/// in (clipping each one to a few deviations, so a mic tap couldn't poison
/// the variance) was tried and measured: it cut the variance in exactly the
/// material where the beats *are* the variance, dropping the bar under the
/// room's own clatter. In a synthetic noisy room it took false beats from 8
/// to 36 per 17 seconds and left the sensitivity slider with nothing to
/// work with. The outlier problem is handled by [shouldForgetBaseline]
/// instead, which changes nothing while beats are arriving.
class OnsetBaseline {
  double? _mean;
  double _variance = 0;
  int _samples = 0;

  /// Null until the first frame — there's no such thing as a baseline from
  /// no audio.
  double? get mean => _mean;

  double get stddev => math.sqrt(_variance);

  /// What an onset has to beat right now, at [k] deviations.
  double thresholdAt(double k) {
    final mean = _mean;
    return mean == null ? 0 : mean + k * stddev;
  }

  void reset() {
    _mean = null;
    _variance = 0;
    _samples = 0;
  }

  /// Folds one frame's onset strength in, [alpha] being how much of it to
  /// take (derived from the chosen memory length).
  void learn(double flux, double alpha) {
    _samples++;
    // Until the memory is actually full, weigh each frame as 1/n — the
    // plain average of everything heard so far. An exponential average
    // starts at whatever its first frame was and carries it for a whole
    // time constant: on the 30-second memory that's the first ~12ms of
    // audio setting the bar for half a minute, and if the microphone
    // happened to open on a loud frame, half a minute of hearing nothing.
    final effective = math.max(alpha, 1 / _samples);

    final mean = _mean;
    if (mean == null) {
      _mean = flux;
      _variance = 0;
      return;
    }

    final delta = flux - mean;
    final newMean = mean + effective * delta;
    _mean = newMean;
    final delta2 = flux - newMean;
    _variance = (1 - effective) * (_variance + effective * delta * delta2);
  }
}

/// How long the bar may go uncrossed before a long memory gives up on what
/// it has learned. Slower than any danceable tempo by a wide margin.
const forgetAfterSeconds = 8.0;

/// Only memories longer than this get the escape hatch below.
const forgetMinimumMemoryMs = 10000.0;

/// Whether the baseline has been left somewhere nothing can reach and
/// should be thrown away and learned again.
///
/// Something that isn't music — a hand clap next to the tablet, a finger on
/// the microphone — is hundreds of deviations above anything musical, and a
/// variance squares that. The short memories shake it off by themselves in
/// a few seconds. The 30-second one does not: driven with a synthetic tap
/// burst it stayed above every real beat for minutes, which is what "waiting
/// for music" with the music playing looks like.
///
/// [fastLevel] is a ~300ms level and [mean] the baseline's own: requiring
/// the room to still be roughly as loud as the baseline says is what keeps
/// this from firing when the music simply stopped — there the fast level
/// collapses and the bar is allowed to stay where it is, so a break between
/// songs reads as a break rather than as a detector to reset.
///
/// Nothing here fires while beats are arriving, so a deliberately
/// insensitive setting is left alone.
bool shouldForgetBaseline({
  required double memoryMs,
  required double secondsSinceBeat,
  required double fastLevel,
  required double? mean,
}) {
  if (memoryMs <= forgetMinimumMemoryMs) return false;
  if (mean == null || mean <= 0) return false;
  if (secondsSinceBeat < forgetAfterSeconds) return false;
  return fastLevel > mean * 0.5;
}
