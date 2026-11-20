import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio/beat_detector.dart';
import '../core/audio/osc_beat_source.dart';
import '../core/song/deck_song_audio.dart';
import '../core/song/mic_song_recognizer.dart';
import '../core/song/show_fingerprints.dart';
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
const prefSongWatchSource = 'songWatch.source';

/// How Song watch knows which song is playing.
enum SongWatchSource {
  /// Recognises the song files of the shows through the microphone.
  mic,

  /// Rekordbox's master deck, named by rkbx_link over Wi-Fi.
  rkbx;

  static SongWatchSource fromName(String? name) =>
      SongWatchSource.values.firstWhere((s) => s.name == name, orElse: () => SongWatchSource.mic);
}

/// Song watch settings — device-level, like the beat source: they belong to
/// this tablet and the DJ booth it sits in, not to a show.
class SongWatchPrefs {
  final bool enabled;

  /// How much later than the deck the lights run, in milliseconds (negative
  /// = earlier). For a PA or Bluetooth speaker that delays the sound.
  final int offsetMs;

  final SongWatchSource source;

  const SongWatchPrefs({this.enabled = false, this.offsetMs = 0, this.source = SongWatchSource.mic});

  SongWatchPrefs copyWith({bool? enabled, int? offsetMs, SongWatchSource? source}) => SongWatchPrefs(
    enabled: enabled ?? this.enabled,
    offsetMs: offsetMs ?? this.offsetMs,
    source: source ?? this.source,
  );
}

class SongWatchPrefsNotifier extends StateNotifier<SongWatchPrefs> {
  SongWatchPrefsNotifier(super.initial);

  void setEnabled(bool value) => _set(state.copyWith(enabled: value));

  void setOffsetMs(int value) => _set(state.copyWith(offsetMs: value.clamp(-500, 500)));

  void setSource(SongWatchSource value) => _set(state.copyWith(source: value));

  void _set(SongWatchPrefs next) {
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _persist(SongWatchPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(prefSongWatchEnabled, prefs.enabled);
    await sp.setInt(prefSongWatchOffsetMs, prefs.offsetMs);
    await sp.setString(prefSongWatchSource, prefs.source.name);
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
/// While it's on, the chosen source feeds the [SongFollower]: rkbx_link's
/// master deck as it reports, or the microphone's recognised song.
final songWatchProvider = Provider<void>((ref) {
  final enabled = ref.watch(songWatchPrefsProvider.select((p) => p.enabled));
  final source = ref.watch(songWatchPrefsProvider.select((p) => p.source));
  final status = ref.read(songWatchStatusProvider.notifier);
  if (!enabled) {
    status.state = const SongWatchStatus();
    return;
  }
  switch (source) {
    case SongWatchSource.rkbx:
      _watchRkbx(ref, status);
    case SongWatchSource.mic:
      _watchMic(ref, status);
  }
});

void _watchRkbx(Ref ref, StateController<SongWatchStatus> status) {
  final osc = ref.watch(oscBeatSourceProvider);
  final follower = SongFollower(_AppFollowerActions(ref.read));
  void publish() {
    if (status.state != follower.status) status.state = follower.status;
  }

  unawaited(osc.open(OscBeatSource.songWatchHolder));
  final sub = osc.deckUpdates.listen((deck) async {
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
    unawaited(osc.release(OscBeatSource.songWatchHolder));
  });
}

/// The show that plays the song file at [path] (the first with cues).
SongShow? _showForPath(List<SongShow> shows, String path) {
  for (final show in shows) {
    if (show.audio?.path == path && show.cues.isNotEmpty) return show;
  }
  return null;
}

void _watchMic(Ref ref, StateController<SongWatchStatus> status) {
  // Rebuilt when the set of song files changes (a show added, a file linked).
  final paths = ref.watch(songShowsProvider.select((shows) => recognisableSongPaths(shows).join('\n')));
  final mic = ref.watch(beatDetectorProvider);
  final follower = SongFollower(
    _AppFollowerActions(ref.read),
    matcher: (shows, title, _) => _showForPath(shows, title),
  );
  var disposed = false;
  var known = 0;
  MicSongRecognizer? recognizer;
  StreamSubscription<Uint8List>? pcmSub;
  Timer? queryTimer;
  Timer? feedTimer;

  void publish() {
    final next = recognizer == null && paths.isNotEmpty
        ? const SongWatchStatus(phase: SongWatchPhase.preparing)
        : follower.status.withKnownSongs(known);
    if (status.state != next) status.state = next;
  }

  publish();
  Future<void> start() async {
    final fingerprints = await buildShowFingerprints(ref.read(songShowsProvider));
    if (disposed) return;
    known = fingerprints.paths.length;
    final rec = MicSongRecognizer(index: fingerprints.index, songIds: fingerprints.paths);
    recognizer = rec;
    if (!await mic.open(BeatDetectorService.songWatchHolder) || disposed) {
      publish();
      return;
    }
    pcmSub = mic.pcm.listen((chunk) => rec.addPcm(chunk, DateTime.now()));
    queryTimer = Timer.periodic(const Duration(seconds: 2), (_) => rec.query(DateTime.now()));
    // The recognised song as a "deck": its id and predicted position, many
    // times a second while it's still being heard — silence from here is
    // what tells the follower the song has gone.
    feedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final now = DateTime.now();
      final id = rec.songAt(now);
      if (id != null) {
        await follower.onDeck(RkbxDeckState(title: id, timeSec: rec.positionAt(now), timeAt: now), now);
      } else {
        await follower.onTick(now);
      }
      publish();
    });
    publish();
  }

  unawaited(start());
  ref.onDispose(() {
    disposed = true;
    pcmSub?.cancel();
    queryTimer?.cancel();
    feedTimer?.cancel();
    unawaited(follower.stop());
    unawaited(mic.release(BeatDetectorService.songWatchHolder));
  });
}
