import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show setEquals;

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

  /// How long the light takes to fade down to dark before the dark itself
  /// starts. 0 is a hard cut.
  final int fadeOutMs;

  /// How long the light takes to come back up after the dark. 0 is a hard cut.
  final int fadeInMs;

  /// The average time between two dropouts, dark included.
  final int intervalMs;

  /// 0 is a metronome, 1 swings each gap between none and double the average.
  final double jitter;

  /// Dark on the beat instead of on a timer: every [beatEvery]-th beat the
  /// light drops for [lengthMs]. [intervalMs] and [jitter] then do nothing.
  /// With no beat source listening it carries on by the timer, so a lost
  /// detector does not silently switch the effect off.
  final bool onBeat;

  /// Which beats drop the light when [onBeat]: every 1st, 2nd, 4th or 8th.
  final int beatEvery;

  const DropoutSettings({
    this.enabled = false,
    this.targetLayerIds = const {},
    this.fixtureIds = const {},
    this.lengthMs = 120,
    this.fadeOutMs = 0,
    this.fadeInMs = 0,
    this.intervalMs = 4000,
    this.jitter = 0.5,
    this.onBeat = false,
    this.beatEvery = 1,
  });

  // By value: a Smart Program hands its zone's settings over on every zone
  // play, and the controller must be able to tell "same again" from a change
  // or it would restart the dropout's timer each time.
  @override
  bool operator ==(Object other) =>
      other is DropoutSettings &&
      other.enabled == enabled &&
      other.lengthMs == lengthMs &&
      other.fadeOutMs == fadeOutMs &&
      other.fadeInMs == fadeInMs &&
      other.intervalMs == intervalMs &&
      other.jitter == jitter &&
      other.onBeat == onBeat &&
      other.beatEvery == beatEvery &&
      setEquals(other.targetLayerIds, targetLayerIds) &&
      setEquals(other.fixtureIds, fixtureIds);

  @override
  int get hashCode => Object.hash(
    enabled,
    lengthMs,
    fadeOutMs,
    fadeInMs,
    intervalMs,
    jitter,
    onBeat,
    beatEvery,
    Object.hashAllUnordered(targetLayerIds),
    Object.hashAllUnordered(fixtureIds),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'targetLayerIds': targetLayerIds.toList(),
    'fixtureIds': fixtureIds.toList(),
    'lengthMs': lengthMs,
    'fadeOutMs': fadeOutMs,
    'fadeInMs': fadeInMs,
    'intervalMs': intervalMs,
    'jitter': jitter,
    'onBeat': onBeat,
    'beatEvery': beatEvery,
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
      fadeOutMs: ((json['fadeOutMs'] as num?)?.round() ?? base.fadeOutMs).clamp(0, maxFadeOutMs),
      fadeInMs: ((json['fadeInMs'] as num?)?.round() ?? base.fadeInMs).clamp(0, maxFadeInMs),
      intervalMs: ((json['intervalMs'] as num?)?.round() ?? base.intervalMs).clamp(minIntervalMs, maxIntervalMs),
      jitter: ((json['jitter'] as num?)?.toDouble() ?? base.jitter).clamp(0.0, 1.0),
      onBeat: json['onBeat'] as bool? ?? false,
      beatEvery: beatDivisions.contains(json['beatEvery']) ? json['beatEvery'] as int : 1,
    );
  }

  static const beatDivisions = [1, 2, 4, 8];
  static const minLengthMs = 30;
  static const maxLengthMs = 500;
  static const maxFadeOutMs = 1000;
  static const maxFadeInMs = maxFadeOutMs;
  static const minIntervalMs = 500;
  static const maxIntervalMs = 20000;

  DropoutSettings copyWith({
    bool? enabled,
    Set<String>? targetLayerIds,
    Set<String>? fixtureIds,
    int? lengthMs,
    int? fadeOutMs,
    int? fadeInMs,
    int? intervalMs,
    double? jitter,
    bool? onBeat,
    int? beatEvery,
  }) => DropoutSettings(
    enabled: enabled ?? this.enabled,
    targetLayerIds: targetLayerIds ?? this.targetLayerIds,
    fixtureIds: fixtureIds ?? this.fixtureIds,
    lengthMs: lengthMs ?? this.lengthMs,
    fadeOutMs: fadeOutMs ?? this.fadeOutMs,
    fadeInMs: fadeInMs ?? this.fadeInMs,
    intervalMs: intervalMs ?? this.intervalMs,
    jitter: jitter ?? this.jitter,
    onBeat: onBeat ?? this.onBeat,
    beatEvery: beatEvery ?? this.beatEvery,
  );
}

/// How long the light stays up before the next dropout.
///
/// The dark is part of [DropoutSettings.intervalMs], so the lit part is what's
/// left once it is taken off — and never shorter than a frame or two, or a
/// jittery setting would chain dropouts into one long blackout.
Duration dropoutGap(DropoutSettings settings, Random random) {
  final lit = settings.intervalMs - settings.lengthMs - settings.fadeOutMs - settings.fadeInMs;
  final swing = (random.nextDouble() * 2 - 1) * settings.jitter.clamp(0.0, 1.0);
  final gap = (lit * (1 + swing)).round();
  return Duration(milliseconds: max(gap, 60));
}

/// [frame] with [dark] taken to zero and each [dim] channel scaled by its
/// gain (0..1, a dropout part-way through its fade-out). Returns [frame]
/// itself when there is nothing to cut, so the normal case allocates nothing.
/// Never writes into [frame].
Uint8List applyDropout(Uint8List frame, Set<int> dark, [Map<int, double>? dim]) {
  if (dark.isEmpty && (dim == null || dim.isEmpty)) return frame;
  final out = Uint8List.fromList(frame);
  dim?.forEach((channel, gain) {
    if (channel >= 0 && channel < out.length) out[channel] = (out[channel] * gain.clamp(0.0, 1.0)).round();
  });
  for (final channel in dark) {
    if (channel >= 0 && channel < out.length) out[channel] = 0;
  }
  return out;
}
