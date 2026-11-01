import 'dart:math' as math;

import 'package:dmx_controller/core/audio/onset_baseline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hopMs = 512 / 44100 * 1000;
  final rng = math.Random(1);

  /// Feeds [seconds] of onsets: a hit of [strength] every [periodMs] (a
  /// kick, or a key click), and returns how many of them the gate let in.
  int feed(MusicLevelGate gate, double seconds, double strength, {double periodMs = 469, double jitter = 0}) {
    var passed = 0;
    var next = 0.0;
    final frames = (seconds * 1000 / hopMs).round();
    for (var i = 0; i < frames; i++) {
      gate.tick(hopMs);
      final t = i * hopMs;
      if (t >= next) {
        next = t + periodMs * (1 + jitter * (rng.nextDouble() - 0.5));
        final hit = strength * (0.8 + 0.4 * rng.nextDouble());
        if (gate.allows(hit)) {
          gate.onBeat(hit);
          passed++;
        }
      }
    }
    return passed;
  }

  test('before any music, everything passes', () {
    final gate = MusicLevelGate();
    expect(gate.allows(0.0001), isTrue);
    expect(feed(gate, 20, 0.01, periodMs: 200, jitter: 1), greaterThan(80));
  });

  test('keyboard clicks after the music stops do not pass', () {
    final gate = MusicLevelGate();
    expect(feed(gate, 60, 1.0), greaterThan(120), reason: 'every kick of the set counts');
    // Half an hour of typing at -30 dB of the kicks.
    expect(feed(gate, 1800, 0.03, periodMs: 180, jitter: 1), 0);
  });

  test('a softer track and a breakdown after a loud one still pass', () {
    final gate = MusicLevelGate();
    feed(gate, 60, 1.0);
    expect(feed(gate, 30, 0.1, periodMs: 545), 55, reason: '-20 dB: every hit');
    final next = feed(gate, 60, 0.5, periodMs: 545);
    expect(next, 110);
  });

  test('a clap next to the microphone does not lift the bar over the music', () {
    final gate = MusicLevelGate();
    feed(gate, 30, 1.0);
    gate.onBeat(200);
    gate.onBeat(200);
    expect(gate.reference, lessThan(2));
    expect(feed(gate, 30, 1.0), greaterThan(60));
  });

  test('starting over forgets the reference', () {
    final gate = MusicLevelGate();
    feed(gate, 30, 1.0);
    gate.reset();
    expect(feed(gate, 20, 0.03, periodMs: 180, jitter: 1), greaterThan(80));
  });
}
