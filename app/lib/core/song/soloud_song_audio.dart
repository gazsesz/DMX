import 'package:flutter_soloud/flutter_soloud.dart';

import 'song_show_player.dart';

/// [SongAudio] on flutter_soloud — the engine measured in the phase-0 spike.
class SoloudSongAudio implements SongAudio {
  AudioSource? _source;
  SoundHandle? _handle;
  Duration _length = Duration.zero;

  @override
  Duration get length => _length;

  @override
  Future<void> load(String path) async {
    final engine = SoLoud.instance;
    if (!engine.isInitialized) await engine.init();
    await _release();
    _source = await engine.loadFile(path, mode: LoadMode.disk);
    _length = engine.getLength(_source!);
  }

  @override
  void play(Duration from) {
    final source = _source;
    if (source == null) return;
    final engine = SoLoud.instance;
    _handle = engine.play(source);
    if (from > Duration.zero) engine.seek(_handle!, from);
  }

  @override
  void stop() {
    final handle = _handle;
    _handle = null;
    if (handle != null) SoLoud.instance.stop(handle);
  }

  @override
  void seek(Duration to) {
    final handle = _handle;
    if (handle != null) SoLoud.instance.seek(handle, to);
  }

  @override
  Duration get position {
    final handle = _handle;
    return handle == null ? Duration.zero : SoLoud.instance.getPosition(handle);
  }

  Future<void> _release() async {
    stop();
    final source = _source;
    _source = null;
    if (source != null) await SoLoud.instance.disposeSource(source);
  }

  Future<void> dispose() => _release();
}
