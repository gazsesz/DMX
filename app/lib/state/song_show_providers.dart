import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/song/soloud_song_audio.dart';
import '../core/song/song_show_player.dart';
import '../models/song_show.dart';
import 'bank_providers.dart';
import 'chase_providers.dart';
import 'playback_providers.dart' as pb;
import 'provider_reader.dart';

const _uuid = Uuid();

final songShowsProvider = StateNotifierProvider<SongShowsNotifier, List<SongShow>>((ref) => SongShowsNotifier());

class SongShowsNotifier extends StateNotifier<List<SongShow>> {
  SongShowsNotifier() : super(const []);

  SongShow create(String name) {
    final show = SongShow(id: _uuid.v4(), name: name);
    state = [...state, show];
    return show;
  }

  void upsert(SongShow show) {
    final exists = state.any((s) => s.id == show.id);
    state = exists ? [for (final s in state) if (s.id == show.id) show else s] : [...state, show];
  }

  void duplicate(String id) {
    final source = state.where((s) => s.id == id);
    if (source.isEmpty) return;
    final copy = source.first;
    state = [...state, copy.duplicateAs(_uuid.v4(), '${copy.name} Copy')];
  }

  void remove(String id) => state = state.where((s) => s.id != id).toList();

  void loadAll(List<SongShow> shows) => state = shows;
}

/// Sends a song show's cues to the layer players, the same way a dashboard
/// tile or a Smart Program would start a bank or a chase.
class _LayerCueSink implements SongCueSink {
  _LayerCueSink(ReadProvider read) : _read = stableRead(read);

  final ReadProvider _read;

  @override
  void start(SongCue cue) {
    final target = cue.target;
    if (target == null) return;
    if (target.isBank) {
      final matches = _read(banksProvider).where((b) => b.id == target.id);
      if (matches.isEmpty) return;
      pb.runBankOnLayer(_read, bank: matches.first, layerId: cue.layerId);
    } else {
      final matches = _read(chasesProvider).where((c) => c.id == target.id);
      if (matches.isEmpty) return;
      // The whole chase plays, on the layers its own steps name; a cue's layer
      // only matters for banks.
      pb.startLayeredChase(
        _read,
        matches.first,
        playing: pb.NowPlaying(id: target.id, kind: pb.PlaybackKind.chase, name: matches.first.name),
      );
    }
  }

  @override
  void stopLayer(String layerId) => pb.stopLayer(_read, layerId);
}

final songShowPlayerProvider = Provider<SongShowPlayer>((ref) {
  final audio = SoloudSongAudio();
  final player = SongShowPlayer(audio: audio, sink: _LayerCueSink(ref.read));
  ref.onDispose(() {
    player.dispose();
    audio.dispose();
  });
  return player;
});

/// Plays [show] from [from]. Returns a message when it can't start.
Future<String?> startSongShow(ReadProvider read, SongShow show, {Duration from = Duration.zero}) async {
  final path = show.audio?.path;
  if (path == null) return '${show.name} has no audio file linked';
  try {
    await read(songShowPlayerProvider).play(show, from: from, audioPath: path);
  } catch (e) {
    return 'Could not play ${show.name}: $e';
  }
  return null;
}

void stopSongShow(ReadProvider read) => read(songShowPlayerProvider).stop();
