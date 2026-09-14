import 'package:dmx_controller/core/widgets/log_scale.dart';
import 'package:flutter_test/flutter_test.dart';

/// The timing sliders are the controls used most during a show, and the
/// mapping between thumb position and value is the whole reason they got
/// rescaled — a regression here is invisible in a screenshot and obvious
/// on stage.
void main() {
  test('a position round-trips back to the same value', () {
    for (final value in [0.05, 0.2, 0.5, 1.0, 2.5, 5.0]) {
      expect(
        stepSpeedScale.valueAt(stepSpeedScale.positionOf(value)),
        closeTo(value, 1e-9),
        reason: 'step $value',
      );
      expect(
        fadeTimeScale.valueAt(fadeTimeScale.positionOf(value)),
        closeTo(value, 1e-9),
        reason: 'fade $value',
      );
    }
  });

  test('step speed runs backwards — pushing the slider up speeds it up', () {
    expect(stepSpeedScale.valueAt(0), closeTo(stepSpeedScale.max, 1e-9));
    expect(stepSpeedScale.valueAt(1), closeTo(stepSpeedScale.min, 1e-9));
    expect(stepSpeedScale.valueAt(0.75), lessThan(stepSpeedScale.valueAt(0.25)));
  });

  test('fade runs forwards, from a snap to five seconds', () {
    expect(fadeTimeScale.valueAt(0), closeTo(fadeTimeScale.min, 1e-9));
    expect(fadeTimeScale.valueAt(1), closeTo(fadeTimeScale.max, 1e-9));
    expect(fadeTimeScale.valueAt(0.75), greaterThan(fadeTimeScale.valueAt(0.25)));
  });

  test('the short fades get real travel, which a linear slider denied them', () {
    // On the old linear 0-5s slider everything under half a second lived in
    // the first 10% of the thumb. Log spacing has to do better than that.
    final halfSecond = fadeTimeScale.positionOf(0.5);
    expect(halfSecond, greaterThan(0.5), reason: 'half a second should sit past the midpoint');
    // Each doubling gets the same amount of travel, by construction.
    final quarterToHalf = fadeTimeScale.positionOf(0.5) - fadeTimeScale.positionOf(0.25);
    final oneToTwo = fadeTimeScale.positionOf(2.0) - fadeTimeScale.positionOf(1.0);
    expect(quarterToHalf, closeTo(oneToTwo, 1e-9));
  });

  test('values outside the range clamp instead of running off the slider', () {
    expect(fadeTimeScale.positionOf(0), 0);
    expect(fadeTimeScale.positionOf(99), 1);
    expect(stepSpeedScale.positionOf(0), 1, reason: 'faster than the fastest pins to the top');
    expect(stepSpeedScale.positionOf(99), 0);
    expect(fadeTimeScale.valueAt(-1), closeTo(fadeTimeScale.min, 1e-9));
    expect(fadeTimeScale.valueAt(2), closeTo(fadeTimeScale.max, 1e-9));
  });
}
