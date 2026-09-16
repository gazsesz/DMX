import 'dart:math' as math;

/// The rolling "what counts as normal in this room" that an onset has to
/// stand out from: an exponential moving mean and variance of the onset
/// strength, so the beat threshold is `mean + k·stddev` — a statistical
/// outlier test that stays calibrated to however loud and eventful the
/// music actually is.
///
/// What it deliberately does *not* learn from is an outlier's full size.
/// A finger on the microphone produces an onset hundreds of times anything
/// in the music, and squaring that into a variance moves the bar up by
/// orders of magnitude in a handful of frames — which the memory then holds
/// for as long as its time constant says. With the baseline memory set to
/// Off (a 30-second memory) a couple of seconds of tapping put the
/// threshold above every real beat for *minutes*: the rig sat in "waiting
/// for music" with the music plainly playing.
///
/// So each frame is winsorised before it's learned from — anything above
/// [clipSigmas] deviations teaches the baseline as if it had landed exactly
/// there. The beat itself is still detected on the raw value; it just
/// doesn't get to redefine normal.
class OnsetBaseline {
  /// How far above the mean a single frame may push the baseline.
  ///
  /// Well clear of where beats live (the detector fires somewhere between
  /// 2.5 and 9 deviations depending on the sensitivity slider), so ordinary
  /// music teaches the baseline exactly as it did before; low enough that a
  /// mic tap is cut down from a few hundred deviations to six.
  static const clipSigmas = 6.0;

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
    // time constant: on Off that's the first ~12ms of audio setting the
    // bar for half a minute, and if the microphone opened on a loud frame,
    // half a minute of hearing no beats at all.
    final effective = math.max(alpha, 1 / _samples);

    final mean = _mean;
    if (mean == null) {
      _mean = flux;
      _variance = 0;
      return;
    }

    // The floor keeps the cap from collapsing onto the mean when the
    // variance is near zero (a dead-steady passage): without it the
    // baseline could never climb again, and the threshold would sit at the
    // mean with everything above it counting as a beat.
    final cap = mean + math.max(clipSigmas * stddev, mean.abs());
    final value = math.min(flux, cap);

    final delta = value - mean;
    final newMean = mean + effective * delta;
    _mean = newMean;
    final delta2 = value - newMean;
    _variance = (1 - effective) * (_variance + effective * delta * delta2);
  }
}
