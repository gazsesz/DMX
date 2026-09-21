/// Turns MIDI System Real-Time bytes into beats.
///
/// A MIDI clock is 24 pulses (0xF8) per quarter note — this counts them and
/// reports true on the 24th. Start/Continue (0xFA/0xFB) reset the count, so
/// a beat lands right on the downbeat instead of wherever the free-running
/// count happens to be — something a microphone can never give you.
///
/// Pure counting logic, no MIDI transport involved, so it's unit-testable
/// on its own against a plain sequence of status bytes.
class MidiClockCounter {
  static const clockByte = 0xF8;
  static const startByte = 0xFA;
  static const continueByte = 0xFB;
  static const stopByte = 0xFC;
  static const pulsesPerBeat = 24;

  int _pulses = 0;

  /// Zeroes the pulse count without reporting a beat — for a fresh
  /// connection, where whatever count a stray clock byte left behind
  /// shouldn't count towards the first beat.
  void reset() => _pulses = 0;

  /// Feeds one System Real-Time status byte in. Returns true exactly on the
  /// pulse that completes a beat; every other byte (including non-realtime
  /// ones, which this doesn't care about) returns false.
  bool feed(int statusByte) {
    switch (statusByte) {
      case clockByte:
        _pulses++;
        if (_pulses < pulsesPerBeat) return false;
        _pulses = 0;
        return true;
      case startByte:
      case continueByte:
        _pulses = 0;
        return false;
      default:
        return false;
    }
  }
}
