import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio/beat_detector.dart';
import '../core/audio/beat_predictor.dart';
import '../core/audio/beat_source.dart';
import '../core/audio/midi_beat_source.dart';
import '../core/playback/chase_player.dart';

/// One shared beat detector for the whole app, so a chase started from any
/// screen reacts to the same microphone listener the Dashboard toggles.
final beatDetectorProvider = Provider<BeatDetectorService>((ref) {
  final service = BeatDetectorService();
  ref.onDispose(service.dispose);
  return service;
});

/// One shared MIDI beat source, mirroring [beatDetectorProvider] — the
/// microphone and MIDI live side by side rather than one replacing the
/// other, so switching the source in Setup doesn't lose either one's state.
final midiBeatSourceProvider = Provider<MidiBeatSource>((ref) {
  final source = MidiBeatSource();
  ref.onDispose(source.dispose);
  return source;
});

const prefBeatSourceKind = 'beatSource.kind';
const prefBeatSourceMidiDeviceId = 'beatSource.midiDeviceId';
const prefBeatSourceMidiDeviceName = 'beatSource.midiDeviceName';

enum BeatSourceKind {
  mic,
  midi;

  String get label => switch (this) {
    BeatSourceKind.mic => 'Microphone',
    BeatSourceKind.midi => 'MIDI (USB)',
  };
}

class BeatSourcePrefs {
  final BeatSourceKind kind;

  /// The last MIDI device connected, by id and name — device-level, not
  /// part of the project, since which USB device is plugged in has nothing
  /// to do with which show is loaded. Kept even after a disconnect so Setup
  /// can show what to reconnect to and the id lets a reconnect find it again
  /// without the user re-picking it from the list.
  final String? midiDeviceId;
  final String? midiDeviceName;

  const BeatSourcePrefs({this.kind = BeatSourceKind.mic, this.midiDeviceId, this.midiDeviceName});

  BeatSourcePrefs copyWith({BeatSourceKind? kind, String? midiDeviceId, String? midiDeviceName}) {
    return BeatSourcePrefs(
      kind: kind ?? this.kind,
      midiDeviceId: midiDeviceId ?? this.midiDeviceId,
      midiDeviceName: midiDeviceName ?? this.midiDeviceName,
    );
  }
}

BeatSourcePrefs beatSourcePrefsFromStrings({String? kind, String? midiDeviceId, String? midiDeviceName}) {
  return BeatSourcePrefs(
    kind: BeatSourceKind.values.firstWhere((e) => e.name == kind, orElse: () => BeatSourceKind.mic),
    midiDeviceId: midiDeviceId,
    midiDeviceName: midiDeviceName,
  );
}

/// Which beat source is live, and which MIDI device to reconnect to.
/// Persisted like the other device-level preferences (loaded before the
/// first frame in `main()`), not project state.
class BeatSourcePrefsNotifier extends StateNotifier<BeatSourcePrefs> {
  BeatSourcePrefsNotifier(super.initial);

  void setKind(BeatSourceKind kind) => _set(state.copyWith(kind: kind));

  void setMidiDevice(String id, String name) =>
      _set(state.copyWith(midiDeviceId: id, midiDeviceName: name));

  void _set(BeatSourcePrefs next) {
    state = next;
    _persist(next);
  }

  Future<void> _persist(BeatSourcePrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(prefBeatSourceKind, prefs.kind.name);
    if (prefs.midiDeviceId != null) await sp.setString(prefBeatSourceMidiDeviceId, prefs.midiDeviceId!);
    if (prefs.midiDeviceName != null) {
      await sp.setString(prefBeatSourceMidiDeviceName, prefs.midiDeviceName!);
    }
  }
}

final beatSourcePrefsProvider = StateNotifierProvider<BeatSourcePrefsNotifier, BeatSourcePrefs>((ref) {
  return BeatSourcePrefsNotifier(const BeatSourcePrefs());
});

