import 'dart:async';

import 'package:dmx_controller/core/audio/beat_predictor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<DateTime> source;
  late BeatPredictor predictor;
  late List<DateTime> received;
  late StreamSubscription<DateTime> sub;

  // Comfortably inside estimateTempo's 40-220 BPM window, so nothing here
  // gets octave-corrected into a different period than the one under test.
  const period = Duration(milliseconds: 500);

  setUp(() {
    source = StreamController<DateTime>.broadcast();
    predictor = BeatPredictor(source.stream);
    received = [];
    sub = predictor.events.listen(received.add);
  });

  tearDown(() async {
    await sub.cancel();
    predictor.dispose();
    await source.close();
  });

  /// Three evenly spaced beats ending [endOffset] before now — far enough in
  /// the past that every one of the (at most 4) predictions the lock
  /// schedules from them is already due, so a test doesn't have to wait out
  /// a real beat period to see one arrive.
  List<DateTime> pastBeats([Duration endOffset = const Duration(milliseconds: 2500)]) {
    final last = DateTime.now().subtract(endOffset);
    return [last.subtract(period * 2), last.subtract(period), last];
  }

  test('real beats pass straight through while disabled', () async {
    final beats = pastBeats();
    beats.forEach(source.add);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, beats);
  });

  test('two beats are not enough to lock a tempo, even enabled', () async {
    predictor.enabled = true;
    final last = DateTime.now().subtract(const Duration(seconds: 1));
    source.add(last.subtract(period));
    source.add(last);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, hasLength(2));
  });

  test('locks onto the tempo and fills in the beats no one heard, up to a cap', () async {
    predictor.enabled = true;
    final beats = pastBeats();
    beats.forEach(source.add);

    // The lock is already overdue by several periods, so all four capped
    // predictions arrive almost immediately rather than one real period
    // apart from each other.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(received, hasLength(beats.length + 4));

    final predicted = received.skip(beats.length);
    var previous = beats.last;
    for (final beat in predicted) {
      expect(beat.difference(previous), period);
      previous = beat;
    }

    // No fifth prediction gets invented once the cap is hit, even after
    // waiting out another full period.
    final countAtCap = received.length;
    await Future<void>.delayed(period + const Duration(milliseconds: 100));
    expect(received, hasLength(countAtCap));
  });

  test('a real beat resets the cap so prediction can resume after it', () async {
    predictor.enabled = true;
    final beats = pastBeats();
    beats.forEach(source.add);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final beforeRealBeat = received.length; // 3 real + 4 predicted, capped out

    // A real beat lands chronologically right where the lock expected one.
    // Being real rather than predicted, it must reset the cap — otherwise
    // a song running past four missed beats would stall prediction forever
    // even once real beats started arriving again.
    final realBeat = beats.last.add(period);
    source.add(realBeat);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // The real beat itself, plus a fresh run of predictions after it —
    // not zero, which is what a cap that never reset would produce.
    expect(received.length, beforeRealBeat + 1 + 4);
    expect(received[beforeRealBeat], realBeat);
  });
}
