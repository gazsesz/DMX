import 'dart:math' as math;

import 'package:dmx_controller/core/audio/beat_detector.dart';
import 'package:dmx_controller/core/audio/onset_baseline.dart';
import 'package:flutter_test/flutter_test.dart';

/// The detector's baseline, driven with a synthetic onset-strength stream
/// instead of a microphone.
///
/// Two things are being pinned down here. One: the statistics themselves
/// stay plain, because an earlier attempt to make them outlier-proof by
/// clipping each frame cut the variance in exactly the material where the
/// beats *are* the variance, and the room's own clatter started counting as
/// beats. Two: the 30-second memory can't be left deaf by something that
/// isn't music — that's what [shouldForgetBaseline] is for.
void main() {
  const hopMs = 512 / 44100 * 1000;
  const fps = 1000 / hopMs; // ~86 frames a second

  // What the service uses at the default sensitivity of 0.6.
  const k = 3.5;
  const refractoryFrames = 250 / hopMs;

  double alphaFor(BeatAdaptSpeed speed) => 1 - math.exp(-hopMs / speed.tauMs);

  /// Real-shaped material: a kick about a hundred times the background, a
  /// room that clatters now and then.
  List<double> music(int seconds, {int offset = 0, bool beats = true}) {
    final out = <double>[];
    final beatEvery = (fps / 2).round(); // 120 BPM
    for (var i = 0; i < seconds * fps.round(); i++) {
      final n = i + offset;
      final background =
          1.0 + 0.4 * math.sin(n * 0.7).abs() + (n % 37 == 0 ? 2.0 : 0) + (n % 211 == 0 ? 7.0 : 0);
      final into = n % beatEvery;
      final beat = !beats ? 0.0 : (into == 0 ? 120.0 : (into == 1 ? 40.0 : 0.0));
      out.add(background + beat);
    }
    return out;
  }

  /// A finger drumming on the microphone: brief, and hundreds of times the
  /// size of anything musical.
  List<double> tapping(int seconds) {
    final out = <double>[];
    final every = (fps / 4).round();
    for (var i = 0; i < seconds * fps.round(); i++) {
      out.add(i % every < 3 ? 900.0 : 1.2);
    }
    return out;
  }

  /// Runs frames through a baseline the way the service does, escape hatch
  /// included, and returns the frame indices that fired a beat.
  List<int> beatsIn(
    List<double> frames, {
    required OnsetBaseline baseline,
    required BeatAdaptSpeed speed,
    double sensitivity = k,
    int from = 0,
  }) {
    final alpha = alphaFor(speed);
    final fastAlpha = 1 - math.exp(-hopMs / 300);
    final beats = <int>[];
    var fast = 0.0;
    var sinceBeat = 0;
    var framesSinceReset = 0;
    for (var i = 0; i < frames.length; i++) {
      final flux = frames[i];
      fast += fastAlpha * (flux - fast);
      sinceBeat++;
      framesSinceReset++;

      if (shouldForgetBaseline(
        memoryMs: speed.tauMs,
        secondsSinceBeat: sinceBeat / fps,
        fastLevel: fast,
        mean: baseline.mean,
      )) {
        baseline.reset();
        framesSinceReset = 0;
        sinceBeat = 0;
      }

      baseline.learn(flux, alpha);
      // The service holds beats back for the first 600ms, here and after a
      // reset, while the statistics form.
      if (framesSinceReset * hopMs < 600) continue;

      final clear = beats.isEmpty || i - beats.last > refractoryFrames;
      if (flux > baseline.thresholdAt(sensitivity) && clear) {
        sinceBeat = 0;
        if (i >= from) beats.add(i);
      }
    }
    return beats;
  }

  final settled = (fps * 3).round();

  test('steady music is detected at its real tempo', () {
    for (final speed in BeatAdaptSpeed.values) {
      final beats = beatsIn(
        music(20),
        baseline: OnsetBaseline(),
        speed: speed,
        from: settled,
      );
      // 17 seconds at 120 BPM.
      expect(beats.length, inInclusiveRange(32, 36), reason: 'at ${speed.label}');
    }
  });

  test('the sensitivity setting still decides what counts', () {
    // A room with no music in it: turning the slider down has to quieten it
    // down. This is what clipping the frames broke.
    final loose = beatsIn(
      music(20, beats: false),
      baseline: OnsetBaseline(),
      speed: BeatAdaptSpeed.off,
      sensitivity: 2.5,
      from: settled,
    );
    final tight = beatsIn(
      music(20, beats: false),
      baseline: OnsetBaseline(),
      speed: BeatAdaptSpeed.off,
      sensitivity: 9,
      from: settled,
    );
    expect(tight.length, lessThan(loose.length ~/ 2));

    // And at the default setting the room's own clatter is mostly ignored.
    // Clipping the frames put this at 36 in 17 seconds where the plain
    // statistics give 8 — which is what "it counts noise as beats" looked
    // like on the tablet.
    final normal = beatsIn(
      music(20, beats: false),
      baseline: OnsetBaseline(),
      speed: BeatAdaptSpeed.off,
      from: settled,
    );
    expect(normal.length, lessThan(15));
  });

  test('a tap on the mic does not leave the long memory deaf', () {
    final baseline = OnsetBaseline();
    final frames = [...music(10), ...tapping(2), ...music(20, offset: 12 * fps.round())];
    final resumes = (12 * fps).round();

    final beats = beatsIn(frames, baseline: baseline, speed: BeatAdaptSpeed.off, from: resumes);

    // Back within a handful of seconds. Before the escape hatch this was
    // nothing at all for minutes.
    expect(beats, isNotEmpty, reason: 'still deaf after the tapping');
    final backAfter = (beats.first - resumes) / fps;
    expect(backAfter, lessThan(12));
  });

  test('a short memory shakes a tap off by itself, and is left alone', () {
    // Nothing should forget here — the memory is short enough to recover on
    // its own, so the escape hatch stays out of it.
    expect(
      shouldForgetBaseline(
        memoryMs: BeatAdaptSpeed.normal.tauMs,
        secondsSinceBeat: 30,
        fastLevel: 10,
        mean: 10,
      ),
      isFalse,
    );
  });

  test('a room that has gone quiet is a break, not a detector to reset', () {
    // The music stopped: the fast level collapses well under the baseline,
    // and the bar is left where it is rather than dropped onto the noise.
    expect(
      shouldForgetBaseline(
        memoryMs: BeatAdaptSpeed.off.tauMs,
        secondsSinceBeat: 30,
        fastLevel: 0.1,
        mean: 10,
      ),
      isFalse,
    );
    expect(
      shouldForgetBaseline(
        memoryMs: BeatAdaptSpeed.off.tauMs,
        secondsSinceBeat: 30,
        fastLevel: 9,
        mean: 10,
      ),
      isTrue,
    );
  });

  test('nothing is forgotten while beats are arriving', () {
    expect(
      shouldForgetBaseline(
        memoryMs: BeatAdaptSpeed.off.tauMs,
        secondsSinceBeat: 2,
        fastLevel: 10,
        mean: 10,
      ),
      isFalse,
    );
  });

  test('opening the mic on a loud frame does not blind it for the memory', () {
    // The first frame is a beat. Weighing early frames as 1/n is what stops
    // that one frame from setting the bar for the next thirty seconds.
    final baseline = OnsetBaseline();
    final frames = music(20);
    expect(frames.first, greaterThan(100));

    final beats = beatsIn(frames, baseline: baseline, speed: BeatAdaptSpeed.off, from: settled);
    expect(beats.length, inInclusiveRange(32, 36));
  });
}
