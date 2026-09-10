import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Dashboard's live timing: what a bank steps at, how long looks
/// cross-fade, and whether that overrides a chase's own saved per-step
/// timing.
///
/// It lives here rather than inside the Dashboard's State so anything else
/// firing the same triggers — today the remote-control endpoint — plays them
/// exactly as pressing the tile would. The *controls* stay on the Dashboard.
class TempoState {
  final double bpm;
  final double stepSeconds;
  final double fadeSeconds;
  final bool overrideTiming;

  const TempoState({
    this.bpm = 120,
    this.stepSeconds = 1.2,
    this.fadeSeconds = 0.3,
    this.overrideTiming = true,
  });

  Duration get hold => Duration(milliseconds: (stepSeconds * 1000).round());
  Duration get fade => Duration(milliseconds: (fadeSeconds * 1000).round());

  TempoState copyWith({double? bpm, double? stepSeconds, double? fadeSeconds, bool? overrideTiming}) {
    return TempoState(
      bpm: bpm ?? this.bpm,
      stepSeconds: stepSeconds ?? this.stepSeconds,
      fadeSeconds: fadeSeconds ?? this.fadeSeconds,
      overrideTiming: overrideTiming ?? this.overrideTiming,
    );
  }
}

class TempoNotifier extends StateNotifier<TempoState> {
  TempoNotifier() : super(const TempoState());

  /// Sets tempo from a BPM value, keeping [TempoState.stepSeconds] (what
  /// actually drives bank playback) in step with it.
  void setBpm(double bpm) {
    final clamped = bpm.clamp(20.0, 300.0);
    state = state.copyWith(bpm: clamped, stepSeconds: (60 / clamped).clamp(0.0, 5.0));
  }

  void setStepSeconds(double seconds) {
    final clamped = seconds.clamp(0.0, 5.0);
    state = state.copyWith(
      stepSeconds: clamped,
      bpm: clamped <= 0 ? state.bpm : (60 / clamped).clamp(20.0, 300.0),
    );
  }

  void setFadeSeconds(double seconds) => state = state.copyWith(fadeSeconds: seconds.clamp(0.0, 5.0));

  void setOverrideTiming(bool value) => state = state.copyWith(overrideTiming: value);
}

final tempoProvider = StateNotifierProvider<TempoNotifier, TempoState>((ref) => TempoNotifier());
