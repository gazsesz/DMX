import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/beat_detector.dart';
import '../core/audio/tempo_estimator.dart';
import '../core/widgets/log_scale.dart';
import 'audio_providers.dart';
import 'provider_reader.dart';

/// The Dashboard's live timing: what a bank steps at, how long looks
/// cross-fade, and whether that overrides a chase's own saved per-step
/// timing.
///
/// It lives here rather than inside the Dashboard's State so anything else
/// firing the same triggers — today the remote-control endpoint — plays them
/// exactly as pressing the tile would. The *controls* stay on the Dashboard.
class TempoState {
  final double stepSeconds;
  final double fadeSeconds;
  final bool overrideTiming;

  /// Derive the fade from the tempo instead of using [fadeSeconds]: a
  /// slowing song gets a longer cross-fade, a quickening one a tighter
  /// snap. What you'd otherwise be reaching for the Fade slider to do by
  /// hand every time the music changes gear.
  final bool autoFade;

  /// How hard [autoFade] leans on the tempo, 0..1 — see [autoFadeRatio].
  final double autoFadeAmount;

  const TempoState({
    this.stepSeconds = 1.2,
    this.fadeSeconds = 0.3,
    this.overrideTiming = true,
    this.autoFade = false,
    this.autoFadeAmount = 0.5,
  });

  /// Steps per minute, derived rather than stored.
  ///
  /// It used to be a field kept in step with [stepSeconds] by every setter,
  /// which drifted the moment one was set without the other — the default
  /// state shipped claiming 120 BPM and 1.2s per step at the same time, and
  /// the readout dutifully printed both. One number, one source.
  ///
  /// The clamp is a display bound: the Step Speed slider reaches well past
  /// 300 steps a minute, and the BPM box would rather saturate than show a
  /// four-digit tempo.
  double get bpm => (60 / stepSeconds).clamp(20.0, 300.0);

  /// The fraction of a step the cross-fade takes at the current amount.
  ///
  /// The floor isn't zero and the ceiling isn't one on purpose: at 0 the
  /// switch would do nothing, and at 1 the next fade would start exactly as
  /// the last finished, leaving the rig permanently mid-transition with no
  /// look ever fully landing.
  static const _minRatio = 0.05;
  static const _maxRatio = 0.85;

  double get autoFadeRatio => _minRatio + (_maxRatio - _minRatio) * autoFadeAmount.clamp(0.0, 1.0);

  /// What a cross-fade actually lasts right now.
  ///
  /// While beat sync is armed [stepSeconds] tracks the detected tempo, so
  /// this follows the music by itself; with beat sync off it simply scales
  /// against the step time you set.
  double get effectiveFadeSeconds {
    if (!autoFade) return fadeSeconds;
    return (stepSeconds * autoFadeRatio).clamp(fadeTimeScale.min, fadeTimeScale.max);
  }

  Duration get hold => Duration(milliseconds: (stepSeconds * 1000).round());
  Duration get fade => Duration(milliseconds: (effectiveFadeSeconds * 1000).round());

  TempoState copyWith({
    double? stepSeconds,
    double? fadeSeconds,
    bool? overrideTiming,
    bool? autoFade,
    double? autoFadeAmount,
  }) {
    return TempoState(
      stepSeconds: stepSeconds ?? this.stepSeconds,
      fadeSeconds: fadeSeconds ?? this.fadeSeconds,
      overrideTiming: overrideTiming ?? this.overrideTiming,
      autoFade: autoFade ?? this.autoFade,
      autoFadeAmount: autoFadeAmount ?? this.autoFadeAmount,
    );
  }
}

class TempoNotifier extends StateNotifier<TempoState> {
  TempoNotifier() : super(const TempoState());

  /// Sets tempo from a BPM value. [TempoState.stepSeconds] is the one stored
  /// number — BPM is a view of it — so this just converts.
  void setBpm(double bpm) => setStepSeconds(60 / bpm.clamp(20.0, 300.0));

  void setStepSeconds(double seconds) {
    state = state.copyWith(
      stepSeconds: seconds.clamp(stepSpeedScale.min, stepSpeedScale.max),
    );
  }

  void setFadeSeconds(double seconds) =>
      state = state.copyWith(fadeSeconds: seconds.clamp(fadeTimeScale.min, fadeTimeScale.max));

  void setOverrideTiming(bool value) => state = state.copyWith(overrideTiming: value);

  void setAutoFade(bool value) => state = state.copyWith(autoFade: value);

  void setAutoFadeAmount(double amount) =>
      state = state.copyWith(autoFadeAmount: amount.clamp(0.0, 1.0));
}

final tempoProvider = StateNotifierProvider<TempoNotifier, TempoState>((ref) => TempoNotifier());

/// Keeps [TempoState.stepSeconds] following the detected beat while beat
/// sync is armed, so the BPM readout and auto-fade track the music.
///
/// App-level rather than owned by the control panel: the panel only exists
/// while it's open, and the tempo has to keep up whether or not anyone is
/// looking at it. Beats are ignored while beat sync is off — the mic also
/// runs for Smart Programs, and those beats must not drag the manual step
/// speed around behind the user's back.
final beatTempoTrackerProvider = Provider<BeatTempoTracker>((ref) {
  final tracker = BeatTempoTracker(
    service: ref.watch(beatDetectorProvider),
    armed: () => ref.read(beatSyncEnabledProvider),
    onTempo: (bpm) => ref.read(tempoProvider.notifier).setBpm(bpm),
  );
  ref.onDispose(tracker.dispose);
  return tracker;
});

class BeatTempoTracker {
  final bool Function() armed;
  final void Function(double bpm) onTempo;

  final List<DateTime> _beats = [];
  StreamSubscription<DateTime>? _sub;

  BeatTempoTracker({
    required BeatDetectorService service,
    required this.armed,
    required this.onTempo,
  }) {
    _sub = service.beatEvents.listen(_onBeat);
  }

  void _onBeat(DateTime now) {
    if (!armed()) {
      _beats.clear();
      return;
    }
    // A long gap means a new song (or the music stopped) — starting over
    // beats folding the old tempo into the new one.
    if (_beats.isNotEmpty && now.difference(_beats.last) > const Duration(seconds: 2)) {
      _beats.clear();
    }
    _beats.add(now);
    if (_beats.length > 12) _beats.removeAt(0);
    final estimate = estimateTempo(_beats);
    if (estimate != null && estimate.isConfident) onTempo(estimate.bpm);
  }

  void dispose() => _sub?.cancel();
}

/// Brings [beatTempoTrackerProvider] to life at startup — it can't follow
/// anything until it exists.
void watchBeatTempo(ReadProvider read) => read(beatTempoTrackerProvider);
