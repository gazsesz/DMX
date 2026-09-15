import 'package:dmx_controller/core/audio/tempo_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

/// The estimator exists because averaging beat gaps put a live gig
/// permanently in the "slower" zone: every missed beat contributes a gap of
/// twice the real one, and the mean drags the tempo down with it.
void main() {
  /// Beat times for [count] beats at [bpm], optionally dropping the beats
  /// at [drop] (indices into the run) to simulate missed detections.
  List<DateTime> beatsAt(double bpm, int count, {Set<int> drop = const {}, List<int> jitterMs = const []}) {
    final start = DateTime(2026, 1, 1);
    final periodMs = 60000 / bpm;
    return [
      for (var i = 0; i < count; i++)
        if (!drop.contains(i))
          start.add(Duration(
            microseconds: ((i * periodMs + (i < jitterMs.length ? jitterMs[i] : 0)) * 1000).round(),
          )),
    ];
  }

  test('a clean run reads its own tempo back', () {
    for (final bpm in [60.0, 100.0, 128.0, 174.0]) {
      final estimate = estimateTempo(beatsAt(bpm, 10));
      expect(estimate, isNotNull, reason: '$bpm');
      expect(estimate!.bpm, closeTo(bpm, 0.5), reason: '$bpm');
      expect(estimate.isConfident, isTrue);
    }
  });

  test('a missed beat does not drag the tempo down', () {
    // This is the gig failure, reproduced: 128 BPM with three of twelve
    // beats missed. Averaging the raw gaps gives about 100 BPM, which a
    // Smart Program reads as a slow song.
    final withGaps = beatsAt(128, 12, drop: {3, 7, 9});
    final naiveMean = _naiveBpm(withGaps);
    expect(naiveMean, lessThan(115), reason: 'the old approach really did break');

    final estimate = estimateTempo(withGaps);
    expect(estimate, isNotNull);
    expect(estimate!.bpm, closeTo(128, 2));
  });

  test('two beats missed in a row still folds back', () {
    final estimate = estimateTempo(beatsAt(120, 12, drop: {4, 5}));
    expect(estimate!.bpm, closeTo(120, 2));
  });

  test('a spurious extra beat between two real ones is folded, not averaged', () {
    final times = beatsAt(120, 9).toList();
    // A double trigger half a beat after the fourth.
    times.insert(5, times[4].add(const Duration(milliseconds: 250)));
    final estimate = estimateTempo(times);
    expect(estimate!.bpm, closeTo(120, 3));
  });

  test('human timing jitter is tolerated', () {
    final estimate = estimateTempo(beatsAt(128, 10, jitterMs: [0, 12, -9, 15, -14, 6, -7, 11, -12, 8]));
    expect(estimate!.bpm, closeTo(128, 4));
  });

  test('random taps produce no confident answer', () {
    final start = DateTime(2026, 1, 1);
    final chaotic = [
      start,
      start.add(const Duration(milliseconds: 137)),
      start.add(const Duration(milliseconds: 902)),
      start.add(const Duration(milliseconds: 1010)),
      start.add(const Duration(milliseconds: 2500)),
      start.add(const Duration(milliseconds: 2600)),
    ];
    final estimate = estimateTempo(chaotic);
    // It may well return something; what matters is that it doesn't claim
    // to be sure, because the Smart Program only acts on confident reads.
    if (estimate != null) expect(estimate.isConfident, isFalse);
  });

  test('an octave error is pulled back into the plausible range', () {
    // Detector firing on every eighth note of a 128 BPM track.
    final estimate = estimateTempo(beatsAt(256, 10));
    expect(estimate!.bpm, closeTo(128, 1));
    // ...and one catching only every other beat of a 160 BPM track.
    final halved = estimateTempo(beatsAt(35, 10));
    expect(halved!.bpm, closeTo(70, 1));
  });

  test('fewer than three beats says nothing', () {
    expect(estimateTempo([]), isNull);
    expect(estimateTempo(beatsAt(120, 2)), isNull);
  });
}

/// What the code used to do: mean of the raw gaps.
double _naiveBpm(List<DateTime> times) {
  final gaps = [
    for (var i = 1; i < times.length; i++) times[i].difference(times[i - 1]).inMilliseconds,
  ];
  return 60000 / (gaps.reduce((a, b) => a + b) / gaps.length);
}
