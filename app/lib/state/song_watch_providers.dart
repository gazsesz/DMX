import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio/osc_beat_source.dart';
import '../core/song/deck_song_audio.dart';
import '../core/song/song_follower.dart';
import '../core/song/song_timeline_math.dart';
import '../models/song_show.dart';
import 'artnet_providers.dart';
import 'audio_providers.dart';
import 'bank_providers.dart';
import 'chase_providers.dart';
import 'layer_providers.dart';
import 'playback_providers.dart' as pb;
import 'provider_reader.dart';
import 'smart_program_providers.dart';
import 'song_show_providers.dart';

const prefSongWatchEnabled = 'songWatch.enabled';
const prefSongWatchOffsetMs = 'songWatch.offsetMs';

/// Song watch settings — device-level, like the beat source: they belong to
/// this tablet and the DJ booth it sits in, not to a show.
class SongWatchPrefs {
  final bool enabled;

  /// How much later than the deck the lights run, in milliseconds (negative
  /// = earlier). For a PA or Bluetooth speaker that delays the sound.
  final int offsetMs;

  const SongWatchPrefs({this.enabled = false, this.offsetMs = 0});

  SongWatchPrefs copyWith({bool? enabled, int? offsetMs}) =>
      SongWatchPrefs(enabled: enabled ?? this.enabled, offsetMs: offsetMs ?? this.offsetMs);
}

class SongWatchPrefsNotifier extends StateNotifier<SongWatchPrefs> {
  SongWatchPrefsNotifier(super.initial);

  void setEnabled(bool value) => _set(state.copyWith(enabled: value));

  void setOffsetMs(int value) => _set(state.copyWith(offsetMs: value.clamp(-500, 500)));

  void _set(SongWatchPrefs next) {
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _persist(SongWatchPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(prefSongWatchEnabled, prefs.enabled);
    await sp.setInt(prefSongWatchOffsetMs, prefs.offsetMs);
  }
}

/// Loaded in `main()` before the first frame, like the other device prefs.
final songWatchPrefsProvider = StateNotifierProvider<SongWatchPrefsNotifier, SongWatchPrefs>((ref) {
  return SongWatchPrefsNotifier(const SongWatchPrefs());
});

/// What Song watch is doing now, for Setup and the dock.
final songWatchStatusProvider = StateProvider<SongWatchStatus>((ref) => const SongWatchStatus());

/// What was running before a show took the stage, so it can come back.
class PlaybackSnapshot {
  /// What each layer was playing (Smart Program layers included).
  final Map<String, pb.NowPlaying> layers;

  /// The Smart Program that was running, if one was.
  final String? smartProgramId;

  const PlaybackSnapshot({required this.layers, this.smartProgramId});

  bool get isEmpty => layers.isEmpty && smartProgramId == null;
}

/// Notes what every layer is playing right now.
PlaybackSnapshot takePlaybackSnapshot(ReadProvider read) {
  final layers = <String, pb.NowPlaying>{};
  for (final layer in read(layersProvider)) {
    final np = read(pb.nowPlayingForLayerProvider(layer.id));
    if (np != null && read(pb.chasePlayerProvider(layer.id)).isPlaying) layers[layer.id] = np;
  }
  return PlaybackSnapshot(layers: layers, smartProgramId: read(pb.smartProgramPlayerProvider).activeProgramId);
}

/// Starts again what [snapshot] noted: the Smart Program on all its layers,
/// then each plain bank on its layer and each chase once (a chase plays on
/// the layers its own steps name).
Future<void> restorePlayback(ReadProvider read, PlaybackSnapshot snapshot) async {
  if (!read(artNetServiceProvider).isConnected) return;
  final programId = snapshot.smartProgramId;
  if (programId != null) {
    final matches = read(smartProgramsProvider).where((p) => p.id == programId);
    if (matches.isNotEmpty) await pb.startSmartProgram(read, matches.first);
  }
  final chasesStarted = <String>{};
  for (final entry in snapshot.layers.entries) {
    final np = entry.value;
    switch (np.kind) {
      case pb.PlaybackKind.smartProgram:
        break; // came back with the program above
      case pb.PlaybackKind.bank:
        final matches = read(banksProvider).where((b) => b.id == np.id);
        if (matches.isNotEmpty) pb.runBankOnLayer(read, bank: matches.first, layerId: entry.key);
      case pb.PlaybackKind.chase:
        if (!chasesStarted.add(np.id)) break;
        final matches = read(chasesProvider).where((c) => c.id == np.id);
        if (matches.isNotEmpty) await pb.startLayeredChase(read, matches.first, playing: np);
    }
  }
}

/// The app side of [SongFollower]: remembers and stops what's running, plays
/// the show on the deck's clock, and brings the old program back after.
class _AppFollowerActions implements SongFollowerActions {
  _AppFollowerActions(ReadProvider read) : _read = stableRead(read);

