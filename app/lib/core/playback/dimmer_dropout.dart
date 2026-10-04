import 'dart:math';
import 'dart:typed_data';

/// A dimmer dropout: the light goes dark for a moment, now and then, while
/// whatever else the layer is doing — a slow pan, a colour fade — carries on.
///
/// Like the momentary effects it is an *output* effect: it changes the frame on
/// its way to the node and never touches the buffers the show writes into, so
/// when the dark ends the layer is simply where it would have been.
class DropoutSettings {
  final bool enabled;

  /// Layers the dropout cuts. Empty means every layer, and also channels no
  /// layer owns (a scene fired by hand).
  final Set<String> targetLayerIds;

  /// Fixtures it cuts. Empty means every fixture on the chosen layers.
  final Set<String> fixtureIds;

  /// How long the dark lasts.
  final int lengthMs;

  /// The average time between two dropouts, dark included.
  final int intervalMs;

  /// 0 is a metronome, 1 swings each gap between none and double the average.
  final double jitter;

  const DropoutSettings({
    this.enabled = false,
    this.targetLayerIds = const {},
    this.fixtureIds = const {},
    this.lengthMs = 120,
    this.intervalMs = 4000,
    this.jitter = 0.5,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'targetLayerIds': targetLayerIds.toList(),
    'fixtureIds': fixtureIds.toList(),
    'lengthMs': lengthMs,
    'intervalMs': intervalMs,
    'jitter': jitter,
  };

  /// Tolerant of a missing or hand-edited entry: anything absent or out of
  /// range falls back to the default rather than failing the whole project.
  factory DropoutSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DropoutSettings();
    const base = DropoutSettings();
    return DropoutSettings(
      enabled: json['enabled'] as bool? ?? false,
      targetLayerIds: {...(json['targetLayerIds'] as List? ?? []).whereType<String>()},
      fixtureIds: {...(json['fixtureIds'] as List? ?? []).whereType<String>()},
      lengthMs: ((json['lengthMs'] as num?)?.round() ?? base.lengthMs).clamp(minLengthMs, maxLengthMs),
      intervalMs: ((json['intervalMs'] as num?)?.round() ?? base.intervalMs).clamp(minIntervalMs, maxIntervalMs),
      jitter: ((json['jitter'] as num?)?.toDouble() ?? base.jitter).clamp(0.0, 1.0),
    );
  }

  static const minLengthMs = 30;
  static const maxLengthMs = 500;
  static const minIntervalMs = 500;
  static const maxIntervalMs = 20000;

  DropoutSettings copyWith({
    bool? enabled,
    Set<String>? targetLayerIds,
    Set<String>? fixtureIds,
    int? lengthMs,
    int? intervalMs,
    double? jitter,
  }) => DropoutSettings(
    enabled: enabled ?? this.enabled,
    targetLayerIds: targetLayerIds ?? this.targetLayerIds,
    fixtureIds: fixtureIds ?? this.fixtureIds,
    lengthMs: lengthMs ?? this.lengthMs,
    intervalMs: intervalMs ?? this.intervalMs,
    jitter: jitter ?? this.jitter,
  );
}

/// How long the light stays up before the next dropout.
///
/// The dark is part of [DropoutSettings.intervalMs], so the lit part is what's
/// left once it is taken off — and never shorter than a frame or two, or a
/// jittery setting would chain dropouts into one long blackout.
Duration dropoutGap(DropoutSettings settings, Random random) {
  final lit = settings.intervalMs - settings.lengthMs;
  final swing = (random.nextDouble() * 2 - 1) * settings.jitter.clamp(0.0, 1.0);
  final gap = (lit * (1 + swing)).round();
  return Duration(milliseconds: max(gap, 60));
}

/// [frame] with [dark] taken to zero. Returns [frame] itself when there is
/// nothing to cut, so the normal case allocates nothing. Never writes into
/// [frame].
Uint8List applyDropout(Uint8List frame, Set<int> dark) {
  if (dark.isEmpty) return frame;
  final out = Uint8List.fromList(frame);
  for (final channel in dark) {
    if (channel >= 0 && channel < out.length) out[channel] = 0;
  }
  return out;
}
