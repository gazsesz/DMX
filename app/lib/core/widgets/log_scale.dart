import 'dart:math' as math;

/// Maps a slider's 0..1 travel onto a value spaced logarithmically.
///
/// Timing controls need this. On a linear 0-5s fade slider the whole useful
/// range — snap, 0.1s, 0.3s, half a second — lives in the first tenth of
/// the travel, so the settings you actually reach for are the ones you
/// can't hit; everything past 2s is padding you never use. Spacing the
/// values by ratio instead gives every octave the same amount of thumb.
class LogScale {
  /// Value at position 0 (or at position 1 when [inverted]).
  final double min;

  /// Value at position 1 (or at position 0 when [inverted]).
  final double max;

  /// Runs the scale backwards, so pushing the slider up gets a *smaller*
  /// value. Step speed wants this: "up" should mean faster, and faster
  /// means fewer seconds per step.
  final bool inverted;

  const LogScale({required this.min, required this.max, this.inverted = false});

  double valueAt(double position) {
    final travel = position.clamp(0.0, 1.0);
    final fraction = inverted ? 1 - travel : travel;
    return math.exp(math.log(min) + (math.log(max) - math.log(min)) * fraction);
  }

  double positionOf(double value) {
    final clamped = value.clamp(min, max);
    final fraction = (math.log(clamped) - math.log(min)) / (math.log(max) - math.log(min));
    return inverted ? 1 - fraction : fraction;
  }
}

/// Step Speed: position 1 is the *fastest* step. The bottom of the range is
/// a 20 ms step (strobe territory) and the top is a five-second hold.
const stepSpeedScale = LogScale(min: 0.02, max: 5.0, inverted: true);

/// Fade Time. 10 ms is a snap for anything on a stage, so the scale simply
/// bottoms out there rather than carrying a special "zero" position.
const fadeTimeScale = LogScale(min: 0.01, max: 5.0);
