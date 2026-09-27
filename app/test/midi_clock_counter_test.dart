import 'package:dmx_controller/core/audio/midi_clock_counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('24 clock pulses produce exactly one beat', () {
    final counter = MidiClockCounter();
    var beats = 0;
    for (var i = 0; i < 24; i++) {
      if (counter.feed(MidiClockCounter.clockByte)) beats++;
    }
    expect(beats, 1);
  });

  test('clock keeps ticking beats every 24 pulses', () {
    final counter = MidiClockCounter();
    var beats = 0;
    for (var i = 0; i < 24 * 5; i++) {
      if (counter.feed(MidiClockCounter.clockByte)) beats++;
    }
    expect(beats, 5);
  });

  test('Start mid-beat resets the count instead of finishing it early', () {
    final counter = MidiClockCounter();
    for (var i = 0; i < 12; i++) {
      counter.feed(MidiClockCounter.clockByte);
    }
    expect(counter.feed(MidiClockCounter.startByte), false);

    var beats = 0;
    for (var i = 0; i < 23; i++) {
      if (counter.feed(MidiClockCounter.clockByte)) beats++;
    }
    expect(beats, 0, reason: 'Start should have zeroed the count, not left 12 pulses standing');
    expect(counter.feed(MidiClockCounter.clockByte), true, reason: 'the 24th pulse after Start');
  });

  test('Continue also resets the count', () {
    final counter = MidiClockCounter();
    for (var i = 0; i < 20; i++) {
      counter.feed(MidiClockCounter.clockByte);
    }
    counter.feed(MidiClockCounter.continueByte);
    for (var i = 0; i < 23; i++) {
      expect(counter.feed(MidiClockCounter.clockByte), false);
    }
    expect(counter.feed(MidiClockCounter.clockByte), true);
  });

  test('non-realtime bytes are ignored and do not advance the count', () {
    final counter = MidiClockCounter();
    for (var i = 0; i < 23; i++) {
      counter.feed(MidiClockCounter.clockByte);
    }
    expect(counter.feed(0x90), false); // a stray note-on status byte
    expect(counter.feed(MidiClockCounter.clockByte), true, reason: 'the 24th real clock pulse');
  });

  test('reset zeroes the count without reporting a beat', () {
    final counter = MidiClockCounter();
    for (var i = 0; i < 23; i++) {
      counter.feed(MidiClockCounter.clockByte);
    }
    counter.reset();
    for (var i = 0; i < 23; i++) {
      expect(counter.feed(MidiClockCounter.clockByte), false);
    }
    expect(counter.feed(MidiClockCounter.clockByte), true);
  });
}