/// The beat source actually driving playback right now — the microphone
/// detector or the MIDI clock, whichever Setup has selected. Every playback
/// call site (`ChasePlayer`, `SmartProgramPlayer`, the dock, momentary FX,
/// `startChase`) reads this instead of reaching for a concrete source
/// directly, so switching source in Setup takes effect everywhere at once.
/// Mic-only tuning (sensitivity, frequency band, the VU meter) still reads
/// [beatDetectorProvider] directly, but only from UI that's already checked
/// the kind is [BeatSourceKind.mic].
final activeBeatSourceProvider = Provider<BeatSource>((ref) {
  final kind = ref.watch(beatSourcePrefsProvider).kind;
  return switch (kind) {
    BeatSourceKind.mic => ref.watch(beatDetectorProvider),
    BeatSourceKind.midi => ref.watch(midiBeatSourceProvider),
  };
});

/// One shared predictor sitting in front of [activeBeatSourceProvider], so
/// every beat-synced chase (Dashboard, Banks, the Chase editor's preview)
/// fills the same missed beats the same way instead of each screen guessing
/// on its own.
///
/// A MIDI clock never misses a beat, so [BeatPredictionEnabledProvider]
/// stays off and unreachable while the source is MIDI — this still wraps it
/// safely either way, since a disabled predictor is pure passthrough.
final beatPredictorProvider = Provider<BeatPredictor>((ref) {
  final predictor = BeatPredictor(ref.watch(activeBeatSourceProvider).beatEvents);
  ref.onDispose(predictor.dispose);
  return predictor;
});

/// Whether the predictor is filling in missed beats. Off by default —
/// same reasoning as [beatSyncEnabledProvider] starting false: it's a
/// listening mode you opt into, not one that should surprise you by already
/// being on. Only meaningful (and only shown in the UI) while beat sync
/// itself is armed and the source is the microphone.
final beatPredictionEnabledProvider = StateNotifierProvider<BeatPredictionNotifier, bool>((ref) {
  return BeatPredictionNotifier(ref.watch(beatPredictorProvider));
});

class BeatPredictionNotifier extends StateNotifier<bool> {
  final BeatPredictor _predictor;

  BeatPredictionNotifier(this._predictor) : super(false);

  void setEnabled(bool value) {
    _predictor.enabled = value;
    state = value;
  }
}

/// Whether beat sync is armed, shared by every screen that can start
/// playback. It has to be one flag: a bank fired from the Dashboard used to
/// pick up the Dashboard's own toggle, so a bank run from the Banks tab
/// could sit frozen waiting for beats with no way to switch it off from
/// there.
final beatSyncEnabledProvider = StateNotifierProvider<BeatSyncNotifier, bool>((ref) {
  return BeatSyncNotifier(ref.watch(activeBeatSourceProvider));
});

/// Half time / on the beat / double time / flash — shared app-wide like
/// [beatSyncEnabledProvider], so a chase reads the same however it's fired.
final beatRateProvider = StateProvider<BeatRate>((ref) => BeatRate.normal);

/// How long the lit step stays up in [BeatRate.flash].
///
/// 80 ms is about the shortest a flash still reads as light rather than a
/// glitch, and short enough that the rig is dark again well before the next
/// beat at any danceable tempo.
final flashLengthProvider = StateProvider<Duration>((ref) => const Duration(milliseconds: 80));

BeatRate beatRateOf(WidgetRef ref) => ref.read(beatRateProvider);

class BeatSyncNotifier extends StateNotifier<bool> {
  final BeatSource _source;

  BeatSyncNotifier(this._source) : super(_source.isListening);

  /// Turns beat sync on/off, starting or stopping the active source with it.
  /// Returns null on success, or the reason it couldn't be opened.
  Future<String?> setEnabled(bool value) async {
    if (!value) {
      await _source.stop();
      state = false;
      return null;
    }
    final started = await _source.start();
    if (!started) return _source.lastError ?? 'Could not start the beat source';
    state = true;
    return null;
  }
}