  final ReadProvider _read;
  PlaybackSnapshot? _snapshot;
  DeckSongAudio? _clock;

  @override
  List<SongShow> get shows => _read(songShowsProvider);

  @override
  String? get playingShowId => _read(playingSongShowIdProvider);

  @override
  Future<bool> takeOver(SongShow show, Duration from) async {
    if (!_read(artNetServiceProvider).isConnected) return false;
    // A show running already (the previous track's) is not "the program
    // before": keep what was noted when the first show came in.
    if (_snapshot == null && _read(playingSongShowIdProvider) == null) {
      _snapshot = takePlaybackSnapshot(_read);
    }
    pb.stopSmartProgram(_read);
    for (final layer in _read(layersProvider)) {
      pb.stopLayer(_read, layer.id);
    }
    final audioMs = show.audio?.durationMs ?? 0;
    final timelineMs = show.msOfBeat(timelineBeats(show)).round();
    final clock = DeckSongAudio(
      length: Duration(milliseconds: audioMs > timelineMs ? audioMs : timelineMs),
      offset: Duration(milliseconds: _read(songWatchPrefsProvider).offsetMs),
    )..report(from);
    _clock = clock;
    final error = await startSongShow(_read, show, from: clock.position, clock: clock);
    if (error != null) {
      _clock = null;
      await giveBack();
      return false;
    }
    return true;
  }

  @override
  void report(Duration position, double rate) {
    final clock = _clock;
    if (clock == null) return;
    clock.offset = Duration(milliseconds: _read(songWatchPrefsProvider).offsetMs);
    clock.report(position, rate: rate);
  }

  @override
  void stopShow() {
    _clock = null;
    if (_read(playingSongShowIdProvider) != null) stopSongShow(_read);
  }

  @override
  Future<void> giveBack() async {
    stopShow();
    final snapshot = _snapshot;
    _snapshot = null;
    if (snapshot != null && !snapshot.isEmpty) await restorePlayback(_read, snapshot);
  }

  @override
  void forget() {
    _clock = null;
    _snapshot = null;
  }
}

/// Song watch, alive for as long as the app runs (watched by the shell).
/// While it's on, rkbx_link's socket stays open and every master-deck update
/// goes to the [SongFollower].
final songWatchProvider = Provider<void>((ref) {
  final enabled = ref.watch(songWatchPrefsProvider.select((p) => p.enabled));
  final source = ref.watch(oscBeatSourceProvider);
  final status = ref.read(songWatchStatusProvider.notifier);
  if (!enabled) {
    status.state = const SongWatchStatus();
    return;
  }
  final follower = SongFollower(_AppFollowerActions(ref.read));
  void publish() {
    if (status.state != follower.status) status.state = follower.status;
  }

  unawaited(source.open(OscBeatSource.songWatchHolder));
  final sub = source.deckUpdates.listen((deck) async {
    await follower.onDeck(deck, DateTime.now());
    publish();
  });
  final timer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
    await follower.onTick(DateTime.now());
    publish();
  });
  publish();
  ref.onDispose(() {
    sub.cancel();
    timer.cancel();
    unawaited(follower.stop());
    unawaited(source.release(OscBeatSource.songWatchHolder));
  });
});
