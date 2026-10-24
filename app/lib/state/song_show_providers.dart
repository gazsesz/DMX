import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/song/soloud_song_audio.dart';
import '../core/song/song_scope.dart';
import '../core/song/song_show_player.dart';
import '../models/song_show.dart';
import 'artnet_providers.dart';
import 'bank_providers.dart';
import 'chase_providers.dart';
import 'fixture_group_providers.dart';
import 'fixture_providers.dart';
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
class LayerCueSink implements SongCueSink {
  LayerCueSink(ReadProvider read) : _read = stableRead(read);

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

/// The id of the song show that is playing, if any — for the list and the
/// editor to show a Stop button.
final playingSongShowIdProvider = StateProvider<String?>((ref) => null);

/// The layers the running song show plays on, so ending it can stop them and
/// lift the fixture scope it put on them.
final songShowLayersProvider = StateProvider<Set<String>>((ref) => const {});

final songShowPlayerProvider = Provider<SongShowPlayer>((ref) {
  final audio = SoloudSongAudio();
  final player = SongShowPlayer(audio: audio, sink: LayerCueSink(ref.read));
  final finished = player.finished.listen((_) => _endSongShow(ref.read));
  ref.onDispose(() {
    finished.cancel();
    player.dispose();
    audio.dispose();
  });
  return player;
});

/// Every layer [show] can touch: the ones its cues name, plus the lanes of any
/// chase it starts (a chase plays on the layers its own steps name).
Set<String> songShowLayers(ReadProvider read, SongShow show) {
  final layers = <String>{};
  for (final cue in show.cues) {
    layers.add(cue.layerId);
    final target = cue.target;
    if (target != null && !target.isBank) {
      for (final chase in read(chasesProvider)) {
        if (chase.id == target.id) layers.addAll(pb.chaseLayerIds(read, chase));
      }
    }
  }
  return layers;
}

/// Confines the show's layers to the fixtures in its groups (a show with no
/// groups, or none left, plays on everything) and remembers which layers it
/// used. Layers dropped by an edit are released.
void _applySongScope(ReadProvider read, SongShow show) {
  final service = read(artNetServiceProvider);
  final layers = songShowLayers(read, show);
  final channels = scopeChannels(
    groupIds: show.groupIds,
    groups: read(fixtureGroupsProvider),
    fixtures: read(patchedFixturesProvider),
  );
  final previous = read(songShowLayersProvider);
  for (final layer in previous.difference(layers)) {
    service.setLayerScope(layer, null);
  }
  for (final layer in layers) {
    service.setLayerScope(layer, channels);
  }
  read(songShowLayersProvider.notifier).state = layers;
}

/// Ends the running show: its layers stop where they are (the look is held,
/// like stopping a Smart Program) and the fixture scope comes off them.
void _endSongShow(ReadProvider read) {
  final service = read(artNetServiceProvider);
  for (final layer in read(songShowLayersProvider)) {
    pb.stopLayer(read, layer);
    service.setLayerScope(layer, null);
  }
  read(songShowLayersProvider.notifier).state = const {};
  read(playingSongShowIdProvider.notifier).state = null;
}

/// Plays [show] from [from]. Returns a message when it can't start.
Future<String?> startSongShow(ReadProvider read, SongShow show, {Duration from = Duration.zero}) async {
  final path = show.audio?.path;
  if (path == null) return '${show.name} has no audio file linked';
  // One show at a time: the one on stage ends before this one starts.
  if (read(songShowPlayerProvider).show != null) {
    read(songShowPlayerProvider).stop();
    _endSongShow(read);
  }
  _applySongScope(read, show);
  try {
    await read(songShowPlayerProvider).play(show, from: from, audioPath: path);
  } catch (e) {
    _endSongShow(read);
    return 'Could not play ${show.name}: $e';
  }
  read(playingSongShowIdProvider.notifier).state = show.id;
  return null;
}

void stopSongShow(ReadProvider read) {
  read(songShowPlayerProvider).stop();
  _endSongShow(read);
}

/// Pushes an edited [show] to the player if it is the one playing, with its
/// fixture scope and layers brought up to date.
void updateRunningSongShow(ReadProvider read, SongShow show) {
  final player = read(songShowPlayerProvider);
  if (player.show?.id != show.id) return;
  player.update(show);
  _applySongScope(read, show);
}
