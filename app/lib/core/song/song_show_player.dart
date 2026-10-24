import 'dart:async';

import '../../models/song_show.dart';
import 'song_clock.dart';
import 'song_cue_scheduler.dart';

/// The audio side of a song show, kept behind an interface so the cue logic
/// is testable without a sound card.
abstract class SongAudio {
  Future<void> load(String path);
  Duration get length;
  void play(Duration from);
  void stop();
  void seek(Duration to);
  Duration get position;
}

/// Where a firing cue goes — in the app, the layer players.
abstract class SongCueSink {
  void start(SongCue cue);
  void stopLayer(String layerId);
}

/// Plays a [SongShow]: the audio runs, a smoothed clock follows it, and every
/// cue the clock passes is handed to the [SongCueSink].
class SongShowPlayer {
  /// How often the clock is checked. Well under the audio engine's own
  /// position step, so cues don't wait on top of it.
  static const tickInterval = Duration(milliseconds: 10);

  /// A forward jump larger than this between two ticks is treated as a seek
  /// (state is re-established) rather than a run of cues to fire.
  static const _skipThreshold = Duration(milliseconds: 500);

  final SongAudio audio;

  /// What is playing now: [audio], or the silent clock a show without a song
  /// file is run on.
  late SongAudio _active = audio;
  final SongCueSink sink;
  final Duration Function() _wall;

  SongShowPlayer({required this.audio, required this.sink, Duration Function()? wall})
    : _wall = wall ?? _stopwatchWall();

  static Duration Function() _stopwatchWall() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  final _clock = SongClock();
  final _finished = StreamController<void>.broadcast();
  SongShow? _show;
  Timer? _timer;
  Duration _lastPos = Duration.zero;

  SongShow? get show => _show;
  bool get isPlaying => _show != null && _clock.isRunning;
  Stream<void> get finished => _finished.stream;

  /// The song position now, for the UI.
  Duration get position => _clock.now(_wall());

  /// Starts [show] at [from]. Whatever should already be running at that
  /// point starts too, so jumping into a drop lands on the drop's look.
  Future<void> play(
    SongShow show, {
    Duration from = Duration.zero,
    String? audioPath,
    SongAudio? audioOverride,
  }) async {
    stop();
    if (audioOverride == null && audioPath != null) await audio.load(audioPath);
    _active = audioOverride ?? audio;
    _show = show;
    _active.play(from);
    _clock.start(from, _wall());
    _lastPos = from;
    _restoreState(from);
    _timer = Timer.periodic(tickInterval, (_) => tick());
  }

  /// Replaces the running show with an edited copy of itself, keeping the
  /// position — an edit never restarts the song.
  void update(SongShow show) {
    if (_show?.id != show.id) return;
    _show = show;
  }

  void seek(Duration to) {
    if (!isPlaying) return;
    _active.seek(to);
    _clock.start(to, _wall());
    _lastPos = to;
    _restoreState(to);
  }

  /// Ends playback. The layers keep their last look — silence is the next
  /// cue's job (or a blackout's), the same as stopping any other program.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_show != null) _active.stop();
    _clock.stop();
    _show = null;
  }

  /// One clock step. Public so tests can drive time themselves.
  void tick() {
    final show = _show;
    if (show == null) return;
    final wall = _wall();
    _clock.report(_active.position, wall);
    final pos = _clock.now(wall);
    if (pos < _lastPos || pos - _lastPos > _skipThreshold) {
      _restoreState(pos);
    } else {
      for (final cue in cuesDue(show, _lastPos.inMicroseconds / 1000, pos.inMicroseconds / 1000)) {
        _fire(cue);
      }
    }
    _lastPos = pos;
    final length = _active.length;
    if (length > Duration.zero && pos >= length) {
      stop();
      _finished.add(null);
    }
  }

  void _restoreState(Duration pos) {
    final show = _show;
    if (show == null) return;
    final ms = pos.inMicroseconds / 1000;
    for (final layerId in layersToSilence(show, ms)) {
      sink.stopLayer(layerId);
    }
    for (final cue in stateAt(show, ms)) {
      _fire(cue);
    }
  }

  void _fire(SongCue cue) {
    switch (cue.action) {
      case SongCueAction.start:
        if (cue.hasTarget) sink.start(cue);
      case SongCueAction.stop:
        sink.stopLayer(cue.layerId);
    }
  }

  void dispose() {
    stop();
    _finished.close();
  }
}
