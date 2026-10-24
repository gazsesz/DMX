/// Smooths a stepped playback position into a continuous clock.
///
/// The audio engine reports its position in ~47 ms steps (measured in the
/// phase-0 spike), which is far coarser than a cue should land. Between
/// reports this carries on from the last one by the wall clock; the
/// interpolation error measured against the real position was ~1 ms median,
/// ~30 ms worst.
class SongClock {
  /// A report this far from where the clock expected to be is a seek, not
  /// jitter — the clock jumps there instead of easing.
  static const seekThreshold = Duration(milliseconds: 250);

  Duration _anchorPos = Duration.zero;
  Duration _anchorWall = Duration.zero;
  Duration _lastReport = Duration.zero;
  Duration _last = Duration.zero;
  bool _running = false;
  bool _jumped = false;

  bool get isRunning => _running;

  /// Starts (or restarts) the clock at [position] as of [wall].
  void start(Duration position, Duration wall) {
    _anchorPos = position;
    _anchorWall = wall;
    _lastReport = position;
    _last = position;
    _running = true;
    _jumped = false;
  }

  void stop() => _running = false;

  /// Feeds in the engine's latest [position], read at [wall].
  void report(Duration position, Duration wall) {
    if (!_running || position == _lastReport) return;
    _lastReport = position;
    final expected = _anchorPos + (wall - _anchorWall);
    if ((position - expected).abs() > seekThreshold) _jumped = true;
    _anchorPos = position;
    _anchorWall = wall;
  }

  /// The song position at [wall]. Never runs backwards on its own: a report
  /// slightly behind the clock holds it still until the audio catches up;
  /// only a seek moves it back.
  Duration now(Duration wall) {
    if (!_running) return _last;
    final estimate = _anchorPos + (wall - _anchorWall);
    if (_jumped) {
      _jumped = false;
      _last = estimate;
    } else if (estimate > _last) {
      _last = estimate;
    }
    return _last;
  }
}
