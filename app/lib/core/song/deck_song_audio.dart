import 'song_show_player.dart';

/// A song played by someone else — a DJ deck in Rekordbox, reported over
/// rkbx_link — as the clock of a [SongShowPlayer]. Nothing is played here:
/// the position is the deck's own, carried on by the wall clock between
/// reports at the deck's playback speed, so the show follows pitch, loops,
/// cue jumps and pauses as they happen.
class DeckSongAudio implements SongAudio {
  /// How far the position is carried on after the last report. Short, so a
  /// paused deck holds the show nearly where it stopped; rkbx_link reports
  /// many times a second, so a playing deck never runs out of it.
  static const maxCoast = Duration(milliseconds: 150);

  DeckSongAudio({required this.length, this.offset = Duration.zero, Duration Function()? wall})
    : _wall = wall ?? _stopwatchWall();

  static Duration Function() _stopwatchWall() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  @override
  final Duration length;

  /// Shifts the lights against the sound: positive makes the show run that
  /// much later than the deck (when the PA's sound reaches the room late).
  Duration offset;

  final Duration Function() _wall;
  Duration _reported = Duration.zero;
  Duration _reportedAt = Duration.zero;
  double _rate = 1;

  /// Feeds in the deck's position in the track, and how fast it is running
  /// (1.0 = the track's own tempo).
  void report(Duration trackPosition, {double rate = 1}) {
    _reported = trackPosition;
    _reportedAt = _wall();
    _rate = rate;
  }

  @override
  Duration get position {
    var since = _wall() - _reportedAt;
    if (since > maxCoast) since = maxCoast;
    if (since < Duration.zero) since = Duration.zero;
    final pos = _reported + since * _rate - offset;
    return pos < Duration.zero ? Duration.zero : pos;
  }

  @override
  Future<void> load(String path) async {}

  @override
  void play(Duration from) {}

  @override
  void stop() {}

  @override
  void seek(Duration to) {}
}
