import 'dart:math' as math;

/// "Is music playing?" from the microphone's plain loudness, held over a
/// couple of seconds — not from beats.
///
/// Beats can't answer it. On the tablet a keyboard click or a cough read
/// as strong an onset as a kick (+1…+18 dB against +7…+12 dB on the
/// overall band), and during real music the onset detector still went
/// 6–9 s without a beat, which the old "4 s without a beat" rule turned
/// into a blackout mid-song. Loudness separates the two cases cleanly:
/// music keeps the room above the floor nearly all the time, while a
/// click or a cough is above it for a few tens of milliseconds.
///
/// So the state is the share of the last [window] whose frames were at or
/// above the floor: at least [onShare] turns it on, below [offShare] turns
/// it off, anything in between keeps the current state.
class MusicPresence {
  final Duration window;
  final double onShare;
  final double offShare;

  MusicPresence({
    this.window = const Duration(seconds: 2),
    this.onShare = 0.5,
    this.offShare = 0.2,
  });

  // Levels rather than above/below flags, so moving the floor re-judges
  // the whole window at once instead of waiting for it to refill.
  final List<double> _levels = [];
  double _share = 0;
  bool _present = false;

  /// Null until the window has filled once, after a [reset] — not enough
  /// history yet to say either way.
  bool? get present => _levels.length < _capacity ? null : _present;

  double _hopMs = 11.6;
  int get _capacity => math.max(1, (window.inMilliseconds / _hopMs).round());

  /// Share of the window at or above the floor, 0..1 — for the meter.
  double get share => _share;

  /// One frame of [levelDb] (frame RMS, dBFS) against [floorDb], every
  /// [hopMs]. Returns [present] after it.
  bool? add(double levelDb, double floorDb, double hopMs) {
    _hopMs = hopMs;
    _levels.add(levelDb);
    while (_levels.length > _capacity) {
      _levels.removeAt(0);
    }
    var above = 0;
    for (final l in _levels) {
      if (l >= floorDb) above++;
    }
    _share = above / _levels.length;
    if (_levels.length >= _capacity) {
      if (!_present && _share >= onShare) _present = true;
      if (_present && _share < offShare) _present = false;
    }
    return present;
  }

  void reset() {
    _levels.clear();
    _share = 0;
    _present = false;
  }
}
