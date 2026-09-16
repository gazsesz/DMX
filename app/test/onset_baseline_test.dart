import 'dart:math' as math;

import 'package:dmx_controller/core/audio/beat_detector.dart';
import 'package:dmx_controller/core/audio/onset_baseline.dart';
import 'package:flutter_test/flutter_test.dart';

/// The detector's baseline, driven with a synthetic onset-strength stream
/// instead of a microphone.
///
/// The case that matters is the one from the floor: baseline memory on Off
/// (a 30-second memory), music playing, and someone taps the microphone to
/// push the tempo up. The tap is hundreds of times anything in the music,
/// and a variance that learns from it squared used to put the threshold
/// above every real beat for minutes afterwards — "waiting for music" with
/// the music playing.
void main() {
  // The detector's own frame rate: a 512-sample hop at 44.1kHz.
  const hopMs = 512 / 44100 * 1000;
  const framesPerSecond = 1000 / hopMs; // ~86

  // What the service uses at the default sensitivity of 0.6.
  const k = 3.5;
  const refractoryFrames = 250 / hopMs;

  double alphaFor(BeatAdaptSpeed speed) => 1 - math.exp(-hopMs / speed.tauMs);

  /// Runs [frames] of onset strength through a baseline, returning the
  /// frame indices that would have fired a beat.
  List<int> beatsIn(
    List<double> frames, {
    required OnsetBaseline baseline,
    required double alpha,
    int from = 0,
  }) {
    final beats = <int>[];
    double? lastBeat;
    for (var i = 0; i < frames.length; i++) {
      final flux = frames[i];
      baseline.learn(flux, alpha);
      final threshold = baseline.thresholdAt(k);
      final clear = lastBeat == null || i - lastBeat > refractoryFrames;
      if (flux > threshold && clear && i >= from) {
        beats.add(i);
        lastBeat = i.toDouble();
      } else if (flux > threshold && clear) {
        lastBeat = i.toDouble();
      }
    }
    return beats;
  }

  /// Steady music: a quiet, slightly restless background with a firm onset
  /// every half second, i.e. 120 BPM.
  List<double> music(double seconds, {double startAt = 0}) {
    final frames = <double>[];
    final total = (seconds * framesPerSecond).round();
    final beatEvery = (framesPerSecond / 2).round();
    final offset = (startAt * framesPerSecond).round();
    for (var i = 0; i < total; i++) {
      final n = i + offset;
      // Deterministic jitter, so the baseline has something to measure.
      final background = 1.0 + 0.35 * math.sin(n * 0.7) + 0.2 * math.sin(n * 0.13);
      frames.add(n % beatEvery == 0 ? background + 18 : background);
    }
    return frames;
  }

  /// Someone drumming a finger on the microphone: brief, and hundreds of
  /// times the size of anything musical.
  List<double> tapping(double seconds) {
    final frames = <double>[];
    final total = (seconds * framesPerSecond).round();
    final tapEvery = (framesPerSecond / 4).round(); // ~4 taps a second
    for (var i = 0; i < total; i++) {
      final intoTap = i % tapEvery;
      frames.add(intoTap < 3 ? 900.0 : 1.2);
    }
    return frames;
  }

  test('steady music is detected at about its real tempo', () {
    final baseline = OnsetBaseline();
    final alpha = alphaFor(BeatAdaptSpeed.off);
    final frames = music(20);
    // Ignore the first couple of seconds: the baseline starts at the first
    // frame it sees and needs a moment either way.
    final beats = beatsIn(frames, baseline: baseline, alpha: alpha, from: (framesPerSecond * 3).round());

    final seconds = 17;
    expect(beats.length, greaterThan(seconds * 2 - 4));
    expect(beats.length, lessThan(seconds * 2 + 4));
  });

  test('a tap on the mic does not deafen the detector afterwards', () {
    final baseline = OnsetBaseline();
    final alpha = alphaFor(BeatAdaptSpeed.off);

    // Music, then two seconds of tapping over it, then music again.
    final before = music(10);
    final taps = tapping(2);
    final after = music(20, startAt: 12);
    final frames = [...before, ...taps, ...after];

    final resumesAt = before.length + taps.length + (framesPerSecond * 3).round();
    final beats = beatsIn(frames, baseline: baseline, alpha: alpha, from: resumesAt);

    // 17 seconds of music at 120 BPM once the tapping stops. Before the
    // baseline clipped outliers this was zero for minutes.
    expect(beats.length, greaterThan(30), reason: 'the detector went deaf after the tapping');
  });

  test('the baseline recovers within a couple of seconds, not minutes', () {
    final baseline = OnsetBaseline();
    final alpha = alphaFor(BeatAdaptSpeed.off);

    final before = music(10);
    final taps = tapping(2);
    final frames = [...before, ...taps, ...music(20, startAt: 12)];
    beatsIn(frames.sublist(0, before.length + taps.length), baseline: baseline, alpha: alpha);
    final afterTapping = baseline.thresholdAt(k);

    // Feed two more seconds of music and see where the bar sits.
    final settled = OnsetBaseline();
    beatsIn(music(12), baseline: settled, alpha: alpha);

    // Within spitting distance of an undisturbed baseline — the point being
    // that a real beat (about 18 above the background) still clears it.
    expect(afterTapping, lessThan(settled.thresholdAt(k) * 3));
    expect(afterTapping, lessThan(18));
  });

  test('a frame is learned from at most six deviations above the mean', () {
    final baseline = OnsetBaseline();
    for (var i = 0; i < 500; i++) {
      baseline.learn(1.0 + 0.3 * math.sin(i.toDouble()), 0.05);
    }
    final before = baseline.stddev;

    baseline.learn(10000, 0.05);
    // Without clipping this single frame would multiply the variance by
    // thousands; clipped, it can't move the deviation by more than the
    // frame's own weight.
    expect(baseline.stddev, lessThan(before * 3));
  });

  test('a dead-steady passage can still let the baseline climb again', () {
    final baseline = OnsetBaseline();
    // No variance at all: the clip cap has to fall back to something other
    // than the mean, or the baseline could never follow the music up.
    for (var i = 0; i < 200; i++) {
      baseline.learn(1.0, 0.05);
    }
    expect(baseline.stddev, lessThan(0.001));

    for (var i = 0; i < 400; i++) {
      baseline.learn(8.0, 0.05);
    }
    expect(baseline.mean, greaterThan(4));
  });
}
