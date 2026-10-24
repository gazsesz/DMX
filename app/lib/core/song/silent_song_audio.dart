import 'song_show_player.dart';

/// A song with no sound: just a clock running over a stretch of time. What a
/// show plays on when no song file is linked, so the lights can be tested from
/// the tempo alone.
class SilentSongAudio implements SongAudio {
  SilentSongAudio({required this.length, Stopwatch? stopwatch}) : _watch = stopwatch ?? Stopwatch();

  @override
  final Duration length;

  final Stopwatch _watch;
  Duration _from = Duration.zero;

  @override
  Future<void> load(String path) async {}

  @override
  void play(Duration from) {
    _from = from;
    _watch
      ..reset()
      ..start();
  }

  @override
  void stop() {
    _from = position;
    _watch
      ..stop()
      ..reset();
  }

  @override
  void seek(Duration to) {
    _from = to;
    _watch
      ..reset()
      ..start();
  }

  @override
  Duration get position => _from + _watch.elapsed;
}
