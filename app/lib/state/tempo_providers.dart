import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/log_scale.dart';

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
